import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

import '../main.dart'
    show emailBadgeNotifier, notificationCountNotifier, refreshPermissions, userIdNotifier;
import '../models/email.dart';
import '../models/email_account.dart';
import '../models/notification.dart';
import 'auth_service.dart';
import 'email_account_service.dart';
import 'email_service.dart';
import 'local_db.dart';
import 'notification_service.dart';
import 'phone_notifications.dart';
import 'shell_navigation.dart';
import 'staff_service.dart';

/// One desktop pop-up: what it says and where clicking it goes.
class SyncToast {
  const SyncToast(this.title, this.body, {this.screen, this.notification});
  final String title;
  final String body;
  /// Nav key to open on click…
  final String? screen;
  /// …or a notification to route like the bell does.
  final AppNotification? notification;
}

/// Polls for what's new while the shell is open and announces it.
///
/// "Last seen" markers (highest notification id, highest email id per
/// account) are kept per user in kv, so a restart
/// doesn't repeat pop-ups, but anything that arrived while the app was
/// closed is announced once at startup. The very first run only records
/// the markers.
class BackgroundSync {
  @visibleForTesting
  BackgroundSync({this._toaster, LocalDb? Function()? db})
      : _db = db ?? (() => LocalDb.instance);

  static final instance = BackgroundSync();

  static const firstPollDelay        = Duration(seconds: 3);
  static const notificationsInterval = Duration(seconds: 20);
  static const emailInterval         = Duration(seconds: 30);
  static const _accountsRefresh      = Duration(minutes: 5);
  /// More new items than this in one poll → one summary pop-up.
  static const maxSingleToasts = 3;

  final void Function(SyncToast)? _toaster;
  final LocalDb? Function() _db;

  final _timers = <Timer>[];
  bool _running = false;
  int _generation = 0; // a stop()/start() pair mustn't leave two loops
  bool _emailBusy = false;
  int? _userId;
  List<EmailAccount>? _accounts;
  DateTime? _accountsAt;
  final _markers = <String, int?>{};

  Future<void> start() async {
    if (_running) return;
    _running = true;
    final generation = ++_generation;
    // Let the landing screen have the network first.
    _timers.add(Timer(firstPollDelay, () => _begin(generation)));
  }

