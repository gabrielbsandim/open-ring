import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/ring/domain/ring_sync_batch.dart';
import 'package:open_ring/features/ring/domain/sleep_session_span.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';
import '../../../helpers/sync_fixtures.dart';

void main() {
  group('SleepSessionSpan.group', () {
    test('splits nights on a gap longer than an hour', () {
      final nap = SleepSegment(
        start: DateTime(2026, 11, 10, 14),
        end: DateTime(2026, 11, 10, 14, 40),
        stage: SleepStage.light,
      );

      final sessions = SleepSessionSpan.group([nap, ...lastNight.reversed]);

      expect(sessions.map((s) => (s.start, s.end)), [
        (nightStart, lastNight.last.end),
        (nap.start, nap.end),
      ]);
      expect(sessions.first.segments, lastNight);
    });

    test('keeps a gap of up to an hour inside one night', () {
      final afterGap = SleepSegment(
        start: DateTime(2026, 11, 10, 2),
        end: DateTime(2026, 11, 10, 3),
        stage: SleepStage.deep,
      );
      final tooLate = SleepSegment(
        start: DateTime(2026, 11, 10, 4, 1),
        end: DateTime(2026, 11, 10, 5),
        stage: SleepStage.light,
      );

      final sessions = SleepSessionSpan.group([
        lastNight.first,
        afterGap,
        tooLate,
      ]);

      expect(sessions.map((s) => s.segments.length), [2, 1]);
    });
  });

  group('resumePoints', () {
    test('uses the latest sample per kind and the latest night start', () {
      final driver = loadedDriver();
      final batch = RingSyncBatch(
        deviceId: ringId,
        identity: ringIdentity,
        syncedAt: syncNow,
        activity: driver.activity,
        heartRate: driver.heartRate,
        spo2: driver.spo2,
        stress: driver.stress,
        hrv: driver.hrv,
        sleep: driver.sleep,
      );

      expect(batch.resumePoints(), {
        RecordKind.activity: eveningActivity.last.start,
        RecordKind.heartRate: nightHeartRate.last.at,
        RecordKind.spo2: driver.spo2.single.at,
        RecordKind.stress: driver.stress.single.at,
        RecordKind.hrv: driver.hrv.single.at,
        RecordKind.sleep: nightStart,
      });
    });

    test('skips kinds that were not pulled or came back empty', () {
      final batch = RingSyncBatch(
        deviceId: ringId,
        identity: ringIdentity,
        syncedAt: syncNow,
        heartRate: const [],
        sleep: lastNight,
      );

      expect(batch.resumePoints(), {RecordKind.sleep: nightStart});
    });
  });
}
