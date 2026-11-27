import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/theme_mode_controller.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/ai_report_providers.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/application/health_context_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/analysis_run_state.dart';
import 'package:open_ring/features/ai/domain/health_context_assembly.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/infrastructure/shared_preferences_ai_run_marker_store.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
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
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';
import 'package:open_ring/features/widgets/application/widget_providers.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/database.dart';
import '../../../helpers/fake_sync_scheduler.dart';
import '../../../helpers/in_memory_sync_interval_store.dart';
import '../../../helpers/in_memory_theme_mode_store.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart' show FakeSyncStore;
import '../../../helpers/settings_fakes.dart';
import '../../../helpers/widget_fakes.dart';
import '../../food/application/meal_analysis_harness.dart';

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

  group('Delete all data during an AI run', () {
    late _GatedReports reports;
    late StreamController<AnalysisEvent> events;
    late int requests;
    late Completer<void>? factoryGate;

    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      reports = _GatedReports();
      events = StreamController<AnalysisEvent>();
      requests = 0;
      factoryGate = null;
    });

    ProviderContainer aiContainer() {
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
            (ref, _) async => const AiPayloadReady(_payload),
          ),
          aiConfigStoreProvider.overrideWithValue(
            InMemoryAiConfigStore()
              ..config = const AiConfig(
                baseUrl: 'https://api.example.com/v1',
                model: 'm',
              )
              ..consent = const AiConsent(
                consentedAtUtcMs: 0,
                policyEffectiveDate: aiCurrentPolicyEffectiveDate,
                hostKey: 'https://api.example.com:443',
                detailLevel: AiDetailLevel.standard,
                contextSchemaVersion: aiContextSchemaVersion,
              ),
          ),
          aiReportStoreProvider.overrideWithValue(reports),
          aiRunMarkerStoreProvider.overrideWithValue(
            SharedPreferencesAiRunMarkerStore(),
          ),
          analysisModelFactoryProvider.overrideWithValue((config) async {
            await factoryGate?.future;
            return _HeldModel(events.stream, () => requests++);
          }),
        ],
      );
      final sub = c.listen(analysisRunControllerProvider, (_, _) {});
      addTearDown(sub.close);
      return c;
    }

    void answer() => events.add(
      const AnalysisCompleted(
        text: '{"summary":"ok","cards":[]}',
        finishReason: 'stop',
        usage: AiTokenUsage(promptTokens: 100, completionTokens: 50),
      ),
    );

    Future<void> expectNothingWritten() async {
      expect(reports.inner.reports, isEmpty);
      expect(
        await SharedPreferencesAsync().getKeys(),
        isNot(contains(SharedPreferencesAiRunMarkerStore.monthKey)),
      );
    }

    test('mid stream: the run is aborted and writes nothing back', () async {
      final c = aiContainer();
      final run = c.read(analysisRunControllerProvider.notifier).send();
      await pumpEventQueue();
      expect(c.read(analysisRunControllerProvider), isA<AnalysisSending>());

      expect(await c.read(deleteAllDataProvider.notifier).delete(), isTrue);
      answer();
      await run;
      await pumpEventQueue();

      await expectNothingWritten();
    });

    test('while send is still preparing: no request goes out', () async {
      factoryGate = Completer<void>();
      final c = aiContainer();
      final run = c.read(analysisRunControllerProvider.notifier).send();
      await pumpEventQueue();

      final deleting = c.read(deleteAllDataProvider.notifier).delete();
      await pumpEventQueue();
      factoryGate!.complete();
      expect(await deleting, isTrue);
      await run;
      await pumpEventQueue();

      expect(requests, 0);
      await expectNothingWritten();
    });

    test('while the report insert is pending: the erase waits', () async {
      reports.gate = Completer<void>();
      final c = aiContainer();
      final run = c.read(analysisRunControllerProvider.notifier).send();
      await pumpEventQueue();
      answer();
      await pumpEventQueue();
      expect(reports.pending, 1);

      final deleting = c.read(deleteAllDataProvider.notifier).delete();
      await pumpEventQueue();
      reports.gate!.complete();
      expect(await deleting, isTrue);
      await run;
      await pumpEventQueue();

      await expectNothingWritten();
    });
  });

  test('a photo send in flight is aborted: no other request and no tokens '
      'after the wipe', () async {
    final h = MealQueueHarness();
    final answer = Completer<AnalysisEvent>();
    h.respond = () => answer.future;
    final a = await h.meal();
    await h.queued(a);
    await h.queued(
      await h.meal(photo: 'meal_2.jpg'),
      at: h.now.add(const Duration(seconds: 1)),
    );
    final c = container(
      FakeLocalDataEraser(onErase: () => h.analyses.deleteAll()),
      [
        ...h.overrides,
        aiEnabledProvider.overrideWithValue(true),
        foodEnabledProvider.overrideWithValue(true),
      ],
    );
    final pass = c.read(mealAnalysisQueueProvider.notifier).drain();
    while (h.requests.isEmpty) {
      await pumpEventQueue(times: 1);
    }

    expect(await c.read(deleteAllDataProvider.notifier).delete(), isTrue);
    answer.complete(completed());
    await pass;
    await pumpEventQueue();

    expect(h.requests, hasLength(1));
    expect(h.markers.monthSum, 0);
    expect(await rowCount(h.db, 'meal_analyses'), 0);
  });

  test('a photo pass that throws leaves Delete all data working, '
      'twice', () async {
    final h = MealQueueHarness()
      ..failingSecrets = FailingSecretStore(failRead: true);
    await h.queued(await h.meal());
    final c = container(FakeLocalDataEraser(), [
      ...h.overrides,
      aiEnabledProvider.overrideWithValue(true),
      foodEnabledProvider.overrideWithValue(true),
    ]);
    await c.read(mealAnalysisQueueProvider.notifier).drain();

    expect(await c.read(deleteAllDataProvider.notifier).delete(), isTrue);
    expect(await c.read(deleteAllDataProvider.notifier).delete(), isTrue);
    expect(h.requests, isEmpty);
  });

  test('an enqueue in flight writes no use and no row after the '
      'wipe', () async {
    final h = MealQueueHarness();
    final mealId = await h.meal();
    final c = container(
      FakeLocalDataEraser(onErase: () => h.analyses.deleteAll()),
      [
        ...h.overrides,
        aiEnabledProvider.overrideWithValue(true),
        foodEnabledProvider.overrideWithValue(true),
      ],
    );
    final queue = c.read(mealAnalysisQueueProvider.notifier)..toBackground();
    final gate = h.markers.photoGate = Completer<void>();
    final enqueued = queue.enqueue(mealId);
    while (h.markers.photoGate != null) {
      await pumpEventQueue(times: 1);
    }

    final deleting = c.read(deleteAllDataProvider.notifier).delete();
    await pumpEventQueue();
    gate.complete();

    expect(await deleting, isTrue);
    expect(await enqueued, EnqueueOutcome.unavailable);
    expect(h.markers.photoDays, isEmpty);
    expect(await rowCount(h.db, 'meal_analyses'), 0);
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

  test('erasing resets v2 widget config, disables This week availability, '
      'and publishes an unpaired snapshot', () async {
    final scenario = fullDataScenario;
    final gateway = FakeWidgetGateway();
    final ring = MutableRingStatusReader(freshRing);
    final customModules = InMemoryModuleStore({
      ModuleId.openScore,
      ModuleId.body,
      ModuleId.effort,
      ModuleId.goals,
    });
    final customHideNumbers = InMemoryHideNumbersStore();
    final customProfiles = InMemoryUserProfileStore(fullProfile);
    final customUnits = InMemoryUnitSystemStore(UnitSystem.imperial);
    final customWidgetConfig = InMemoryTodayWidgetConfigStore(
      TodayWidgetConfig(
        metrics: const [
          WidgetMetric.dayScore,
          WidgetMetric.weight,
          WidgetMetric.sleep,
          WidgetMetric.steps,
          WidgetMetric.heartRate,
          WidgetMetric.spo2,
        ],
      ).withTheme(WidgetTheme.dark),
    );
    final eraser = FakeLocalDataEraser(
      onErase: () async {
        await customModules.write({});
        await customHideNumbers.write(hidden: false);
        customProfiles.profile = null;
        customUnits.units = null;
        ring.value = RingStatus.unpaired;
      },
    );
    final c = ProviderContainer(
      overrides: [
        localDataEraserProvider.overrideWithValue(eraser),
        themeModeStoreProvider.overrideWithValue(
          InMemoryThemeModeStore(ThemeMode.dark),
        ),
        syncIntervalStoreProvider.overrideWithValue(
          InMemorySyncIntervalStore(SyncInterval.minutes15),
        ),
        syncSchedulerProvider.overrideWithValue(FakeSyncScheduler()),
        syncStoreProvider.overrideWithValue(FakeSyncStore()),
        unitSystemStoreProvider.overrideWithValue(customUnits),
        userProfileStoreProvider.overrideWithValue(customProfiles),
        onboardingStoreProvider.overrideWithValue(
          InMemoryOnboardingStore(completed: true),
        ),
        todayWidgetConfigStoreProvider.overrideWithValue(customWidgetConfig),
        moduleStoreProvider.overrideWithValue(customModules),
        weekGoalStoreProvider.overrideWithValue(InMemoryWeekGoalStore(6)),
        celebrationStoreProvider.overrideWithValue(
          InMemoryCelebrationStore('2026-11-15'),
        ),
        clockProvider.overrideWithValue(() => metricsNow),
        sleepHistoryReaderProvider.overrideWithValue(
          FakeSleepHistoryReader(scenario.spans),
        ),
        heartHistoryReaderProvider.overrideWithValue(scenario.heart),
        activityHistoryReaderProvider.overrideWithValue(
          FakeActivityHistoryReader(scenario.activity, slots: scenario.slots),
        ),
        ringStatusReaderProvider.overrideWithValue(ring),
        widgetGatewayProvider.overrideWithValue(gateway),
        hideNumbersStoreProvider.overrideWithValue(customHideNumbers),
      ],
    );
    addTearDown(c.dispose);
    c.listen(deleteAllDataProvider, (_, _) {});
    final sub = startWidgetPush(c);
    addTearDown(sub.close);
    await c.read(enabledModulesProvider.future);
    await c.read(unitSystemProvider.future);
    await c.read(widgetSnapshotProvider.future);
    await pumpEventQueue();

    expect(gateway.thisWeekAvailable.last, isTrue);
    expect(gateway.appearances.last['todayMetrics'], [
      'dayScore',
      'weight',
      'sleep',
      'steps',
      'heartRate',
      'spo2',
    ]);
    expect(gateway.snapshots.last['paired'], isTrue);
    expect(gateway.snapshots.last['dayScore'], isNotNull);
    expect(gateway.snapshots.last['effort'], isNotNull);

    expect(await c.read(deleteAllDataProvider.notifier).delete(), isTrue);
    await c.read(enabledModulesProvider.future);
    await c.read(unitSystemProvider.future);
    await c.read(widgetSnapshotProvider.future);
    await pumpEventQueue();

    expect(c.read(todayWidgetConfigProvider), TodayWidgetConfig());
    expect(customWidgetConfig.saved, isNull);
    expect(gateway.thisWeekAvailable.last, isFalse);
    expect(gateway.appearances.last, {
      'appTheme': 'system',
      'todayTheme': 'app',
      'todayMetrics': ['sleep', 'steps', 'heartRate'],
      'units': 'metric',
    });
    expect(gateway.snapshots.last['paired'], isFalse);
    expect(gateway.snapshots.last['enabledModules'], isEmpty);
    expect(gateway.snapshots.last['dayScore'], isNull);
    expect(gateway.snapshots.last['weight'], isNull);
    expect(gateway.snapshots.last['energy'], isNull);
    expect(gateway.snapshots.last['effort'], isNull);
    expect(gateway.snapshots.last['goals'], isNull);
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
  new(this.events, this.onGenerate);

  final Stream<AnalysisEvent> events;
  final void Function() onGenerate;

  @override
  Stream<AnalysisEvent> generate(
    AnalysisRequest request, {
    required Future<void> cancel,
  }) {
    onGenerate();
    return events;
  }

  @override
  Future<List<String>> listModels() => throw UnimplementedError();

  @override
  Future<ConnectionProbe> probe({
    Future<void>? cancel,
    void Function()? onReached,
  }) => throw UnimplementedError();
}

final class _GatedReports implements AiReportStore {
  final InMemoryAiReportStore inner = InMemoryAiReportStore();
  Completer<void>? gate;
  int pending = 0;

  @override
  Future<int> insert(AiReport report) async {
    pending++;
    await gate?.future;
    return await inner.insert(report);
  }

  @override
  Future<AiReport?> newestDone(AiReportCacheKey key) => inner.newestDone(key);

  @override
  Future<List<AiReport>> recent({int limit = aiReportKeepCount}) =>
      inner.recent(limit: limit);

  @override
  Future<void> deleteAll() => inner.deleteAll();

  @override
  Future<void> applyRetention(DateTime nowUtc) => inner.applyRetention(nowUtc);
}