  void stop() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _running = false;
    _emailBusy = false;
    _accounts = null;
    _accountsAt = null;
    _markers.clear();
    _userId = null;
  }

  Future<void> _begin(int generation) async {
    final userId = userIdNotifier.value ?? await _resolveUserId();
    if (!_running || generation != _generation) return;
    _userId = userId;
    unawaited(_pollNotifications());
    unawaited(_pollEmail());
    _timers
      ..add(Timer.periodic(notificationsInterval, (_) => _pollNotifications()))
      ..add(Timer.periodic(emailInterval, (_) => _pollEmail()));
  }

  Future<int?> _resolveUserId() async {
    try {
      final p = await AuthService.instance.getProfile();
      return (p?['id'] as num?)?.toInt();
    } catch (_) { return null; }
  }

  // ── Markers ────────────────────────────────────────────────────────────────

  @visibleForTesting
  set debugUserId(int? id) => _userId = id;

  int? _marker(String key) {
    if (_markers.containsKey(key)) return _markers[key];
    int? value;
    final uid = _userId;
    if (uid != null) {
      try {
        value = int.tryParse(_db()?.getValue('$uid', key) ?? '');
      } catch (_) {}
    }
    return _markers[key] = value;
  }

  void _setMarker(String key, int value) {
    if (_markers[key] == value) return;
    _markers[key] = value;
    final uid = _userId;
    if (uid == null) return;
    try {
      _db()?.setValue('$uid', key, '$value');
    } catch (_) {}
  }

  /// Items newer than [marker], oldest first, and the marker to keep. A null
  /// marker (first run) only sets the baseline — nothing counts as new.
  @visibleForTesting
  static (List<T>, int) diffNew<T>(Iterable<T> items, int Function(T) idOf, int? marker) {
    final maxId = items.isEmpty ? null : items.map(idOf).reduce(max);
    if (marker == null) return (<T>[], maxId ?? 0);
    final fresh = items.where((x) => idOf(x) > marker).toList()
      ..sort((a, b) => idOf(a).compareTo(idOf(b)));
    return (fresh, max(marker, maxId ?? marker));
  }

  // ── Notifications (20 s) ─────────────────────────────────────────────────

  Future<void> _pollNotifications() async {
    await Future.wait([
      () async {
        try {
          handleNotifications(await NotificationService.instance.list(noCache: true));
        } catch (_) {}
      }(),
      StaffService.instance.poll(),
      // A role's permissions (or an individual override) can change while
      // this user is mid-session — pick that up without a re-login.
      () async {
        try {
          await refreshPermissions();
        } catch (_) {}
      }(),
    ]);
  }

  @visibleForTesting
  void handleNotifications(List<AppNotification> items) {
    notificationCountNotifier.value = items.where((n) => !n.isRead).length;
    const key = 'seen.notifications';
    final (fresh, marker) = diffNew(items, (n) => n.id, _marker(key));
    _setMarker(key, marker);
    final unread = fresh.where((n) => !n.isRead).toList();
    if (unread.isEmpty) return;
    if (unread.length > maxSingleToasts) {
      _toast(SyncToast('${unread.length} new notifications', 'Open Hypermed to see them.',
          screen: 'notifications'));
      return;
    }
    for (final n in unread) {
      _toast(SyncToast(
        n.title.isNotEmpty ? n.title : n.type.label,
        n.body,
        notification: n,
      ));
    }
  }

  // ── Email (30 s) ───────────────────────────────────────────────────────────

  /// The API only pulls mail when asked (POST /emails/sync), so ask for each
  /// of the user's accounts, then look at the unread inbox.
  Future<void> _pollEmail() async {
    if (_emailBusy) return; // the previous sync is still running
    _emailBusy = true;
    try {
      final now = DateTime.now();
      if (_accounts == null || _accountsAt == null || now.difference(_accountsAt!) > _accountsRefresh) {
        _accounts = await EmailAccountService.instance.list(noCache: true);
        _accountsAt = now;
      }
      final accounts = _accounts!;
      if (accounts.isEmpty) return;
      final unreadByAccount = <int, List<Email>>{};
      await Future.wait(accounts.map((a) async {
        try {
          await EmailService.instance.sync(accountId: a.id, folder: 'INBOX', limit: 20);
        } catch (_) {
          // 422 (IMAP refused / not configured) and timeouts: still show
          // whatever the server already has.
        }
        try {
          unreadByAccount[a.id] = await EmailService.instance.inbox(
              unread: true, accountId: a.id, noCache: true);
        } catch (_) {}
      }));
      handleEmails(unreadByAccount);
      final unread = await EmailService.instance.unreadCount(noCache: true);
      emailBadgeNotifier.value = (unread: unread, failed: emailBadgeNotifier.value.failed);
    } catch (_) {
    } finally {
      _emailBusy = false;
    }
  }

  @visibleForTesting
  void handleEmails(Map<int, List<Email>> unreadByAccount) {
    final fresh = <Email>[];
    for (final MapEntry(key: accountId, value: emails) in unreadByAccount.entries) {
      final key = 'seen.email.$accountId';
      final (newOnes, marker) = diffNew(emails, (e) => e.id, _marker(key));
      _setMarker(key, marker);
      fresh.addAll(newOnes);
    }
    if (fresh.isEmpty) return;
    if (fresh.length > maxSingleToasts) {
      _toast(SyncToast('${fresh.length} new emails', 'Open Email to read them.', screen: 'email'));
      return;
    }
    for (final e in fresh) {
      _toast(SyncToast('New email from ${e.from}', e.subject, screen: 'email'));
    }
  }

  // ── Toasts ─────────────────────────────────────────────────────────────────

  static bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  void _toast(SyncToast t) {
    final toaster = _toaster;
    if (toaster != null) return toaster(t);
    if (Platform.isAndroid) {
      // A notification routes like the bell; others open their screen.
      final screen = t.screen ?? (t.notification != null ? 'notifications' : null);
      unawaited(PhoneNotifications.instance.showGeneral(t.title, t.body, screen: screen));
      return;
    }
    if (!_isDesktop) return; // local_notifier is desktop-only
    try {
      final n = LocalNotification(
        identifier: 'hm_${DateTime.now().microsecondsSinceEpoch}',
        title: t.title,
        body: t.body,
      );
      n.onClick = () => unawaited(_open(t));
      n.show().catchError((_) {});
    } catch (_) {}
  }

  Future<void> _open(SyncToast t) async {
    try {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
    final n = t.notification;
    if (n != null) {
      ShellNavigation.openNotification?.call(n);
    } else if (t.screen != null) {
      ShellNavigation.openScreen?.call(t.screen!);
    }
  }
}
