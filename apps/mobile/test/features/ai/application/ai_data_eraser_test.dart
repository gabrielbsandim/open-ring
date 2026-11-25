import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart' show MealTags;
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_data_eraser.dart';
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
import 'package:open_ring/features/ai/domain/meal_photo_result.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/infrastructure/drift_ai_report_store.dart';
import 'package:open_ring/features/ai/infrastructure/shared_preferences_ai_config_store.dart';
import 'package:open_ring/features/ai/infrastructure/shared_preferences_ai_run_marker_store.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/infrastructure/drift_meal_analysis_store.dart';
import 'package:open_ring/features/food/infrastructure/drift_meal_store.dart';
import 'package:open_ring/features/food/infrastructure/shared_preferences_food_energy_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/infrastructure/shared_preferences_module_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/database.dart';
import '../../food/application/meal_analysis_harness.dart';

const _hostKey = 'https://api.example.com:443';
const _optIn = '{"on":"2026-11-01","soft":null}';
final _at = DateTime.utc(2026, 11, 20, 12);

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

const Set<String> _removed = {
  SharedPreferencesAiConfigStore.configKey,
  SharedPreferencesAiConfigStore.consentKey,
  SharedPreferencesAiConfigStore.mealPhotoConsentKey,
  SharedPreferencesAiConfigStore.profilesKey,
  SharedPreferencesAiConfigStore.photoQueuePauseKey,
  SharedPreferencesAiRunMarkerStore.key,
};

const Set<String> _kept = {
  SharedPreferencesAiRunMarkerStore.monthKey,
  SharedPreferencesAiRunMarkerStore.photoUsesKey,
  SharedPreferencesFoodEnergyStore.key,
  SharedPreferencesModuleStore.key,
};

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
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Runs [afterDelete] once the rows are gone, so a run that was not aborted
/// first would write its report back after the delete.
final class _HookedReports implements AiReportStore {
  new(this.inner);

  final AiReportStore inner;
  Future<void> Function()? afterDelete;

  @override
  Future<int> insert(AiReport report) => inner.insert(report);

  @override
  Future<AiReport?> newestDone(AiReportCacheKey key) => inner.newestDone(key);

  @override
  Future<List<AiReport>> recent({int limit = aiReportKeepCount}) =>
      inner.recent(limit: limit);

  @override
  Future<void> deleteAll() async {
    await inner.deleteAll();
    await afterDelete?.call();
  }

  @override
  Future<void> applyRetention(DateTime nowUtc) => inner.applyRetention(nowUtc);
}

