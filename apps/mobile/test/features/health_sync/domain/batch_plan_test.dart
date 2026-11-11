import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/batch_plan.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';
import 'package:open_ring/features/health_sync/domain/retry_policy.dart';

const tick = Duration(milliseconds: 1);

DateTime at(int hour, [int minute = 0]) => DateTime(2026, 11, 10, hour, minute);

HeartRateEntry beat(DateTime time) =>
    HeartRateEntry(id: 'hr:${time.millisecondsSinceEpoch}', at: time, bpm: 60);

List<HealthWriteBatch> plan(
  List<HealthEntry> entries, {
  DateTime? from,
  DateTime? to,
  int batchSize = 2,
  List<TimeWindow> excluded = const [],
}) => planBatches(
  kind: HealthRecordKind.heartRate,
  version: 7,
  from: from ?? at(1),
  to: to ?? at(5),
  entries: entries,
  batchSize: batchSize,
  excluded: excluded,
);

void main() {
  group('planBatches', () {
    test('chunks by size and tiles the range with no gap', () {
      final beats = [beat(at(4)), beat(at(1)), beat(at(2)), beat(at(3))];

      final batches = plan(beats);

      expect(batches.map((b) => b.entries.map((e) => e.start).toList()), [
        [at(1), at(2)],
        [at(3), at(4)],
      ]);
      expect(batches.map((b) => (b.from, b.to)), [
        (at(1), at(3)),
        (at(3), at(5).add(tick)),
      ]);
      expect(batches.map((b) => b.version), [7, 7]);
    });

    test('widens to entries that start before or end after the range', () {
      final sleep = SleepEntry(
        id: 'sleep',
        start: at(0),
        end: at(6),
        stages: const [],
      );

      final batch = planBatches(
        kind: HealthRecordKind.sleep,
        version: 1,
        from: at(1),
        to: at(5),
        entries: [sleep],
        batchSize: 10,
      ).single;

      expect((batch.from, batch.to), (at(0), at(6).add(tick)));
    });

    test('an empty range still yields one batch so stale records clear', () {
      final batch = plan(const []).single;

      expect(batch.entries, isEmpty);
      expect((batch.from, batch.to), (at(1), at(5).add(tick)));
    });

    test('never covers an excluded window and drops entries inside it', () {
      final beats = [beat(at(1)), beat(at(2, 30)), beat(at(4))];

      final batches = plan(
        beats,
        batchSize: 10,
        excluded: [TimeWindow(at(2), at(3))],
      );

      expect(batches.map((b) => (b.from, b.to)), [
        (at(1), at(2)),
        (at(3).add(tick), at(5).add(tick)),
      ]);
      expect(batches.expand((b) => b.entries).map((e) => e.start), [
        at(1),
        at(4),
      ]);
    });
  });

  group('RetryPolicy', () {
    const policy = RetryPolicy(maxAttempts: 5, cap: Duration(minutes: 5));
    final now = at(8);

    test('doubles the delay per attempt up to the cap', () {
      expect(
        [for (var a = 1; a < 5; a++) policy.nextAttempt(a, now)],
        [
          now.add(const Duration(minutes: 1)),
          now.add(const Duration(minutes: 2)),
          now.add(const Duration(minutes: 4)),
          now.add(const Duration(minutes: 5)),
        ],
      );
    });

    test('has no next attempt once the attempts are spent', () {
      expect(policy.nextAttempt(5, now), isNull);
    });
  });
}
