import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/application/health_context_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/meal_photo_prompt.dart';
import 'package:open_ring/features/ai/domain/meal_photo_wire.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/domain/meal_analysis_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/infrastructure/drift_meal_analysis_store.dart';
import 'package:open_ring/features/food/infrastructure/drift_meal_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/database.dart';
import '../../ai/wire_jpeg_fixture.dart';

const String hostKey = 'https://api.example.com:443';
const String photoModel = 'vision-m';

const MealAnalysisTarget photoTarget = (
  providerHost: hostKey,
  model: photoModel,
  promptVersion: aiMealPromptVersion,
  outputSchema: 1,
);

const AiConfig testedConfig = AiConfig(
  baseUrl: 'https://api.example.com/v1',
  model: 'text-m',
  photoModel: photoModel,
  testedAtUtcMs: 1764000000000,
  testedHostKey: hostKey,
  testedModel: 'text-m',
);

String mealAnswer({String isFood = 'yes'}) => jsonEncode({
  'is_food': isFood,
  'kind': 'main',
  'protein': 'yes',
  'caffeine': 'no',
  'fried': 'no',
  'sugary_drink': 'no',
  'veg': 'some',
  'alcohol': 'none',
  'processed': 'not_mostly',
  'confidence': 'high',
});

AnalysisEvent completed([String? text]) => AnalysisCompleted(
  text: text ?? mealAnswer(),
  finishReason: 'stop',
  usage: const AiTokenUsage(promptTokens: 300, completionTokens: 20),
);

/// Records every request and answers with the harness reply, which may throw an
/// [AnalysisFailure] or never settle.
final class FakePhotoModel implements AnalysisModel {
  new(this.harness);

  final MealQueueHarness harness;

