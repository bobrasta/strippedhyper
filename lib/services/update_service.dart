import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cg;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'setting_service.dart';

/// How updates are applied on this machine.
enum UpdateMode {
  /// Only notify — the user clicks "Update now".
  off,

  /// Download in the background, install on the next app start (or when the
  /// user clicks "Restart to update"). Never interrupts work. The default.
  auto,

  /// Download, give a 60s warning, then install + relaunch straight away.
  immediate;

  static UpdateMode? parse(String? v) =>
      UpdateMode.values.where((m) => m.name == v).firstOrNull;

  String get label => switch (this) {
    UpdateMode.off => 'Off — notify me only',
    UpdateMode.auto => 'Automatic — install on next start',
    UpdateMode.immediate => 'Automatic — install immediately',
  };
}

enum UpdatePhase { idle, checking, upToDate, available, downloading, ready, installing, error }

/// One platform's downloadable package in the feed.
class UpdateAsset {
  const UpdateAsset({required this.url, required this.sha256, this.size});
  final String url;
  final String sha256;
  final int? size;

  factory UpdateAsset.fromJson(Map<String, dynamic> j) => UpdateAsset(
    url: j['url'] as String,
    sha256: (j['sha256'] as String).toLowerCase(),
    size: (j['size'] as num?)?.toInt(),
  );
}

/// The `latest.json` feed published by the release pipeline
/// (.github/workflows/release.yml → tool/make_update_manifest.py).
class UpdateManifest {
  const UpdateManifest({
    required this.version,
    required this.minVersion,
    required this.notes,
    required this.asset,
    this.releasedAt,
  });
  final String version;
  // Anything older than this is blocked behind "Update required",
  // regardless of the update mode (e.g. after a breaking API change).
  final String? minVersion;
  final String notes;
  final UpdateAsset? asset; // null = no package for this platform
  final String? releasedAt;

  factory UpdateManifest.fromJson(Map<String, dynamic> j, String platform) {
    final platforms = (j['platforms'] as Map?)?.cast<String, dynamic>() ?? {};
    final a = platforms[platform];
    return UpdateManifest(
      version: j['version'] as String,
      minVersion: j['min_version'] as String?,
      notes: j['notes'] as String? ?? '',
      releasedAt: j['released_at'] as String?,
      asset: a is Map ? UpdateAsset.fromJson(a.cast<String, dynamic>()) : null,
    );
  }
}

@immutable
class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.manifest,
    this.progress,
    this.error,
    this.required = false,
    this.installAt,
  });
  final UpdatePhase phase;
  final UpdateManifest? manifest;
  final double? progress; // 0..1 while downloading
  final String? error;
  // Current version is below the feed's min_version.
  final bool required;
  // Immediate mode's countdown target.
  final DateTime? installAt;

  UpdateState copyWith({
    UpdatePhase? phase,
    UpdateManifest? manifest,
    double? progress,
    String? error,
    bool? required,
    DateTime? installAt,
    bool clearInstallAt = false,
  }) => UpdateState(
    phase: phase ?? this.phase,
    manifest: manifest ?? this.manifest,
    progress: progress,
    error: error,
    required: required ?? this.required,
    installAt: clearInstallAt ? null : (installAt ?? this.installAt),
  );
}

/// Checks the update feed, downloads + verifies packages, and installs them.
///
/// Windows: runs the Inno Setup installer silently (per-user install, so no
/// UAC prompt) — the installer closes this app, replaces it and relaunches.
/// Linux: extracts the tarball next to the current install and swaps the
/// directory from a detached helper script once this process exits.
class UpdateService {
  UpdateService._();
  static final instance = UpdateService._();

  static const feedUrl = String.fromEnvironment(
    'UPDATE_FEED_URL',
    defaultValue: 'https://app.hypermed.co.tz/updates/latest.json',
  );
  /// Ed25519 public keys allowed to sign latest.json (base64, raw 32
  /// bytes). The private half lives only in the release pipeline
  /// (UPDATE_SIGNING_KEY secret; backup at ~/.config/hypermed on the
  /// release machine) — see tool/sign_update_manifest.py. To rotate: add the
  /// new key here, ship a release signed with the OLD key, then switch the
  /// pipeline to the new key and drop the old one in a later release.
  static const trustedKeys = ['gs3MGeLeGciVoEC/ndTVQVbu7iov/CLZR48f7Un7i8Y='];
  static const checkInterval = Duration(minutes: 15);
  static const immediateGrace = Duration(seconds: 60);
  static const _modeKey = 'update_mode';
  static const _policyKey = 'app_update_policy';

