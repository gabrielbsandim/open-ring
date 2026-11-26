import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/theme_mode_controller.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/energy/application/energy_providers.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/widgets/application/widget_publisher.dart';
import 'package:open_ring/features/widgets/application/widget_snapshot_builder.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:open_ring/features/widgets/domain/widget_gateway.dart';
import 'package:open_ring/features/widgets/domain/widget_snapshot.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';

final widgetGatewayProvider = Provider<WidgetGateway>(
  (ref) => const UnsupportedWidgetGateway(),
);

final todayWidgetConfigStoreProvider = Provider<TodayWidgetConfigStore>(
  (ref) => InMemoryTodayWidgetConfigStore(),
);

final todayWidgetConfigProvider =
    NotifierProvider<TodayWidgetConfigController, TodayWidgetConfig>(
      TodayWidgetConfigController.new,
    );

class TodayWidgetConfigController extends Notifier<TodayWidgetConfig> {
  Future<void> _queue = Future.value();

  @override
  TodayWidgetConfig build() =>
      ref.watch(todayWidgetConfigStoreProvider).read() ?? TodayWidgetConfig();

  Future<void> toggle(
    WidgetMetric metric, {
    int maxMetrics = TodayWidgetConfig.maxMetrics,
  }) => _save((current) {
    if (!current.contains(metric) && current.metrics.length >= maxMetrics) {
      return current;
    }
    return current.toggle(metric);
  });

  Future<void> add(WidgetMetric metric) =>
      _save((current) => current.add(metric));

  Future<void> remove(WidgetMetric metric) =>
      _save((current) => current.remove(metric));

  Future<void> moveUp(int index) => _save((current) => current.moveUp(index));

  Future<void> moveDown(int index) =>
      _save((current) => current.moveDown(index));

  Future<void> removeForModule(ModuleId id) =>
      _save((current) => current.removeForModule(id));

  Future<void> retainModules(Set<ModuleId> enabled) =>
      _save((current) => current.retainModules(enabled));

  Future<void> selectTheme(WidgetTheme theme) =>
      _save((current) => current.withTheme(theme));

  Future<void> reset() => _enqueue(() async {
    state = TodayWidgetConfig();
    await ref.read(todayWidgetConfigStoreProvider).reset();
  });

  Future<void> _save(
    TodayWidgetConfig Function(TodayWidgetConfig current) transform,
  ) => _enqueue(() async {
    final next = transform(state);
    if (next == state) return;
    state = next;
    await ref.read(todayWidgetConfigStoreProvider).write(next);
  });

  // Serialize store mutations so async writes never overwrite newer state.
  Future<void> _enqueue(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }
}

Future<T?> _tryRead<T>(Future<T> future) async {
  try {
    return await future;
  } on Object {
    return null;
  }
}

final widgetSnapshotProvider = FutureProvider<WidgetSnapshot>((ref) async {
  final now = ref.watch(clockProvider)();
  await (
    _tryRead(ref.watch(enabledModulesProvider.future)),
    _tryRead(ref.watch(hideNumbersProvider.future)),
    _tryRead(ref.watch(userProfileProvider.future)),
  ).wait;
  final enabled = ref.watch(activeModulesProvider);
  final hideNumbers = ref.watch(profileWeightHiddenProvider);
  final view = await ref.watch(todayViewProvider.future);
  final lastWorkout = await ref.watch(lastWorkoutProvider.future);
  final (
    dayScoreHistory,
    weightSummary,
    energyNow,
    effortWeek,
    goalWeek,
  ) = await (
    enabled.contains(ModuleId.openScore)
        ? _tryRead(ref.watch(dayScoreHistoryProvider.future))
        : Future<DayScoreHistory?>.value(),
    enabled.contains(ModuleId.body)
        ? _tryRead(ref.watch(weightSummaryProvider.future))
        : Future<WeightSummary?>.value(),
    enabled.contains(ModuleId.energy) && !hideNumbers
        ? _tryRead(ref.watch(energyNowProvider.future))
        : Future<EnergyNow?>.value(),
    enabled.contains(ModuleId.effort)
        ? _tryRead(ref.watch(effortWeekProvider.future))
        : Future<EffortWeek?>.value(),
    enabled.contains(ModuleId.goals)
        ? _tryRead(ref.watch(goalWeekProvider.future))
        : Future<GoalWeekView?>.value(),
  ).wait;
  return buildWidgetSnapshot(
    view,
    lastWorkout: lastWorkout,
    enabledModules: enabled,
    hideNumbers: hideNumbers,
    dayScoreHistory: dayScoreHistory,
    weightSummary: weightSummary,
    energyNow: energyNow,
    effortWeek: effortWeek,
    goalWeek: goalWeek,
    now: now,
  );
});

final widgetAppearanceProvider = Provider<WidgetAppearance>((ref) {
  final today = ref.watch(todayWidgetConfigProvider);
  final enabled = ref.watch(activeModulesProvider);
  final hideNumbers = ref.watch(profileWeightHiddenProvider);
  return (
    appTheme: ref.watch(themeModeProvider),
    today: today,
    effectiveTodayMetrics: today.effectiveMetrics(
      enabled: enabled,
      hideNumbers: hideNumbers,
    ),
    units: ref.watch(currentUnitSystemProvider),
  );
});

final widgetPinSupportedProvider = FutureProvider<bool>(
  (ref) => ref.watch(widgetGatewayProvider).canPin(),
);

final widgetPushTriggerProvider = Provider<WidgetPublisher>((ref) {
  final publisher = WidgetPublisher(ref.watch(widgetGatewayProvider));
  ref
    ..listen(enabledModulesProvider, (_, next) {
      if (next is! AsyncData<Set<ModuleId>>) return;
      unawaited(
        ref.read(todayWidgetConfigProvider.notifier).retainModules(next.value),
      );
    }, fireImmediately: true)
    ..listen(
      activeModulesProvider,
      (_, next) => unawaited(
        publisher.setThisWeekAvailable(
          available:
              next.contains(ModuleId.effort) || next.contains(ModuleId.goals),
        ),
      ),
      fireImmediately: true,
    )
    ..listen(widgetSnapshotProvider, (_, next) {
      if (next case AsyncData(:final value)) {
        unawaited(publisher.snapshot(value));
      }
    }, fireImmediately: true)
    ..listen(
      widgetAppearanceProvider,
      (_, next) => unawaited(publisher.appearance(next)),
      fireImmediately: true,
    );
  return publisher;
});

// A provider nobody listens to is paused, and its listeners with it, so the
// trigger needs a subscription that lives as long as the container.
ProviderSubscription<WidgetPublisher> startWidgetPush(
  ProviderContainer container,
) => container.listen(widgetPushTriggerProvider, (_, _) {});