void main() {
  late AppDatabase db;
  late SecretStore secrets;
  late int built;
  late String? lastKey;
  late int requests;
  late StreamController<AnalysisEvent> events;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    db = await pairedDatabase();
    secrets = InMemorySecretStore()..values[aiApiKeySecretName] = 'sk-ab3X';
    built = 0;
    lastKey = null;
    requests = 0;
    events = StreamController<AnalysisEvent>();
    addTearDown(() => unawaited(events.close()));

    final configs = SharedPreferencesAiConfigStore();
    await configs.writeConfig(
      const AiConfig(
        baseUrl: 'https://api.example.com/v1',
        model: 'm',
        keyLastFour: 'ab3X',
      ),
    );
    await configs.writeConsent(
      const AiConsent(
        consentedAtUtcMs: 0,
        policyEffectiveDate: aiCurrentPolicyEffectiveDate,
        hostKey: _hostKey,
        detailLevel: AiDetailLevel.standard,
        contextSchemaVersion: aiContextSchemaVersion,
      ),
    );
    await configs.writeMealPhotoConsent(
      const AiMealPhotoConsent(
        consentedAtUtcMs: 0,
        policyEffectiveDate: aiCurrentPolicyEffectiveDate,
        hostKey: _hostKey,
      ),
    );
    await configs.writeCapabilityProfile(
      _hostKey,
      'm',
      AiCapabilityProfile.defaults,
    );
    await configs.writePhotoQueuePause(
      const AiPhotoQueuePause(
        reason: AiPhotoQueuePauseReason.unauthorized,
        hostKey: _hostKey,
        model: 'm',
        keyLastFour: 'ab3X',
        atUtcMs: 1,
      ),
    );
    final markers = SharedPreferencesAiRunMarkerStore();
    await markers.write(sampleAiReport(at: _at));
    await markers.addMonthTokens('2026-11', 150);
    await markers.addPhotoUses('2026-11-20', 2);
    await SharedPreferencesAsync().setString(
      SharedPreferencesFoodEnergyStore.key,
      _optIn,
    );
    await SharedPreferencesModuleStore().write({ModuleId.ai, ModuleId.food});
  });

  ProviderContainer container([
    List<Override> extra = const [],
    AiReportStore? reports,
  ]) {
    final c = ProviderContainer(
      overrides: [
        aiConfigStoreProvider.overrideWithValue(
          SharedPreferencesAiConfigStore(),
        ),
        aiRunMarkerStoreProvider.overrideWithValue(
          SharedPreferencesAiRunMarkerStore(),
        ),
        moduleStoreProvider.overrideWithValue(SharedPreferencesModuleStore()),
        secretStoreProvider.overrideWithValue(secrets),
        aiReportStoreProvider.overrideWithValue(
          reports ?? DriftAiReportStore(db),
        ),
        mealAnalysisStoreProvider.overrideWithValue(DriftMealAnalysisStore(db)),
        keyedAnalysisModelFactoryProvider.overrideWithValue((config, key) {
          built++;
          lastKey = key;
          return _HeldModel(events.stream, () => requests++);
        }),
        ...extra,
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<int> seedMeal() async {
    final meal = await DriftMealStore(db).add(
      MealDraft(at: _at, offsetMinutes: 0, tags: const MealTags(protein: true)),
      now: _at,
      photo: 'meal_1.jpg',
    );
    final store = DriftMealAnalysisStore(db);
    final row = await store.enqueue(meal.id, 'meal_1.jpg', (
      providerHost: _hostKey,
      model: 'm',
      promptVersion: 1,
      outputSchema: 2,
    ), now: _at);
    await store.markSending(row.id, now: _at);
    await store.complete(row.id, const (
      status: MealAnalysisStatus.done,
      sent: (sha256: 'sha', width: 768, height: 576, bytes: 1),
      rawText: 'raw',
      confidence: MealPhotoConfidence.medium,
      usage: null,
      cost: null,
      errorKind: null,
      suggestion: MealPhotoSuggestion(
        isFood: MealPhotoFlag.yes,
        kind: MealPhotoKind.main,
        protein: MealPhotoFlag.yes,
        caffeine: MealPhotoFlag.no,
        fried: MealPhotoFlag.no,
        sugaryDrink: MealPhotoFlag.no,
        veg: MealPhotoVeg.some,
        alcohol: MealPhotoAlcohol.none,
        processed: MealPhotoProcessed.notMostly,
        items: [
          MealPhotoItem(
            name: 'rice',
            measure: MealPhotoMeasure.bowl,
            countX2: 2,
            grams: 300,
          ),
        ],
      ),
    ), now: _at);
    expect(await store.confirmItems(row.id), isTrue);
    return meal.id;
  }

  Future<Map<String, Object?>> keptPrefs() async {
    final all = await SharedPreferencesAsync().getAll();
    return {for (final key in _kept) key: all[key]};
  }

  test('removes every AI store and keeps counters, opt in, module and '
      'meals', () async {
    await DriftAiReportStore(db).insert(sampleAiReport(at: _at));
    await DriftAiReportStore(db)
        .insert(sampleAiReport(at: _at.add(const Duration(hours: 1))));
    await seedMeal();
    final keptBefore = await keptPrefs();
    expect(keptBefore.values, everyElement(isNotNull));
    expect(await SharedPreferencesAsync().getKeys(), containsAll(_removed));
    expect(await rowCount(db, 'meal_items'), 1);
    final c = container();
    expect(await c.read(aiConfigProvider.future), isNot(AiConfig.defaults));

    expect(await c.read(aiDataEraserProvider).clear(), isTrue);

    final keys = await SharedPreferencesAsync().getKeys();
    expect(keys.intersection(_removed), isEmpty);
    expect(await keptPrefs(), keptBefore);
    expect(await secrets.read(aiApiKeySecretName), isNull);
    expect(await rowCount(db, 'ai_reports'), 0);
    expect(await rowCount(db, 'meal_analyses'), 0);
    expect(await rowCount(db, 'meal_items'), 0);
    expect(await rowCount(db, 'meals'), 1);
    final tags = await db
        .customSelect('SELECT protein, photo FROM meals')
        .getSingle();
    expect(tags.read<bool>('protein'), isTrue);
    expect(tags.read<String>('photo'), 'meal_1.jpg');
    expect(await c.read(aiConfigProvider.future), AiConfig.defaults);
    expect(await c.read(aiConsentProvider.future), isNull);
    expect(await c.read(aiMealPhotoConsentProvider.future), isNull);
    expect(await c.read(aiRecentReportsProvider.future), isEmpty);
    expect(
      await c.read(aiAvailabilityProvider.future),
      AiAvailability.notConfigured,
    );
    expect(await c.read(enabledModulesProvider.future), {
      ModuleId.ai,
      ModuleId.food,
    });
    expect(built, 0);
  });

  test('a keystore failure keeps the config and the key, and a retry '
      'clears everything', () async {
    final flaky = FlakySecretStore()
      ..values[aiApiKeySecretName] = 'sk-ab3X'
      ..failDeletes = 1;
    secrets = flaky;
    await DriftAiReportStore(db).insert(sampleAiReport(at: _at));
    await seedMeal();
    final keptBefore = await keptPrefs();
    final c = container();

    expect(await c.read(aiDataEraserProvider).clear(), isFalse);

    expect(flaky.deleteCalls, 1);
    expect(await rowCount(db, 'ai_reports'), 0);
    expect(await rowCount(db, 'meal_analyses'), 0);
    expect(await rowCount(db, 'meal_items'), 0);
    var keys = await SharedPreferencesAsync().getKeys();
    expect(keys, containsAll(SharedPreferencesAiConfigStore.keys));
    expect(keys, isNot(contains(SharedPreferencesAiRunMarkerStore.key)));
    expect(await keptPrefs(), keptBefore);
    expect(flaky.values[aiApiKeySecretName], 'sk-ab3X');
    final kept = await c.read(aiConfigProvider.future);
    expect(kept.hostKey, _hostKey);
    expect(kept.keyLastFour, 'ab3X');

    expect(await c.read(aiDataEraserProvider).clear(), isTrue);

    keys = await SharedPreferencesAsync().getKeys();
    expect(keys.intersection(_removed), isEmpty);
    expect(await keptPrefs(), keptBefore);
    expect(flaky.values, isEmpty);
    expect(await c.read(aiConfigProvider.future), AiConfig.defaults);
  });

  test(
    'a host change after a failed Remove cannot reach the old key',
    () async {
      final flaky = FlakySecretStore()
        ..values[aiApiKeySecretName] = 'sk-ab3X'
        ..failDeletes = 1;
      secrets = flaky;
      final c = container();
      expect(await c.read(aiDataEraserProvider).clear(), isFalse);

      await c
          .read(aiConfigProvider.notifier)
          .save(
            const AiConfig(baseUrl: 'https://other.example.com/v1', model: 'm'),
          );
      final config = await c.read(aiConfigProvider.future);
      await c.read(analysisModelFactoryProvider)(config);

      expect(flaky.values, isEmpty);
      expect(config.keyLastFour, isNull);
      expect(built, 1);
      expect(lastKey, isNull);
      expect(requests, 0);
    },
  );

  test('a reading in flight is aborted before the delete: an answer that '
      'lands right after the rows go writes nothing', () async {
    await SharedPreferencesAsync().remove(
      SharedPreferencesAiRunMarkerStore.key,
    );
    final reports = _HookedReports(DriftAiReportStore(db));
    final c = container([
      aiEnabledProvider.overrideWithValue(true),
      aiPayloadProvider.overrideWith(
        (ref, _) async => const AiPayloadReady(_payload),
      ),
    ], reports);
    final sub = c.listen(analysisRunControllerProvider, (_, _) {});
    addTearDown(sub.close);
    final tokensBefore = await SharedPreferencesAiRunMarkerStore().monthTokens(
      '2026-11',
    );
    reports.afterDelete = () async {
      events.add(
        const AnalysisCompleted(
          text: '{"summary":"ok","cards":[]}',
          finishReason: 'stop',
          usage: AiTokenUsage(promptTokens: 100, completionTokens: 50),
        ),
      );
      await pumpEventQueue();
    };

    final run = c.read(analysisRunControllerProvider.notifier).send();
    await pumpEventQueue();
    expect(c.read(analysisRunControllerProvider), isA<AnalysisSending>());
    expect(requests, 1);

    expect(await c.read(aiDataEraserProvider).clear(), isTrue);
    await run;
    await pumpEventQueue();

    expect(await rowCount(db, 'ai_reports'), 0);
    expect(
      await SharedPreferencesAiRunMarkerStore().monthTokens('2026-11'),
      tokensBefore,
    );
    expect(await secrets.read(aiApiKeySecretName), isNull);
    expect(requests, 1);
  });

  test('a photo send in flight is aborted: one request, no row and no '
      'tokens after Remove', () async {
    final h = MealQueueHarness();
    final answer = Completer<AnalysisEvent>();
    h
      ..respond = (() => answer.future)
      ..extraOverrides = [
        aiReportStoreProvider.overrideWithValue(DriftAiReportStore(h.db)),
        aiEnabledProvider.overrideWithValue(true),
        foodEnabledProvider.overrideWithValue(true),
      ];
    await h.queued(await h.meal());
    await h.queued(
      await h.meal(photo: 'meal_2.jpg'),
      at: h.now.add(const Duration(seconds: 1)),
    );
    final pass = h.queue.drain();
    while (h.requests.isEmpty) {
      await pumpEventQueue(times: 1);
    }

    expect(await h.container.read(aiDataEraserProvider).clear(), isTrue);
    answer.complete(completed());
    await pass;
    await pumpEventQueue();

    expect(h.requests, hasLength(1));
    expect(h.markers.monthSum, 0);
    expect(await rowCount(h.db, 'meal_analyses'), 0);
    expect(await rowCount(h.db, 'meals'), 2);
    expect(h.secrets.values, isEmpty);
  });
}