  /// Updater only makes sense for installed desktop release builds.
  /// `--dart-define=FORCE_UPDATER=true` enables it in debug for testing.
  static bool get supported =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isLinux) &&
      (kReleaseMode || const bool.fromEnvironment('FORCE_UPDATER'));

  static String get _platform => Platform.isWindows ? 'windows' : 'linux';

  final state = ValueNotifier<UpdateState>(const UpdateState());
  final currentVersion = ValueNotifier<String>('');
  // This machine's own choice.
  final localMode = ValueNotifier<UpdateMode>(UpdateMode.auto);
  // Company-wide policy set by a Director (null = each user chooses).
  final policyMode = ValueNotifier<UpdateMode?>(null);

  UpdateMode get effectiveMode => policyMode.value ?? localMode.value;

  final _storage = const FlutterSecureStorage();
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(minutes: 10),
  ));
  Timer? _timer;
  Timer? _immediateTimer;
  bool _started = false;

  /// Call once at startup. Applies an already-downloaded update first (that
  /// is how "install on next start" works), then starts periodic checks.
  /// Returns true if the app is about to exit to install an update.
  Future<bool> start() async {
    final info = await PackageInfo.fromPlatform();
    currentVersion.value = info.version;
    if (!supported || _started) return false;
    _started = true;

    try {
      localMode.value = UpdateMode.parse(await _storage.read(key: _modeKey)) ?? UpdateMode.auto;
    } catch (_) {}

    if (await _applyPendingOnStartup()) return true;

    unawaited(check());
    _timer = Timer.periodic(checkInterval, (_) => check());
    return false;
  }

  Future<void> setLocalMode(UpdateMode mode) async {
    localMode.value = mode;
    try {
      await _storage.write(key: _modeKey, value: mode.name);
    } catch (_) {}
    _afterModeChange();
  }

  /// Reads the company-wide policy from backend settings (after login).
  Future<void> refreshPolicy() async {
    try {
      final all = await SettingService.instance.all();
      final v = all[_policyKey];
      policyMode.value = (v == null || v == 'user') ? null : UpdateMode.parse(v);
      _afterModeChange();
    } catch (_) {
      // Keep whatever we had — a failed fetch shouldn't unlock a policy.
    }
  }

  /// Director-only (enforced server-side). null = let each user choose.
  Future<void> setPolicy(UpdateMode? mode) async {
    await SettingService.instance.set(_policyKey, mode?.name ?? 'user');
    policyMode.value = mode;
    _afterModeChange();
  }

  void _afterModeChange() {
    final s = state.value;
    if (s.phase == UpdatePhase.available && effectiveMode != UpdateMode.off) {
      unawaited(download());
    } else if (s.phase == UpdatePhase.ready) {
      _scheduleImmediateIfNeeded();
    }
  }

  /// Fetches the feed. [userInitiated] re-checks even when an update is
  /// already downloaded (the "Check for updates" button).
  Future<void> check({bool userInitiated = false}) async {
    if (!supported) return;
    final phase = state.value.phase;
    if (phase == UpdatePhase.checking ||
        phase == UpdatePhase.downloading ||
        phase == UpdatePhase.installing) {
      return;
    }
    // Already downloaded and still the newest — nothing to do.
    if (phase == UpdatePhase.ready && !userInitiated) return;

    state.value = state.value.copyWith(phase: UpdatePhase.checking);
    try {
      final t = {'t': DateTime.now().millisecondsSinceEpoch};
      final body = await _dio.get<List<int>>(feedUrl,
          queryParameters: t, options: Options(responseType: ResponseType.bytes));
      final sig = await _dio.get<String>('$feedUrl.sig',
          queryParameters: t, options: Options(responseType: ResponseType.plain));
      final bytes = body.data!;
      if (!await verifyManifestSignature(bytes, sig.data ?? '')) {
        throw const _UpdateError('The update feed failed its signature check — update skipped.');
      }
      final m = UpdateManifest.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>, _platform);
      final current = currentVersion.value;
      final required = m.minVersion != null && compareVersions(current, m.minVersion!) < 0;

      if (compareVersions(m.version, current) <= 0 || m.asset == null) {
        state.value = UpdateState(phase: UpdatePhase.upToDate, manifest: m, required: required);
        return;
      }
      final existing = await _verifiedDownload(m);
      if (existing != null) {
        state.value = UpdateState(phase: UpdatePhase.ready, manifest: m, required: required);
        await _rememberPending();
        _scheduleImmediateIfNeeded();
        return;
      }
      state.value = UpdateState(phase: UpdatePhase.available, manifest: m, required: required);
      if (effectiveMode != UpdateMode.off || required) await download();
    } catch (e) {
      state.value = state.value.copyWith(phase: UpdatePhase.error, error: _friendly(e));
    }
  }

  Future<void> download() async {
    final m = state.value.manifest;
    final asset = m?.asset;
    if (m == null || asset == null || state.value.phase == UpdatePhase.downloading) return;

    state.value = state.value.copyWith(phase: UpdatePhase.downloading, progress: 0);
    try {
      final file = await _packageFile(m);
      final part = File('${file.path}.part');
      await _dio.download(
        asset.url,
        part.path,
        onReceiveProgress: (got, total) {
          final t = total > 0 ? total : (asset.size ?? 0);
          if (t > 0) state.value = state.value.copyWith(phase: UpdatePhase.downloading, progress: got / t);
        },
      );
      final digest = await sha256.bind(part.openRead()).first;
      if (digest.toString() != asset.sha256) {
        await part.delete();
        throw const _UpdateError('Downloaded update failed its integrity check — it will be retried.');
      }
      await finishDownload(part, file);
      state.value = state.value.copyWith(phase: UpdatePhase.ready);
      await _rememberPending();
      _scheduleImmediateIfNeeded();
    } catch (e) {
      state.value = state.value.copyWith(phase: UpdatePhase.error, error: _friendly(e));
    }
  }

  void _scheduleImmediateIfNeeded() {
    _immediateTimer?.cancel();
    if (state.value.phase != UpdatePhase.ready) return;
    if (effectiveMode != UpdateMode.immediate) {
      if (state.value.installAt != null) state.value = state.value.copyWith(clearInstallAt: true);
      return;
    }
    final at = DateTime.now().add(immediateGrace);
    state.value = state.value.copyWith(installAt: at);
    _immediateTimer = Timer(immediateGrace, () => installNow());
  }

  /// Postpone an immediate-mode install to the next app start.
  void postpone() {
    _immediateTimer?.cancel();
    state.value = state.value.copyWith(clearInstallAt: true);
  }

  /// Installs the downloaded package and exits this process.
  Future<void> installNow() async {
    final m = state.value.manifest;
    if (m == null) return;
    final file = await _verifiedDownload(m);
    if (file == null) {
      state.value = state.value.copyWith(phase: UpdatePhase.available);
      return download();
    }
    state.value = state.value.copyWith(phase: UpdatePhase.installing);
    try {
      await _launchInstaller(file);
      // Give the detached process a moment to start before we exit.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      exit(0);
    } catch (e) {
      state.value = state.value.copyWith(phase: UpdatePhase.error, error: _friendly(e));
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<Directory> _updatesDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}updates');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _packageFile(UpdateManifest m) async {
    final name = Uri.parse(m.asset!.url).pathSegments.last;
    return File('${(await _updatesDir()).path}${Platform.pathSeparator}$name');
  }

  Future<File?> _verifiedDownload(UpdateManifest m) async {
    if (m.asset == null) return null;
    final f = await _packageFile(m);
    if (!await f.exists()) return null;
    final digest = await sha256.bind(f.openRead()).first;
    return digest.toString() == m.asset!.sha256 ? f : null;
  }


  // A package downloaded in a previous session, newer than what's running,
  // gets installed before the UI appears ("install on next start").
  Future<bool> _applyPendingOnStartup() async {
    try {
      final dir = await _updatesDir();
      final pendingFile = File('${dir.path}${Platform.pathSeparator}pending.json');
      if (!await pendingFile.exists()) return false;
      final raw = await pendingFile.readAsString();
      final parts = raw.split('\n');
      if (parts.length < 3) return false;
      final (version, path, hash) = (parts[0], parts[1], parts[2]);
      final f = File(path);
      if (compareVersions(version, currentVersion.value) <= 0 || !await f.exists()) {
        await pendingFile.delete();
        return false;
      }
      if (effectiveMode == UpdateMode.off) return false;
      final digest = await sha256.bind(f.openRead()).first;
      if (digest.toString() != hash) {
        await pendingFile.delete();
        return false;
      }
      await pendingFile.delete();
      await _launchInstaller(f);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Remember the ready package so the next start installs it. Called
  /// whenever a download completes (see [download]/[check]).
  Future<void> _rememberPending() async {
    final m = state.value.manifest;
    if (m == null) return;
    final f = await _verifiedDownload(m);
    if (f == null) return;
    final dir = await _updatesDir();
    await File('${dir.path}${Platform.pathSeparator}pending.json')
        .writeAsString('${m.version}\n${f.path}\n${m.asset!.sha256}');
  }

  Future<void> _launchInstaller(File pkg) async {
    if (Platform.isWindows) {
      // Inno Setup: silent, closes the running app, relaunches after (see
      // installer/windows/hypermed.iss — the skipifnotsilent [Run] entry).
      await Process.start(
        pkg.path,
        ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/FORCECLOSEAPPLICATIONS'],
        mode: ProcessStartMode.detached,
      );
      return;
    }
    // Linux: extract next to the install, then swap directories once this
    // process has exited, and relaunch.
    final exe = File(Platform.resolvedExecutable);
    final installDir = exe.parent;
    final parent = installDir.parent;
    final staging = Directory('${parent.path}/.hypermed-update-$pid');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create();
    final tar = await Process.run('tar', ['-xzf', pkg.path, '-C', staging.path, '--strip-components=1']);
    if (tar.exitCode != 0) throw _UpdateError('Could not unpack the update: ${tar.stderr}');
    final exeName = exe.uri.pathSegments.last;
    final script = '''
while kill -0 $pid 2>/dev/null; do sleep 0.3; done
rm -rf "${installDir.path}.old"
mv "${installDir.path}" "${installDir.path}.old" && mv "${staging.path}" "${installDir.path}" && rm -rf "${installDir.path}.old"
nohup "${installDir.path}/$exeName" >/dev/null 2>&1 &
''';
    await Process.start('sh', ['-c', script], mode: ProcessStartMode.detached);
  }

  String _friendly(Object e) {
    if (e is _UpdateError) return e.message;
    if (e is DioException) {
      if (e.response?.statusCode == 404) return 'No update feed published yet.';
      return 'Could not reach the update server.';
    }
    if (e is FileSystemException) {
      final os = e.osError?.message.trim();
      return 'Could not write the update: ${e.message}${os == null || os.isEmpty ? '' : ' ($os)'}';
    }
    return e.toString();
  }

  void dispose() {
    _timer?.cancel();
    _immediateTimer?.cancel();
  }
}

class _UpdateError implements Exception {
  const _UpdateError(this.message);
  final String message;
}

/// True when [signatureB64] is a valid Ed25519 signature of [manifest] by
/// any of [UpdateService.trustedKeys] (or [keys], for tests).
/// Puts a verified download ([part]) in place as [package], then removes
/// older packages from the updates folder. The order matters: cleaning first
/// deleted the .part itself (it isn't [package]), so every update failed
/// with "Cannot rename file to …" (v1.1.0-v1.1.4).
@visibleForTesting
Future<void> finishDownload(File part, File package) async {
  await moveIntoPlace(part, package);
  await for (final e in package.parent.list()) {
    if (e is File && e.path != package.path && !e.path.endsWith('.json')) {
      try {
        await e.delete();
      } catch (_) {}
    }
  }
}

/// Moves a verified download to its final name. On Windows a rename fails
/// while anything holds either file open — typically antivirus scanning the
/// freshly written installer, or an old copy of it still in use — so this
/// retries for a while, then falls back to copying, which only needs to read
/// the source.
@visibleForTesting
Future<void> moveIntoPlace(File part, File target, {int attempts = 8, Duration delay = const Duration(milliseconds: 750)}) async {
  FileSystemException? last;
  for (var i = 0; i < attempts; i++) {
    try {
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      return;
    } on FileSystemException catch (e) {
      last = e;
      if (i < attempts - 1) await Future<void>.delayed(delay);
    }
  }
  try {
    await part.copy(target.path);
  } on FileSystemException {
    throw last!;
  }
  try {
    await part.delete();
  } catch (_) {} // a stray .part is cleaned up with the next update
}

Future<bool> verifyManifestSignature(List<int> manifest, String signatureB64, {List<String>? keys}) async {
  final List<int> sig;
  try {
    sig = base64.decode(signatureB64.trim());
  } catch (_) {
    return false;
  }
  if (sig.length != 64) return false;
  final algo = cg.Ed25519();
  for (final k in keys ?? UpdateService.trustedKeys) {
    final pub = cg.SimplePublicKey(base64.decode(k), type: cg.KeyPairType.ed25519);
    if (await algo.verify(manifest, signature: cg.Signature(sig, publicKey: pub))) return true;
  }
  return false;
}

/// Compares dotted numeric versions ("1.10.0" > "1.9.3"); ignores any
/// "+build" / "-suffix". Negative if a < b.
int compareVersions(String a, String b) {
  List<int> parse(String v) => v
      .split(RegExp(r'[+-]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p.trim()) ?? 0)
      .toList();
  final pa = parse(a), pb = parse(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}
