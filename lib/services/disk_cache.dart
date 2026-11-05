import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart';

import 'local_db.dart';

/// [FusedTransformer] (Dio's default, decoding ≥ 50 KB bodies off the UI
/// isolate) that also keeps the raw bytes of JSON GET bodies in
/// `requestOptions.extra[rawBytesKey]`, so [DiskCacheInterceptor] can store
/// them as-is instead of re-encoding a big decoded list on the UI thread.
class RawBytesTransformer extends FusedTransformer {
  RawBytesTransformer() : super(contentLengthIsolateThreshold: 50 * 1024);

  static const rawBytesKey = 'hm_raw_bytes';

  @override
  Future<dynamic> transformResponse(RequestOptions options, ResponseBody responseBody) async {
    final contentType = responseBody.headers[Headers.contentTypeHeader]?.first;
    if (options.method != 'GET' ||
        options.responseType != ResponseType.json ||
        !Transformer.isJsonMimeType(contentType)) {
      return super.transformResponse(options, responseBody);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in responseBody.stream) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    options.extra[rawBytesKey] = bytes;
    responseBody.stream = Stream<Uint8List>.value(bytes);
    return super.transformResponse(options, responseBody);
  }
}

/// What the disk cache did for one response key.
sealed class DiskCacheEvent {
  const DiskCacheEvent(this.key);
  final String key;
}

/// A request was answered from disk and a background revalidation started.
class ServedFromDisk extends DiskCacheEvent {
  const ServedFromDisk(super.key);
}

/// The background revalidation for [key] finished; [changed] when the
/// network copy differs from what was served.
class Revalidated extends DiskCacheEvent {
  const Revalidated(super.key, {required this.changed});
  final bool changed;
}

