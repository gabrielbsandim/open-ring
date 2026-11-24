import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/theme_mode_controller.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/ai_report_providers.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/application/health_context_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/analysis_run_state.dart';
import 'package:open_ring/features/ai/domain/health_context_assembly.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/infrastructure/shared_preferences_ai_run_marker_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/open_score/application/celebration_providers.dart';
import 'package:open_ring/features/open_score/application/week_goal_providers.dart';
import 'package:open_ring/features/open_score/domain/celebration_store.dart';
import 'package:open_ring/features/open_score/domain/week_goal_store.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/domain/sync_interval.dart';
import 'package:open_ring/features/settings/application/delete_all_data_controller.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/widgets/application/widget_providers.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/fake_sync_scheduler.dart';
import '../../../helpers/in_memory_sync_interval_store.dart';
import '../../../helpers/in_memory_theme_mode_store.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart' show FakeSyncStore;
import '../../../helpers/settings_fakes.dart';

void main() {
  late FakeLocalDataEraser eraser;
  late FakeSyncScheduler scheduler;
  late InMemoryUnitSystemStore units;
  late InMemoryUserProfileStore profiles;
  late InMemoryOnboardingStore onboarding;
  late InMemoryTodayWidgetConfigStore widgetConfig;
  late InMemoryModuleStore modules;
  late InMemoryWeekGoalStore weekGoal;
  late InMemoryCelebrationStore celebration;

  ProviderContainer container([
    FakeLocalDataEraser? override,
    List<Override> extra = const [],
  ]) {
    eraser = override ?? FakeLocalDataEraser();
    scheduler = FakeSyncScheduler();
    units = InMemoryUnitSystemStore(UnitSystem.imperial);
    profiles = InMemoryUserProfileStore(fullProfile);
    onboarding = InMemoryOnboardingStore(completed: true);
    modules = InMemoryModuleStore({ModuleId.body, ModuleId.trajectory});
    weekGoal = InMemoryWeekGoalStore(6);
    celebration = InMemoryCelebrationStore('2026-11-15');
    widgetConfig = InMemoryTodayWidgetConfigStore(
      TodayWidgetConfig().withTheme(WidgetTheme.light),
    );
    final container = ProviderContainer(
      overrides: [
        localDataEraserProvider.overrideWithValue(eraser),
        themeModeStoreProvider.overrideWithValue(
          InMemoryThemeModeStore(ThemeMode.dark),
        ),
        syncIntervalStoreProvider.overrideWithValue(
          InMemorySyncIntervalStore(SyncInterval.minutes15),
        ),
        syncSchedulerProvider.overrideWithValue(scheduler),
        syncStoreProvider.overrideWithValue(FakeSyncStore()),
        unitSystemStoreProvider.overrideWithValue(units),
        userProfileStoreProvider.overrideWithValue(profiles),
        onboardingStoreProvider.overrideWithValue(onboarding),
        todayWidgetConfigStoreProvider.overrideWithValue(widgetConfig),
        moduleStoreProvider.overrideWithValue(modules),
        weekGoalStoreProvider.overrideWithValue(weekGoal),
        celebrationStoreProvider.overrideWithValue(celebration),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    container.listen(deleteAllDataProvider, (_, _) {});
    return container;
  }

  test('erases, then resets what the app holds in memory', () async {
    final c = container();
    expect(await c.read(unitSystemProvider.future), UnitSystem.imperial);
    expect(await c.read(userProfileProvider.future), isNotNull);
    final revision = c.read(dataRevisionProvider);
    expect(await c.read(enabledModulesProvider.future), isNotEmpty);
    expect(await c.read(weekGoalProvider.future), 6);
    expect(
      await c.read(celebrationClosedProvider.future),
      const LocalDate(2026, 11, 15),
    );
    celebration.closed = null;
    weekGoal.goal = null;
    units.units = null;
    profiles.profile = null;
    await modules.write({});

    expect(await c.read(deleteAllDataProvider.notifier).delete(), isTrue);

    expect(eraser.erased, 1);
    expect(c.read(deleteAllDataProvider), DeletionStatus.idle);
    expect(c.read(themeModeProvider), ThemeMode.system);
    expect(c.read(syncIntervalProvider), SyncInterval.fallback);
    expect(scheduler.calls, isEmpty);
    expect(scheduler.cancels, 1);
    expect(await c.read(unitSystemProvider.future), UnitSystem.metric);
    expect(await c.read(userProfileProvider.future), isNull);
    expect(c.read(dataRevisionProvider), revision + 1);
    expect(c.read(onboardingProvider), isFalse);
    expect(onboarding.completed, isFalse);
    expect(c.read(todayWidgetConfigProvider), TodayWidgetConfig());
    expect(widgetConfig.saved, isNull);
    expect(await c.read(enabledModulesProvider.future), isEmpty);
    expect(await c.read(weekGoalProvider.future), weekGoalDefault);
    expect(await c.read(celebrationClosedProvider.future), isNull);
  });

  test('Delete all data aborts a run so nothing is written back', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final reports = InMemoryAiReportStore();
    final events = StreamController<AnalysisEvent>();
    final c = container(
      FakeLocalDataEraser(
        onErase: () async {
          await reports.deleteAll();
          await SharedPreferencesAsync().clear(
            allowList: SharedPreferencesAiRunMarkerStore.keys,
          );
        },
      ),
      [
        aiEnabledProvider.overrideWithValue(true),
        aiPayloadProvider.overrideWith(
          (ref) async => const AiPayloadReady(_payload),
        ),
        aiConfigStoreProvider.overrideWithValue(
          InMemoryAiConfigStore()
            ..config = const AiConfig(
              baseUrl: 'https://api.example.com/v1',
              model: 'm',
            ),
        ),
        aiReportStoreProvider.overrideWithValue(reports),
        aiRunMarkerStoreProvider.overrideWithValue(
          SharedPreferencesAiRunMarkerStore(),
        ),
        analysisModelFactoryProvider.overrideWithValue(
          (config) async => _HeldModel(events.stream),
        ),
      ],
    );
    final sub = c.listen(analysisRunControllerProvider, (_, _) {});
    addTearDown(sub.close);
    final run = c.read(analysisRunControllerProvider.notifier).send();
    await pumpEventQueue();
    expect(c.read(analysisRunControllerProvider), isA<AnalysisSending>());

    expect(await c.read(deleteAllDataProvider.notifier).delete(), isTrue);
    events.add(
      const AnalysisCompleted(
        text: '{"summary":"ok","cards":[]}',
        finishReason: 'stop',
        usage: AiTokenUsage(promptTokens: 100, completionTokens: 50),
      ),
    );
    await run;
    await pumpEventQueue();

    expect(reports.reports, isEmpty);
    expect(
      await SharedPreferencesAsync().getKeys(),
      isNot(contains(SharedPreferencesAiRunMarkerStore.monthKey)),
    );
  });

  test('a failed erase reports failure and keeps the settings', () async {
    final c = container(FakeLocalDataEraser(fail: true));

    expect(await c.read(deleteAllDataProvider.notifier).delete(), isFalse);

    expect(c.read(deleteAllDataProvider), DeletionStatus.failed);
    expect(c.read(themeModeProvider), ThemeMode.dark);
    expect(c.read(onboardingProvider), isTrue);
    expect(c.read(todayWidgetConfigProvider).theme, WidgetTheme.light);
    expect(await c.read(enabledModulesProvider.future), {
      ModuleId.body,
      ModuleId.trajectory,
    });
  });

  test('a second tap while deleting does nothing', () async {
    final hold = Completer<void>();
    final c = container(FakeLocalDataEraser(hold: hold));
    final notifier = c.read(deleteAllDataProvider.notifier);

    final first = notifier.delete();
    expect(c.read(deleteAllDataProvider), DeletionStatus.deleting);
    expect(await notifier.delete(), isFalse);
    hold.complete();

    expect(await first, isTrue);
    expect(eraser.erased, 1);
  });
}

const _payload = BuiltAiPayload(
  contextMap: {'reply_language': 'en'},
  canonicalContextJson: '{}',
  systemPrompt: 'system',
  userMessage: 'user',
  facts: [],
  estimatedTokens: 1,
  contextTokens: 1,
  cacheKey: 'context-sha',
  droppedCount: 0,
);

final class _HeldModel implements AnalysisModel {
  new(this.events);

  final Stream<AnalysisEvent> events;

  @override
  Stream<AnalysisEvent> generate(
    AnalysisRequest request, {
    required Future<void> cancel,
  }) => events;

  @override
  Future<List<String>> listModels() => throw UnimplementedError();

  @override
  Future<ConnectionProbe> probe() => throw UnimplementedError();
}
