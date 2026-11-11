import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/sleep/application/sleep_view.dart';
import 'package:open_ring/features/today/application/readiness_trend.dart';
import 'package:open_ring/features/today/application/readiness_view.dart';
import 'package:open_ring/features/today/application/today_view.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';
import 'package:open_ring/features/trends/application/trends_providers.dart';

final ringStatusReaderProvider = Provider<RingStatusReader>(
  (ref) => const EmptyRingStatusReader(),
);

final ringStatusProvider = FutureProvider<RingStatus>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(ringStatusReaderProvider).status();
});

final readinessProvider = FutureProvider<ReadinessView>((ref) async {
  final today = ref.watch(currentDateProvider);
  final (week, heart, activity) = await (
    ref.watch(sleepWeekProvider.future),
    ref.watch(heartBaselinesProvider.future),
    ref.watch(activityDaysProvider.future),
  ).wait;
  final load = activityLoad([
    for (final d in activity.values) d.activeLoad,
  ], today: today);
  return ReadinessView(
    date: today,
    score: readiness(
      sleepScore: week.latest.scoreValue,
      hrv: heart.hrv.deviation,
      restingHeartRate: heart.restingHeartRate.deviation,
      activityLoad: load,
    ),
    sleep: week.latest,
    restingHeartRate: heart.restingHeartRate,
    hrv: heart.hrv,
    activityLoad: load,
  );
});

final readinessTrendProvider = FutureProvider<ReadinessTrend>((ref) async {
  ref.watch(dataRevisionProvider);
  final today = ref.watch(currentDateProvider);
  final reader = ref.watch(activityHistoryReaderProvider);
  final (history, activity) = await (
    ref.watch(trendHistoryProvider.future),
    reader.dailyActivity(
      from: today.addDays(1 - readinessTrendDays - chronicLoadDays),
      to: today,
    ),
  ).wait;
  return ReadinessTrend.collect(
    today: today,
    history: history,
    activity: activity,
  );
});

typedef FormulaView = ({ReadinessView readiness, SleepWeekView week});

final formulaViewProvider = FutureProvider<FormulaView>((ref) async {
  final (readiness, week) = await (
    ref.watch(readinessProvider.future),
    ref.watch(sleepWeekProvider.future),
  ).wait;
  return (readiness: readiness, week: week);
});

final todaySyncAttemptProvider = NotifierProvider<TodaySyncAttempt, DateTime?>(
  TodaySyncAttempt.new,
);

class TodaySyncAttempt extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  Future<void> sync() {
    state = ref.read(clockProvider)();
    return ref.read(ringSyncProvider.notifier).refresh();
  }
}

final todayViewProvider = FutureProvider<TodayView>((ref) async {
  final today = ref.watch(currentDateProvider);
  final now = ref.watch(clockProvider)();
  final stepGoal = ref.watch(stepGoalProvider);
  final (ring, readiness, heart, activity, remMeasured) = await (
    ref.watch(ringStatusProvider.future),
    ref.watch(readinessProvider.future),
    ref.watch(heartDayProvider.future),
    ref.watch(activityDaysProvider.future),
    ref.watch(remMeasuredProvider.future),
  ).wait;
  return TodayView(
    now: now,
    ring: ring,
    readiness: readiness,
    heart: heart,
    activity: activity[today],
    stepGoal: stepGoal,
    remMeasured: remMeasured,
  );
});
