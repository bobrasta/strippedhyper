import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'local_db.dart';

/// Remembers the server's IP address so a connection can skip DNS.
///
/// On some networks resolving api.hypermed.co.tz takes ~5.5 s, and Dart's
/// HttpClient resolves again for every new connection. The last good
/// address is kept in kv('app') and used straight away at startup; a fresh
/// lookup runs in the background at most every [refreshEvery]. A failed
/// connect drops the address and retries that connection through DNS.
class HostAddressCache {
  HostAddressCache._();
  static final instance = HostAddressCache._();

  static const refreshEvery = Duration(minutes: 30);
  static const ipConnectTimeout = Duration(seconds: 5);

  final _ips = <String, String>{};
  final _resolvedAt = <String, DateTime>{};
  final _resolving = <String>{};

  static String _kvKey(String host) => 'dns:$host';

  /// The remembered address for [host], or null to use normal DNS. Starts a
  /// background re-resolve when the last one is older than [refreshEvery].
  String? ipFor(String host) {
    if (InternetAddress.tryParse(host) != null) return null;
    var ip = _ips[host];
    if (ip == null) {
      ip = LocalDb.instance?.getValue(LocalDb.appScope, _kvKey(host));
      if (ip != null) _ips[host] = ip;
    }
    final last = _resolvedAt[host];
    if (last == null || DateTime.now().difference(last) > refreshEvery) {
      unawaited(refresh(host));
    }
    return ip;
  }

  /// Drops [host]'s address (it stopped answering) and resolves afresh.
  void forget(String host) {
    _ips.remove(host);
    _resolvedAt.remove(host);
    try {
      LocalDb.instance?.removeValue(LocalDb.appScope, _kvKey(host));
    } catch (_) {}
    unawaited(refresh(host));
  }

  /// Resolves [host] and remembers its first IPv4 address (else the first).
  Future<void> refresh(String host) async {
    if (!_resolving.add(host)) return;
    try {
      final found = await InternetAddress.lookup(host);
      if (found.isEmpty) return;
      final pick = found.firstWhere(
        (a) => a.type == InternetAddressType.IPv4,
        orElse: () => found.first,
      );
      _ips[host] = pick.address;
      _resolvedAt[host] = DateTime.now();
      LocalDb.instance?.setValue(LocalDb.appScope, _kvKey(host), pick.address);
    } catch (e) {
      dev.log('lookup $host failed: $e', name: 'DNS');
    } finally {
      _resolving.remove(host);
    }
  }

  /// HttpClient.connectionFactory: direct connections go to the remembered
  /// IP (TLS still verifies the certificate against, and sends SNI for, the
  /// hostname); anything unexpected falls back to a normal connect.
  Future<ConnectionTask<Socket>> connect(Uri uri, String? proxyHost, int? proxyPort) async {
    if (proxyHost != null && proxyPort != null) {
      return Socket.startConnect(proxyHost, proxyPort);
    }
    final secure = uri.scheme == 'https';
    final host = uri.host;
    final port = uri.port;
    Future<ConnectionTask<Socket>> plain() =>
        secure ? SecureSocket.startConnect(host, port) : Socket.startConnect(host, port);
    try {
      final ip = ipFor(host);
      if (ip == null) return await plain();
      final task = await Socket.startConnect(ip, port);
      // A dead address can hang until the OS gives up; a live one answers
      // in well under a second, so don't let it eat Dio's 20 s budget.
      final connected = task.socket.timeout(ipConnectTimeout, onTimeout: () {
        task.cancel();
        throw const SocketException('Remembered address timed out');
      });
      final socket = connected.then<Socket>((s) async {
        if (!secure) return s;
        try {
          return await SecureSocket.secure(s, host: host);
        } catch (_) {
          s.destroy();
          rethrow;
        }
      }).catchError((Object e, StackTrace st) async {
        // Connect refused / timed out / wrong certificate: this address is
        // no good any more. Drop it and connect the normal way instead.
        if (e is! SocketException && e is! TlsException) Error.throwWithStackTrace(e, st);
        forget(host);
        return (await plain()).socket;
      });
      return ConnectionTask.fromSocket(socket, task.cancel);
    } catch (_) {
      return await plain();
    }
  }
}