/// Persistent stale-while-revalidate for JSON GETs.
///
/// The first time this app session asks for a key that has a disk copy
/// (younger than [maxAge]), the request resolves at once from disk and the
/// same request is re-sent in the background. When that returns it is
/// stored, and [events] reports whether it changed — the app shell uses that
/// to refresh the screen. Later requests for the key go to the network as
/// before, except within [freshWindow] of a revalidation, when the fresh disk
/// copy is served (a screen remounting to show the new data shouldn't fetch
/// it twice).
///
/// Mutations, `noCache` requests, auth/licence/update endpoints, searches and
/// non-JSON responses pass straight through.
class DiskCacheInterceptor extends Interceptor {
  DiskCacheInterceptor({
    required this.dio,
    required this.db,
    required this.userId,
    required this.revalidateExtra,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The Dio this interceptor is installed on (revalidations go through it).
  final Dio Function() dio;
  final LocalDb? Function() db;
  final int? Function() userId;
  /// Extra merged into a revalidation so the memory cache doesn't answer it.
  final Map<String, dynamic> revalidateExtra;
  final DateTime Function() _clock;

  static const maxAge = Duration(days: 14);
  static const freshWindow = Duration(seconds: 15);
  static const _revalidateKey = 'hm_disk_revalidate';
  static const fromDiskKey = 'hm_from_disk';

  static const _excludedPrefixes = ['/license/check', '/auth/', '/updates'];
  static const _searchParams = {'search', 'q', 'query', 'term', 'keyword'};

  final _fetched = <String>{};
  final _revalidatedAt = <String, DateTime>{};
  final _inFlight = <String>{};
  final _events = StreamController<DiskCacheEvent>.broadcast();

  Stream<DiskCacheEvent> get events => _events.stream;

  /// Forget which keys were fetched this session (e.g. on logout).
  void resetSession() {
    _fetched.clear();
    _revalidatedAt.clear();
  }

  /// `path?sorted&query`, or null when this request mustn't touch the disk.
  @visibleForTesting
  static String? keyFor(RequestOptions o) {
    if (o.method != 'GET' || o.responseType != ResponseType.json) return null;
    final uri = o.uri;
    final path = o.path.startsWith('http') ? uri.path : o.path;
    for (final p in _excludedPrefixes) {
      if (path.startsWith(p) || uri.path.contains('/api/v1$p')) return null;
    }
    final params = uri.queryParametersAll;
    for (final s in _searchParams) {
      final v = params[s];
      if (v != null && v.any((e) => e.trim().isNotEmpty)) return null;
    }
    if (params.isEmpty) return path;
    final names = params.keys.toList()..sort();
    final query = [
      for (final n in names)
        for (final v in params[n]!) '${Uri.encodeQueryComponent(n)}=${Uri.encodeQueryComponent(v)}',
    ].join('&');
    return '$path?$query';
  }

  static bool _isNoCache(RequestOptions o) =>
      CacheOptions.fromExtra(o)?.policy == CachePolicy.noCache;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final key = keyFor(options);
    final store = db();
    final uid = userId();
    if (key == null || store == null || uid == null ||
        options.extra[_revalidateKey] == true || _isNoCache(options)) {
      return handler.next(options);
    }
    try {
      final now = _clock();
      final last = _revalidatedAt[key];
      final recentlyRevalidated = last != null && now.difference(last) < freshWindow;
      if (_fetched.contains(key) && !recentlyRevalidated) return handler.next(options);
      final cached = store.getResponse(uid, key);
      if (cached == null || now.difference(cached.fetchedAt) > maxAge) return handler.next(options);
      final response = await _decode(options, cached.body);
      if (!recentlyRevalidated) {
        _events.add(ServedFromDisk(key));
        _revalidate(options, key, uid, cached.body);
      }
      return handler.resolve(response);
    } catch (e) {
      dev.log('disk cache read failed for $key: $e', name: 'DiskCache');
      return handler.next(options);
    }
  }

  Future<Response<dynamic>> _decode(RequestOptions options, Uint8List body) async {
    final headers = Headers.fromMap({
      Headers.contentTypeHeader: [Headers.jsonContentType],
      Headers.contentLengthHeader: ['${body.length}'],
    });
    final data = await dio().transformer.transformResponse(
      options,
      ResponseBody.fromBytes(body, 200, headers: headers.map),
    );
    options.extra.remove(RawBytesTransformer.rawBytesKey);
    options.extra[fromDiskKey] = true;
    return Response(requestOptions: options, data: data, statusCode: 200, headers: headers);
  }

  void _revalidate(RequestOptions options, String key, int uid, Uint8List served) {
    if (!_inFlight.add(key)) return;
    final extra = Map<String, dynamic>.of(options.extra)
      ..remove(fromDiskKey)
      ..remove(RawBytesTransformer.rawBytesKey)
      ..addAll(revalidateExtra)
      ..[_revalidateKey] = true;
    final request = options.copyWith(extra: extra);
    var changed = false;
    dio().fetch<dynamic>(request).then((res) {
      final bytes = res.requestOptions.extra[RawBytesTransformer.rawBytesKey];
      changed = res.statusCode == 200 && bytes is Uint8List && !listEquals(bytes, served);
    }).catchError((Object _) {}).whenComplete(() {
      _inFlight.remove(key);
      _revalidatedAt[key] = _clock();
      _events.add(Revalidated(key, changed: changed));
    });
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final o = response.requestOptions;
    final key = keyFor(o);
    final bytes = o.extra.remove(RawBytesTransformer.rawBytesKey);
    if (key != null && o.extra[fromDiskKey] != true) {
      _fetched.add(key);
      final store = db();
      final uid = userId();
      final json = Transformer.isJsonMimeType(response.headers.value(Headers.contentTypeHeader));
      if (store != null && uid != null && response.statusCode == 200 && json &&
          bytes is Uint8List && !_isNoCache(o)) {
        try {
          store.putResponse(uid, key, bytes, fetchedAt: _clock());
        } catch (e) {
          dev.log('disk cache write failed for $key: $e', name: 'DiskCache');
        }
      }
    }
    // Keep the bytes for the revalidation's own comparison.
    if (o.extra[_revalidateKey] == true && bytes != null) {
      o.extra[RawBytesTransformer.rawBytesKey] = bytes;
    }
    handler.next(response);
  }
}
