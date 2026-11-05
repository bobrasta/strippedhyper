import 'package:bienhypermed/main.dart';
import 'package:bienhypermed/models/email.dart';
import 'package:bienhypermed/models/notification.dart';
import 'package:bienhypermed/services/background_sync.dart';
import 'package:bienhypermed/services/local_db.dart';
import 'package:flutter_test/flutter_test.dart';

AppNotification _notif(int id, {bool read = false}) => AppNotification.fromJson({
      'id': id, 'type': 'ticket_assigned', 'title': 'Title $id', 'body': 'Body $id',
      'is_read': read, 'created_at': '2026-10-16',
    });

Email _email(int id) => Email.fromJson({'id': id, 'from_name': 'Sender $id', 'subject': 'Subject $id'});

void main() {
  late LocalDb db;
  late List<SyncToast> toasts;
  late BackgroundSync sync;

  BackgroundSync newSync() => BackgroundSync(toaster: toasts.add, db: () => db)..debugUserId = 5;

  setUp(() {
    db = LocalDb.openInMemory();
    toasts = [];
    sync = newSync();
  });
  tearDown(() => db.close());

  test('diffNew: first run is a baseline, later runs return newer ids oldest first', () {
    void check((List<int>, int) r, List<int> fresh, int marker) {
      expect(r.$1, fresh);
      expect(r.$2, marker);
    }
    check(BackgroundSync.diffNew([3, 9, 4], (x) => x, null), [], 9);
    check(BackgroundSync.diffNew(<int>[], (x) => x, null), [], 0);
    check(BackgroundSync.diffNew([12, 9, 11], (x) => x, 9), [11, 12], 12);
    check(BackgroundSync.diffNew([3], (x) => x, 9), [], 9);
  });

  test('notifications: baseline, then one toast per new unread one with its own text', () {
    sync.handleNotifications([_notif(1), _notif(2, read: true)]);
    expect(toasts, isEmpty);
    expect(notificationCountNotifier.value, 1);

    // One read + one new arriving: the old count-based check missed this.
    sync.handleNotifications([_notif(1, read: true), _notif(2, read: true), _notif(3), _notif(4, read: true)]);
    expect(toasts.map((t) => t.title), ['Title 3']);
    expect(toasts.single.body, 'Body 3');
    expect(toasts.single.notification?.id, 3);
    expect(notificationCountNotifier.value, 1);

    // Nothing new → nothing shown.
    sync.handleNotifications([_notif(3)]);
    expect(toasts, hasLength(1));
  });

  test('more than three new notifications → one summary', () {
    sync.handleNotifications([_notif(1)]);
    sync.handleNotifications([for (var i = 1; i <= 6; i++) _notif(i)]);
    expect(toasts.single.title, '5 new notifications');
    expect(toasts.single.screen, 'notifications');
  });

  test('markers persist: a restart repeats nothing but announces what arrived meanwhile', () {
    sync.handleNotifications([_notif(1), _notif(2)]);
    sync.handleEmails({1: [_email(10)]});

    final restarted = newSync();
    restarted.handleNotifications([_notif(1), _notif(2), _notif(3)]);
    restarted.handleEmails({1: [_email(10)]});
    expect(toasts.map((t) => t.title), ['Title 3']);
  });

  test('emails: per-account baseline, one toast per new email, summary above three', () {
    sync.handleEmails({1: [_email(10)], 2: []});
    expect(toasts, isEmpty);

    sync.handleEmails({1: [_email(10), _email(12)], 2: [_email(11)]});
    expect(toasts.map((t) => t.title), ['New email from Sender 12', 'New email from Sender 11']);
    expect(toasts.map((t) => t.body), ['Subject 12', 'Subject 11']);
    expect(toasts.every((t) => t.screen == 'email'), isTrue);

    toasts.clear();
    sync.handleEmails({1: [for (var i = 13; i <= 16; i++) _email(i)], 2: []});
    expect(toasts.single.title, '4 new emails');

    // A newly added account starts with a baseline of its own.
    toasts.clear();
    sync.handleEmails({3: [_email(50)]});
    expect(toasts, isEmpty);
  });

  test('wiping the user resets the baseline instead of re-announcing', () {
    sync.handleNotifications([_notif(1)]);
    db.wipeUser(5);
    newSync().handleNotifications([_notif(1), _notif(2)]);
    expect(toasts, isEmpty);
  });
}
