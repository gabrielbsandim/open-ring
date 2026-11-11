import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/theme_mode_controller.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
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
  @override
  TodayWidgetConfig build() =>
      ref.watch(todayWidgetConfigStoreProvider).read() ?? TodayWidgetConfig();

  Future<void> toggle(WidgetMetric metric) => _save(state.toggle(metric));

  Future<void> selectTheme(WidgetTheme theme) => _save(state.withTheme(theme));

  Future<void> reset() async {
    state = TodayWidgetConfig();
    await ref.read(todayWidgetConfigStoreProvider).reset();
  }

  Future<void> _save(TodayWidgetConfig next) async {
    if (next == state) return;
    state = next;
    await ref.read(todayWidgetConfigStoreProvider).write(next);
  }
}

final widgetSnapshotProvider = FutureProvider<WidgetSnapshot>((ref) async {
  final view = await ref.watch(todayViewProvider.future);
  final lastWorkout = await ref.watch(lastWorkoutProvider.future);
  return buildWidgetSnapshot(view, lastWorkout: lastWorkout);
});

final widgetAppearanceProvider = Provider<WidgetAppearance>(
  (ref) => (
    appTheme: ref.watch(themeModeProvider),
    today: ref.watch(todayWidgetConfigProvider),
    units: ref.watch(currentUnitSystemProvider),
  ),
);

final widgetPinSupportedProvider = FutureProvider<bool>(
  (ref) => ref.watch(widgetGatewayProvider).canPin(),
);

final widgetPushTriggerProvider = Provider<WidgetPublisher>((ref) {
  final publisher = WidgetPublisher(ref.watch(widgetGatewayProvider));
  ref
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
