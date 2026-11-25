import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart' show LocalDate;
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/trajectory/domain/projection_store.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_projection.dart';
import 'package:open_ring/features/trajectory/infrastructure/drift_projection_store.dart';

import '../../helpers/database.dart';

const _monday = LocalDate(2026, 11, 23);

TrajectoryProjection _projection({
  LocalDate monday = _monday,
  double trendKg = 80.4,
  double rateKgPerWeek = -0.5,
  double lowKg = 78.0,
  double midKg = 78.5,
  double highKg = 79.2,
}) => TrajectoryProjection(
  monday: monday,
  trendKg: trendKg,
  rateKgPerWeek: rateKgPerWeek,
  lowKg: lowKg,
  midKg: midKg,
  highKg: highKg,
  createdAt: DateTime.utc(2026, 11, 23, 6, 30),
);

List<Object> _fields(TrajectoryProjection p) => [
  p.monday.iso,
  p.trendKg,
  p.rateKgPerWeek,
  p.lowKg,
  p.midKg,
  p.highKg,
  p.createdAt.toUtc().millisecondsSinceEpoch,
];

Future<void> _addWeighIn(AppDatabase db) => db
    .into(db.weighIns)
    .insert(
      WeighInsCompanion.insert(
        atUtcMs: 1762765200000,
        offsetMinutes: -180,
        kilograms: 80.4,
        source: 'manual',
      ),
    );

void main() {
  late AppDatabase db;
  late ProjectionStore store;

  setUp(() {
    db = memoryDatabase();
    store = DriftProjectionStore(db);
  });

  test('insertIfAbsent on an empty Monday returns true and all() holds the '
      'row', () async {
    expect(await store.insertIfAbsent(_projection()), isTrue);

    final rows = await store.all();
    expect(rows, hasLength(1));
    expect(_fields(rows.single), _fields(_projection()));
  });

  test('the Monday is stored as the LocalDate iso text', () async {
    await store.insertIfAbsent(_projection());

    final row = await db
        .customSelect('SELECT monday FROM trajectory_projections')
        .getSingle();
    expect(row.read<String>('monday'), '2026-11-23');
  });

  test('a negative rate round trips with its sign', () async {
    await store.insertIfAbsent(_projection(rateKgPerWeek: -0.75));

    expect((await store.all()).single.rateKgPerWeek, -0.75);
  });

  test('a second insertIfAbsent for the same Monday returns false and the '
      'first values stay', () async {
    await store.insertIfAbsent(_projection());

    final second = await store.insertIfAbsent(
      _projection(trendKg: 70, lowKg: 60, midKg: 65, highKg: 69),
    );

    expect(second, isFalse);
    final rows = await store.all();
    expect(rows, hasLength(1));
    expect(_fields(rows.single), _fields(_projection()));
  });

  test('two concurrent insertIfAbsent for one Monday write one row and '
      'exactly one returns true', () async {
    final results = await Future.wait([
      store.insertIfAbsent(_projection()),
      store.insertIfAbsent(_projection(trendKg: 71, lowKg: 60, midKg: 65)),
    ]);

    expect(results.where((r) => r), hasLength(1));
    expect(await rowCount(db, 'trajectory_projections'), 1);
  });

  test('every weekday except Monday throws ArgumentError and writes '
      'nothing', () async {
    for (var offset = 1; offset < 7; offset++) {
      await expectLater(
        store.insertIfAbsent(_projection(monday: _monday.addDays(offset))),
        throwsArgumentError,
      );
    }
    expect(await rowCount(db, 'trajectory_projections'), 0);
  });

  test('lowKg above midKg throws ArgumentError and writes nothing', () async {
    await expectLater(
      store.insertIfAbsent(_projection(lowKg: 79, midKg: 78.5)),
      throwsArgumentError,
    );
    expect(await rowCount(db, 'trajectory_projections'), 0);
  });

  test('midKg above highKg throws ArgumentError and writes nothing', () async {
    await expectLater(
      store.insertIfAbsent(_projection(midKg: 79.5, highKg: 79.2)),
      throwsArgumentError,
    );
    expect(await rowCount(db, 'trajectory_projections'), 0);
  });

  test('a band with low, mid and high equal is accepted', () async {
    expect(
      await store.insertIfAbsent(_projection(lowKg: 78, midKg: 78, highKg: 78)),
      isTrue,
    );
  });

  test('all() is sorted by Monday, oldest first', () async {
    for (final monday in [
      _monday,
      _monday.addDays(-14),
      _monday.addDays(7),
      _monday.addDays(-7),
    ]) {
      await store.insertIfAbsent(_projection(monday: monday));
    }

    expect((await store.all()).map((p) => p.monday.iso), [
      '2026-11-09',
      '2026-11-16',
      '2026-11-23',
      '2026-11-30',
    ]);
  });

  test('all() is empty on a fresh database', () async {
    expect(await store.all(), isEmpty);
  });

  test('deleteAll() empties projections, returns the count and leaves '
      'weigh_ins untouched', () async {
    await _addWeighIn(db);
    await store.insertIfAbsent(_projection());
    await store.insertIfAbsent(_projection(monday: _monday.addDays(7)));

    expect(await store.deleteAll(), 2);

    expect(await store.all(), isEmpty);
    expect(await rowCount(db, 'weigh_ins'), 1);
  });

  test('deleteAll() on an empty table returns 0', () async {
    expect(await store.deleteAll(), 0);
  });

  test('after deleteAll() the same Monday can be inserted again', () async {
    await store.insertIfAbsent(_projection());
    await store.deleteAll();

    expect(await store.insertIfAbsent(_projection(trendKg: 79)), isTrue);
    expect((await store.all()).single.trendKg, 79);
  });

  test('the table has the seven not null columns and the Monday as its '
      'primary key', () async {
    final info = await db
        .customSelect('PRAGMA table_info(trajectory_projections)')
        .get();

    expect(
      {for (final c in info) c.read<String>('name'): c.read<int>('notnull')},
      {
        'monday': 1,
        'trend_kg': 1,
        'rate_kg_per_week': 1,
        'low_kg': 1,
        'mid_kg': 1,
        'high_kg': 1,
        'created_at_utc_ms': 1,
      },
    );
    expect(
      info
          .where((c) => c.read<int>('pk') > 0)
          .map((c) => c.read<String>('name')),
      ['monday'],
    );
  });
}
