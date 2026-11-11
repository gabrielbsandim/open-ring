import 'package:meta/meta.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/ring/domain/sleep_session_span.dart';
import 'package:ring_driver/ring_driver.dart';

@immutable
final class RingSyncBatch {
  const new({
    required this.deviceId,
    required this.identity,
    required this.syncedAt,
    this.battery,
    this.activity,
    this.heartRate,
    this.spo2,
    this.stress,
    this.hrv,
    this.sleep,
  });

  final String deviceId;
  final RingIdentity identity;
  final DateTime syncedAt;
  final BatteryStatus? battery;
  final List<ActivityBucket>? activity;
  final List<HeartRateSample>? heartRate;
  final List<Spo2Sample>? spo2;
  final List<StressSample>? stress;
  final List<HrvSample>? hrv;
  final List<SleepSegment>? sleep;

  // Sleep resumes at the start of the latest night so a night that was still
  // in progress is pulled whole again and its session keeps the same start.
  Map<RecordKind, DateTime> resumePoints() {
    final nights = switch (sleep) {
      null => null,
      final segments => SleepSessionSpan.group(segments).map((s) => s.start),
    };
    return {
      RecordKind.activity: ?_latest(activity?.map((b) => b.start)),
      RecordKind.heartRate: ?_latest(heartRate?.map((s) => s.at)),
      RecordKind.spo2: ?_latest(spo2?.map((s) => s.at)),
      RecordKind.stress: ?_latest(stress?.map((s) => s.at)),
      RecordKind.hrv: ?_latest(hrv?.map((s) => s.at)),
      RecordKind.sleep: ?_latest(nights),
    };
  }

  static DateTime? _latest(Iterable<DateTime>? times) {
    if (times == null || times.isEmpty) return null;
    return times.reduce((a, b) => a.isAfter(b) ? a : b);
  }
}
