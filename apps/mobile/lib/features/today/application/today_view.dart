import 'package:meta/meta.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/heart/application/heart_view.dart';
import 'package:open_ring/features/sleep/application/sleep_view.dart';
import 'package:open_ring/features/today/application/readiness_view.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';

const staleSyncAfter = Duration(hours: 3);

enum SyncFreshness { unpaired, neverSynced, fresh, stale }

SyncFreshness freshnessOf(RingStatus ring, DateTime now) {
  if (!ring.paired) return SyncFreshness.unpaired;
  final last = ring.lastSyncAt;
  if (last == null) return SyncFreshness.neverSynced;
  if (now.difference(last) > staleSyncAfter) return SyncFreshness.stale;
  return SyncFreshness.fresh;
}

@immutable
final class TodayView {
  const new({
    required this.now,
    required this.ring,
    required this.readiness,
    required this.heart,
    required this.activity,
    required this.stepGoal,
    this.remMeasured = true,
  });

  final DateTime now;
  final RingStatus ring;
  final ReadinessView readiness;
  final HeartDayView heart;
  final DailyActivity? activity;
  final int stepGoal;
  final bool remMeasured;

  SleepDayView get lastNight => readiness.sleep;

  SyncFreshness get freshness => freshnessOf(ring, now);
}
