import 'package:flutter/foundation.dart';
import '../models/staff_member.dart';
import 'api_client.dart';

export '../models/staff_member.dart';

class StaffService {
  StaffService._();
  static final instance = StaffService._();
  final _dio = ApiClient.instance.dio;

  /// Live staff list — the real source of truth. `update()`/`create()`/
  /// `delete()` patch this immediately on success, so every screen that
  /// renders from it (via ValueListenableBuilder) reflects a change the
  /// instant it happens, without needing to navigate away and back.
  final ValueNotifier<List<StaffMember>> staffNotifier = ValueNotifier<List<StaffMember>>([]);

  /// Last activity per staff id, refreshed by every fetch and background
  /// poll. Kept apart from [staffNotifier] because it ticks on every request
  /// an active user makes: only the "Last active" cells listen to it, so a
  /// poll doesn't rebuild every staff screen just to move a timestamp.
  final ValueNotifier<Map<int, DateTime?>> lastActiveNotifier =
      ValueNotifier<Map<int, DateTime?>>({});

  bool _loaded = false;
  Future<List<StaffMember>>? _inflight;

  /// Returns the live list; fetches once per session unless [force].
  /// [force] bypasses both this in-memory flag AND the HTTP cache layer —
  /// this app's cache is per-process (in-memory only, never persisted or
  /// invalidated across devices/sessions), so another device creating a
  /// staff member is invisible here until a force-refresh, even after a
  /// logout/login within the same running process.
  /// Pass [group] for a one-off filtered fetch that bypasses/doesn't
  /// affect the shared cache (used sparingly — most callers want the
  /// unfiltered live list and filter client-side).
  Future<List<StaffMember>> list({String? group, bool force = false}) async {
    if (group != null) return _fetch(group: group);
    if (!force && _loaded) return staffNotifier.value;
    if (!force && _inflight != null) return _inflight!;

    final future = _fetch(noCache: force);
    _inflight = future;
    try {
      final result = await future;
      _applyIfChanged(result);
      _loaded = true;
      _inflight = null;
      return result;
    } catch (_) {
      _inflight = null;
      rethrow;
    }
  }

  Future<List<StaffMember>> _fetch({String? group, bool noCache = false}) async {
    final res = await _dio.get('/staff',
      queryParameters: {'group': ?group},
      options: noCache ? ApiClient.noCache : null,
    );
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => StaffMember.fromJson(j as Map<String, dynamic>)).toList();
    if (group == null) _applyLastActive(list);
    return list;
  }

  void _applyLastActive(List<StaffMember> fresh) {
    final current = lastActiveNotifier.value;
    final next = {for (final m in fresh) m.id: m.lastActiveAt};
    final changed = next.length != current.length ||
        next.entries.any((e) => current[e.key] != e.value);
    if (changed) lastActiveNotifier.value = next;
  }

  // Only reassigns staffNotifier.value (and so only fires its listeners)
  // when the fetched list actually differs from what's cached — a
  // ValueNotifier notifies on every assignment regardless of content, so
  // without this a poll() tick would rebuild every staff-list screen every
  // interval even when nothing changed.
  void _applyIfChanged(List<StaffMember> fresh) {
    final current = staffNotifier.value;
    final changed = fresh.length != current.length || List.generate(
      fresh.length, (i) => fresh[i].syncSignature != current[i].syncSignature,
    ).contains(true);
    if (changed) staffNotifier.value = fresh;
  }

  /// Background-poll entry point — fetches straight from the server
  /// (bypassing cache) and updates staffNotifier only if something
  /// actually changed, so another device's edit shows up here without
  /// this device needing a manual refresh. Silently no-ops on failure —
  /// a transient blip on a 20s poll shouldn't surface an error toast.
  Future<void> poll() async {
    try {
      final fresh = await _fetch(noCache: true);
      _applyIfChanged(fresh);
      _loaded = true;
    } catch (_) {}
  }

  /// Forces the next list() to re-fetch. Rarely needed now that
  /// create/update/delete patch staffNotifier directly — kept for callers
  /// that mutate staff through some other path (e.g. role/permission
  /// changes made via the Role Builder, not this service).
  void invalidateCache() { _loaded = false; }

  Future<StaffMember> get(int id) async {
    final res = await _dio.get('/staff/$id');
    return StaffMember.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<StaffMember> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/staff', data: data);
    final created = StaffMember.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    staffNotifier.value = [...staffNotifier.value, created];
    return created;
  }

  Future<StaffMember> update(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/staff/$id', data: data);
    final updated = StaffMember.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    staffNotifier.value = [
      for (final m in staffNotifier.value) if (m.id == id) updated else m,
    ];
    return updated;
  }

  Future<void> delete(int id) async {
    await _dio.delete('/staff/$id');
    staffNotifier.value = staffNotifier.value.where((m) => m.id != id).toList();
  }

  /// Resets the member's password back to the default they were invited with.
  Future<void> resetPassword(int id) => _dio.post('/staff/$id/reset-password');
}
