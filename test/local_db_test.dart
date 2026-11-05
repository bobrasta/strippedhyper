import 'dart:typed_data';

import 'package:bienhypermed/services/local_db.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LocalDb db;
  setUp(() => db = LocalDb.openInMemory());
  tearDown(() => db.close());

  test('kv set / get / overwrite / remove, JSON round trip', () {
    expect(db.getValue('7', 'a'), isNull);
    db.setValue('7', 'a', 'one');
    db.setValue('7', 'a', 'two');
    expect(db.getValue('7', 'a'), 'two');
    expect(db.getValue('8', 'a'), isNull);
    db.setJson(LocalDb.appScope, 'trial', {'state': 'valid', 'days': 3});
    expect(db.getJson(LocalDb.appScope, 'trial'), {'state': 'valid', 'days': 3});
    db.removeValue('7', 'a');
    expect(db.getValue('7', 'a'), isNull);
  });

  test('responses upsert per user and key', () {
    db.putResponse(1, '/x', Uint8List.fromList([1, 2]));
    db.putResponse(1, '/x', Uint8List.fromList([3]));
    db.putResponse(2, '/x', Uint8List.fromList([9]));
    expect(db.getResponse(1, '/x')!.body, [3]);
    expect(db.getResponse(2, '/x')!.body, [9]);
    expect(db.getResponse(1, '/y'), isNull);
  });

  test('prune drops old rows, then least recently fetched over the size cap', () {
    final now = DateTime(2026, 10, 1);
    db.putResponse(1, '/old', Uint8List(10), fetchedAt: now.subtract(const Duration(days: 31)));
    db.putResponse(1, '/a', Uint8List(40), fetchedAt: now.subtract(const Duration(hours: 3)));
    db.putResponse(1, '/b', Uint8List(40), fetchedAt: now.subtract(const Duration(hours: 2)));
    db.putResponse(1, '/c', Uint8List(40), fetchedAt: now.subtract(const Duration(hours: 1)));
    db.prune(maxBytes: 100, now: now);
    expect(db.getResponse(1, '/old'), isNull);
    expect(db.getResponse(1, '/a'), isNull);
    expect(db.getResponse(1, '/b'), isNotNull);
    expect(db.getResponse(1, '/c'), isNotNull);
  });

  test('outbox add / update / list / remove', () {
    final id = db.addOutbox(1, 'compose', {'to': 'a@b.c', 'subject': 'Hi'}, 'Timeout');
    db.addOutbox(2, 'reply', {'email_id': 4}, 'x');
    expect(db.outboxCount(1), 1);
    db.updateOutbox(id, payload: {'to': 'z@b.c', 'subject': 'Hi'}, error: 'Server error');
    final entry = db.outbox(1).single;
    expect(entry.kind, 'compose');
    expect(entry.payload['to'], 'z@b.c');
    expect(entry.error, 'Server error');
    db.removeOutbox(id);
    expect(db.outboxCount(1), 0);
    expect(db.outboxCount(2), 1);
  });

  test('wipeUser removes only that user; app scope survives', () {
    for (final u in [1, 2]) {
      db.setValue('$u', 'perms', '{}');
      db.putResponse(u, '/x', Uint8List(1));
      db.addOutbox(u, 'compose', {}, null);
    }
    db.setValue(LocalDb.appScope, 'dns:api', '1.2.3.4');
    db.wipeUser(1);
    expect(db.getValue('1', 'perms'), isNull);
    expect(db.getResponse(1, '/x'), isNull);
    expect(db.outboxCount(1), 0);
    expect(db.getValue('2', 'perms'), '{}');
    expect(db.getResponse(2, '/x'), isNotNull);
    expect(db.outboxCount(2), 1);
    expect(db.getValue(LocalDb.appScope, 'dns:api'), '1.2.3.4');
  });

  test('wipeAll keeps only app-scope kv', () {
    db.setValue('1', 'perms', '{}');
    db.putResponse(1, '/x', Uint8List(1));
    db.addOutbox(1, 'compose', {}, null);
    db.setValue(LocalDb.appScope, 'trial', '{}');
    db.wipeAll();
    expect(db.getValue('1', 'perms'), isNull);
    expect(db.getResponse(1, '/x'), isNull);
    expect(db.outboxCount(1), 0);
    expect(db.getValue(LocalDb.appScope, 'trial'), '{}');
  });
}
