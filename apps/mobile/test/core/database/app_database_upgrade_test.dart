import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';

const _day = 24 * 60 * 60 * 1000;
const _hour = 60 * 60 * 1000;

const _createOutboxV9 = '''
CREATE TABLE health_outbox (
  id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  kind TEXT NOT NULL,
  device_id TEXT NULL,
  from_utc_ms INTEGER NOT NULL,
  to_utc_ms INTEGER NOT NULL,
  record_count INTEGER NOT NULL,
  enqueued_at_utc_ms INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT NULL,
  completed_at_utc_ms INTEGER NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  last_attempt_at_utc_ms INTEGER NULL,
  next_attempt_at_utc_ms INTEGER NULL
)
''';

class _Row {
  const _Row(this.id, this.kind, this.status, this.fromUtcMs);

  final int id;
  final String kind;
  final String status;
  final int fromUtcMs;
}

// A real v9 file: the outbox as drift_schemas/app/drift_schema_v9.json
// declares it, user_version 9, so drift runs the step from 9 on open.
AppDatabase _v9Database(List<_Row> rows) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = AppDatabase(
    NativeDatabase.memory(
      setup: (raw) {
        raw.execute(_createOutboxV9);
        for (final row in rows) {
          raw.execute(
            'INSERT INTO health_outbox (id, kind, device_id, from_utc_ms, '
            'to_utc_ms, record_count, enqueued_at_utc_ms, attempts, '
            'last_error, completed_at_utc_ms, status, last_attempt_at_utc_ms, '
            'next_attempt_at_utc_ms) VALUES (?, ?, ?, ?, ?, 1, ?, 3, ?, ?, ?, '
            '?, ?)',
            [
              row.id,
              row.kind,
              'ring',
              row.fromUtcMs,
              row.fromUtcMs + _hour,
              row.fromUtcMs,
              'boom',
              row.status == 'done' ? row.fromUtcMs + _hour : null,
              row.status,
              row.fromUtcMs + _hour,
              row.status == 'pending' ? row.fromUtcMs + 2 * _hour : null,
            ],
          );
        }
        raw.execute('PRAGMA user_version = 9');
      },
    ),
  );
  addTearDown(db.close);
  return db;
}

Future<Map<int, QueryRow>> _outbox(AppDatabase db) async {
  final rows = await db.customSelect('SELECT * FROM health_outbox').get();
  return {for (final r in rows) r.read<int>('id'): r};
}

void _expectPending(QueryRow row) {
  expect(row.read<String>('status'), 'pending');
  expect(row.read<int>('attempts'), 0);
  expect(row.readNullable<String>('last_error'), isNull);
  expect(row.readNullable<int>('completed_at_utc_ms'), isNull);
  expect(row.readNullable<int>('next_attempt_at_utc_ms'), isNull);
}

void _expectUntouched(QueryRow row, String status) {
  expect(row.read<String>('status'), status);
  expect(row.read<int>('attempts'), 3);
  expect(row.readNullable<String>('last_error'), 'boom');
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  final now = DateTime.now().millisecondsSinceEpoch;
  final rows = [
    _Row(1, 'workout', 'done', now - _day),
    _Row(2, 'workout', 'done', now - 7 * _day + _hour),
    _Row(3, 'workout', 'done', now - 7 * _day - _hour),
    _Row(4, 'workout', 'done', now - 30 * _day),
    _Row(5, 'heartRate', 'done', now - _day),
    _Row(6, 'workout', 'dead', now - _day),
    _Row(7, 'workout', 'pending', now - _day),
    _Row(8, 'workout', 'notApplicable', now - _day),
  ];

  test('criterion 4: Android re-queues done workouts of the last 7 days', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final db = _v9Database(rows);

    final outbox = await _outbox(db);

    _expectPending(outbox[1]!);
    _expectPending(outbox[2]!);
  });

  test('criterion 4: the upgrade lands on schema version 10', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final db = _v9Database(rows);

    final version = await db.customSelect('PRAGMA user_version').getSingle();

    expect(version.read<int>('user_version'), 10);
  });

  test('criterion 4: older done workouts stay done', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final db = _v9Database(rows);

    final outbox = await _outbox(db);

    _expectUntouched(outbox[3]!, 'done');
    _expectUntouched(outbox[4]!, 'done');
  });

  test('criterion 4: other kinds and other statuses are untouched', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final db = _v9Database(rows);

    final outbox = await _outbox(db);

    _expectUntouched(outbox[5]!, 'done');
    _expectUntouched(outbox[6]!, 'dead');
    _expectUntouched(outbox[8]!, 'notApplicable');
    expect(outbox[7]!.read<String>('status'), 'pending');
    expect(outbox[7]!.read<int>('attempts'), 3);
  });

  test('criterion 4: no outbox row is deleted', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final db = _v9Database(rows);

    final outbox = await _outbox(db);

    expect(outbox.keys.toSet(), {1, 2, 3, 4, 5, 6, 7, 8});
  });

  test('criterion 5: iOS changes no row but still reaches version 10', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final db = _v9Database(rows);

    final outbox = await _outbox(db);
    final version = await db.customSelect('PRAGMA user_version').getSingle();

    expect(version.read<int>('user_version'), 10);
    _expectUntouched(outbox[1]!, 'done');
    _expectUntouched(outbox[2]!, 'done');
    _expectUntouched(outbox[3]!, 'done');
  });

  test('criterion 5: a non-mobile host changes no row', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final db = _v9Database(rows);

    final outbox = await _outbox(db);
    final version = await db.customSelect('PRAGMA user_version').getSingle();

    expect(version.read<int>('user_version'), 10);
    _expectUntouched(outbox[1]!, 'done');
    _expectUntouched(outbox[2]!, 'done');
  });
}