  @override
  Stream<AnalysisEvent> generate(
    AnalysisRequest request, {
    required Future<void> cancel,
  }) async* {
    harness.requests.add(request);
    harness.inFlight++;
    if (harness.inFlight > harness.maxInFlight) {
      harness.maxInFlight = harness.inFlight;
    }
    try {
      yield await harness.respond();
    } finally {
      harness.inFlight--;
    }
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class MealQueueHarness {
  final AppDatabase db = memoryDatabase();
  late final DriftMealStore meals = DriftMealStore(db);
  late final GatedAnalysisStore analyses = GatedAnalysisStore(
    DriftMealAnalysisStore(db),
  );
  final InMemoryPhotoStore photos = InMemoryPhotoStore();
  final InMemoryAiRunMarkerStore markers = InMemoryAiRunMarkerStore();
  final InMemorySecretStore secrets = InMemorySecretStore()
    ..values[aiApiKeySecretName] = 'sk-test-1234';
  final InMemoryAiConfigStore configStore = InMemoryAiConfigStore()
    ..config = testedConfig
    ..mealPhotoConsent = const AiMealPhotoConsent(
      consentedAtUtcMs: 1764000000000,
      policyEffectiveDate: aiCurrentPolicyEffectiveDate,
      hostKey: hostKey,
    )
    ..profiles[aiCapabilityProfileKey(hostKey, photoModel)] =
        const AiCapabilityProfile(vision: AiVisionSupport.yes);
  Set<ModuleId> modules = {ModuleId.ai, ModuleId.food};
  late final InMemoryModuleStore moduleStore = InMemoryModuleStore(modules);

  DateTime now = DateTime(2026, 11, 24, 12);
  DateTime Function()? clock;
  bool demo = false;
  final List<AnalysisRequest> requests = [];
  final List<Duration> sentAt = [];
  int inFlight = 0;
  int maxInFlight = 0;
  FutureOr<AnalysisEvent> Function() respond = completed;
  Duration Function()? elapsed;
  Completer<void>? encodeGate;
  SecretStore? failingSecrets;

  late final ProviderContainer container = _container();

  ProviderContainer _container() {
    final c = ProviderContainer(
      overrides: [
        moduleStoreProvider.overrideWithValue(moduleStore),
        ...overrides,
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Every override but the module store, for a container of another test.
  List<Override> get overrides => [
    demoModeStoreProvider.overrideWithValue(
      InMemoryDemoModeStore(enabled: demo),
    ),
    aiConfigStoreProvider.overrideWithValue(configStore),
    secretStoreProvider.overrideWithValue(failingSecrets ?? secrets),
    aiRunMarkerStoreProvider.overrideWithValue(markers),
    aiReplyLanguageProvider.overrideWithValue('en'),
    clockProvider.overrideWithValue(() => clock?.call() ?? now),
    mealStoreProvider.overrideWithValue(meals),
    photoStoreProvider.overrideWithValue(photos),
    mealAnalysisStoreProvider.overrideWithValue(analyses),
    wirePhotoEncoderProvider.overrideWithValue((stored) async {
      await encodeGate?.future;
      return prepareWirePhoto(stored);
    }),
    keyedAnalysisModelFactoryProvider.overrideWithValue((config, key) {
      expect(
        (config.trimmedModel, key),
        (photoModel, secrets.values[aiApiKeySecretName]),
      );
      sentAt.add(elapsed?.call() ?? Duration.zero);
      return FakePhotoModel(this);
    }),
  ];

  MealAnalysisQueue get queue =>
      container.read(mealAnalysisQueueProvider.notifier);

  /// Loads the module list, so the AI and Food gates read on.
  Future<void> start() => container.read(enabledModulesProvider.future);

  Future<int> meal({String photo = 'meal_1.jpg', bool save = true}) async {
    if (save) await photos.save(photo, leakyPhoto());
    final row = await meals.add(
      MealDraft(at: now, offsetMinutes: -180),
      now: now,
      photo: photo,
    );
    return row.id;
  }

  /// A row written straight to the store, bypassing the gate.
  Future<int> queued(
    int mealId, {
    DateTime? at,
    MealAnalysisTarget target = photoTarget,
  }) async {
    final name = (await meals.byId(mealId))!.photo!;
    final row = await analyses.enqueue(mealId, name, target, now: at ?? now);
    return row.id;
  }

  Future<MealAnalysis> row(int mealId) async =>
      (await analyses.byMeal(mealId)).single;
}

/// Delegates to drift; [markGate] holds a row after it turned sending and
/// before the queue hears back.
final class GatedAnalysisStore implements MealAnalysisStore {
  new(this.inner);

  final MealAnalysisStore inner;
  Completer<void>? markGate;

  @override
  Future<bool> markSending(int id, {required DateTime now}) async {
    final moved = await inner.markSending(id, now: now);
    await markGate?.future;
    return moved;
  }

  @override
  Future<MealAnalysis> enqueue(
    int mealId,
    String photoName,
    MealAnalysisTarget target, {
    required DateTime now,
    bool again = false,
  }) => inner.enqueue(mealId, photoName, target, now: now, again: again);

  @override
  Future<List<MealAnalysis>> byMeal(int mealId) => inner.byMeal(mealId);

  @override
  Future<MealAnalysis?> byId(int id) => inner.byId(id);

  @override
  Future<MealAnalysis?> next() => inner.next();

  @override
  Future<bool> requeue(int id, {required DateTime now}) =>
      inner.requeue(id, now: now);

  @override
  Future<bool> countResend(int id, {required DateTime now}) =>
      inner.countResend(id, now: now);

  @override
  Future<bool> retry(int id, {required DateTime now}) =>
      inner.retry(id, now: now);

  @override
  Future<bool> complete(
    int id,
    MealAnalysisAnswer answer, {
    required DateTime now,
  }) => inner.complete(id, answer, now: now);

  @override
  Future<bool> fail(int id, String errorKind, {required DateTime now}) =>
      inner.fail(id, errorKind, now: now);

  @override
  Future<bool> skip(int id, String reason, {required DateTime now}) =>
      inner.skip(id, reason, now: now);

  @override
  Future<int> countQueuedSince(DateTime since) => inner.countQueuedSince(since);

  @override
  Future<int> expireBefore(DateTime cutoff, {required DateTime now}) =>
      inner.expireBefore(cutoff, now: now);

  @override
  Future<int> skipOffTarget(
    String providerHost,
    String model, {
    required DateTime now,
  }) => inner.skipOffTarget(providerHost, model, now: now);

  @override
  Future<int> recoverInterrupted({required DateTime now}) =>
      inner.recoverInterrupted(now: now);

  @override
  Future<int> purgeRawBefore(DateTime cutoff) => inner.purgeRawBefore(cutoff);

  @override
  Future<bool> keepOnPhone(int mealId) => inner.keepOnPhone(mealId);

  @override
  Future<bool> setKeepOnPhone(int mealId, {required bool keep}) =>
      inner.setKeepOnPhone(mealId, keep: keep);

  @override
  Future<void> deleteAll() => inner.deleteAll();
}
