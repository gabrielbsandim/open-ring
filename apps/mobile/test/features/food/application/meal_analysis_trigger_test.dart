import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/vision_probe_controller.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/openai_wire_codec.dart';
import 'package:open_ring/features/ai/domain/vision_probe.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/food/application/meal_analysis_trigger.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';

import 'meal_analysis_harness.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late MealQueueHarness h;

  void lifecycle(List<AppLifecycleState> states) =>
      states.forEach(binding.handleAppLifecycleStateChanged);

  setUp(() {
    lifecycle([AppLifecycleState.resumed]);
    h = MealQueueHarness();
  });

  Future<void> listen() async {
    h.container.listen(mealAnalysisTriggerProvider, (_, _) {});
    await pumpEventQueue();
  }

  test('a row queued before start is sent once the modules load', () async {
    final mealId = await h.meal();
    await h.queued(mealId);

    await listen();

    expect(h.requests, hasLength(1));
    expect((await h.row(mealId)).status, MealAnalysisStatus.done);
  });

  test('in the background a trigger sends nothing and resume drains', () async {
    await listen();
    lifecycle([AppLifecycleState.inactive, AppLifecycleState.hidden]);
    final mealId = await h.meal();
    await h.queued(mealId);

    await h.container
        .read(aiConfigProvider.notifier)
        .save(testedConfig.copyWith(photoDailyLimit: 5));
    lifecycle([AppLifecycleState.paused]);
    await pumpEventQueue();
    expect(h.requests, isEmpty);

    lifecycle([
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    await pumpEventQueue();
    expect(h.requests, hasLength(1));
  });

  test('a launch while paused sends nothing until resume', () async {
    lifecycle([
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    final mealId = await h.meal();
    await h.queued(mealId);

    await listen();
    expect(h.requests, isEmpty);

    lifecycle([
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    await pumpEventQueue();
    expect(h.requests, hasLength(1));
  });

  test('a config change runs a pass', () async {
    await listen();
    final mealId = await h.meal();
    await h.queued(mealId);

    await h.container
        .read(aiConfigProvider.notifier)
        .save(testedConfig.copyWith(photoDailyLimit: 5));
    await pumpEventQueue();

    expect(h.requests, hasLength(1));
  });

  test('a new photo consent runs a pass', () async {
    h.configStore.mealPhotoConsent = null;
    await listen();
    await h.container.read(aiMealPhotoConsentProvider.future);
    final mealId = await h.meal();
    await h.queued(mealId);

    h.configStore.mealPhotoConsent = const AiMealPhotoConsent(
      consentedAtUtcMs: 1764000000001,
      policyEffectiveDate: aiCurrentPolicyEffectiveDate,
      hostKey: hostKey,
    );
    h.container.invalidate(aiMealPhotoConsentProvider);
    await pumpEventQueue();

    expect(h.requests, hasLength(1));
  });

  test('a host change clears the photo consent and the provider rereads '
      'it', () async {
    expect(
      await h.container.read(aiMealPhotoConsentProvider.future),
      isNotNull,
    );

    await h.container
        .read(aiConfigProvider.notifier)
        .save(testedConfig.copyWith(baseUrl: 'https://other.example/v1'));

    expect(await h.container.read(aiMealPhotoConsentProvider.future), isNull);
  });

  test('a passing probe lifts a noVision pause and the trigger drains the '
      'row after it', () async {
    h.configStore
      ..profiles[aiCapabilityProfileKey(hostKey, photoModel)] =
          const AiCapabilityProfile(vision: AiVisionSupport.no)
      ..photoQueuePause = const AiPhotoQueuePause(
        reason: AiPhotoQueuePauseReason.noVision,
        hostKey: hostKey,
        model: photoModel,
        keyLastFour: null,
        atUtcMs: 1,
      );
    final c = ProviderContainer(
      overrides: [
        moduleStoreProvider.overrideWithValue(h.moduleStore),
        ...h.overrides,
        visionProbeRandomProvider.overrideWithValue(Random(11)),
      ],
    );
    addTearDown(c.dispose);
    final grid = VisionProbeGrid.random(Random(11));
    final probeAnswer = jsonEncode({
      for (final (i, cell) in grid.cells.indexed)
        visionProbeCellNames[i]: cell.name,
    });
    h.respond = () =>
        h.requests.length == 1 ? completed(probeAnswer) : completed();
    final mealId = await h.meal();
    await h.queued(mealId);
    c
      ..listen(mealAnalysisTriggerProvider, (_, _) {})
      ..listen(visionProbeControllerProvider, (_, _) {});
    await pumpEventQueue();
    expect(h.requests, isEmpty);

    await c.read(visionProbeControllerProvider.notifier).run();
    await pumpEventQueue();

    expect(h.configStore.photoQueuePause, isNull);
    expect(h.requests, hasLength(2));
    final row = (await h.analyses.byMeal(mealId)).single;
    expect(row.status, MealAnalysisStatus.done);
  });

  test(
    'a withdrawn photo consent skips a queued row on the next pass',
    () async {
      await listen();
      final mealId = await h.meal();
      await h.queued(mealId);

      await h.container
          .read(aiConfigProvider.notifier)
          .withdrawMealPhotoConsent();
      await pumpEventQueue();

      final row = await h.row(mealId);
      expect(row.status, MealAnalysisStatus.skipped);
      expect(row.errorKind, MealAnalysisErrorKind.noConsent);
      expect(h.requests, isEmpty);
    },
  );

  test('a limit of 3 set through the config makes the 4th enqueue today '
      'return dailyLimit', () async {
    await h.start();
    h.queue.toBackground();
    await h.container
        .read(aiConfigProvider.notifier)
        .edit((c) => c.copyWith(photoDailyLimit: 3));

    for (var i = 0; i < 3; i++) {
      final id = await h.meal(photo: 'meal_$i.jpg');
      expect(await h.queue.enqueue(id), EnqueueOutcome.queued);
    }
    final fourth = await h.meal(photo: 'meal_3.jpg');
    expect(await h.queue.enqueue(fourth), EnqueueOutcome.dailyLimit);
  });

  test('after a passing probe, a no vision 400 from the queue turns the '
      'vision state to text only', () async {
    h.configStore.profiles.clear();
    final c = ProviderContainer(
      overrides: [
        moduleStoreProvider.overrideWithValue(h.moduleStore),
        ...h.overrides,
        visionProbeRandomProvider.overrideWithValue(Random(11)),
      ],
    )..listen(aiPhotoVisionProvider, (_, _) {});
    addTearDown(c.dispose);
    final grid = VisionProbeGrid.random(Random(11));
    final probeAnswer = jsonEncode({
      for (final (i, cell) in grid.cells.indexed)
        visionProbeCellNames[i]: cell.name,
    });
    h.respond = () {
      if (h.requests.length == 1) return completed(probeAnswer);
      throw OpenAiWireCodec.classifyHttpError(
        statusCode: 400,
        body: jsonEncode({
          'error': {'message': 'Unsupported content type image_url'},
        }),
      );
    };
    await c.read(enabledModulesProvider.future);
    c.listen(visionProbeControllerProvider, (_, _) {});
    await c.read(visionProbeControllerProvider.notifier).run();
    expect(await c.read(aiPhotoVisionProvider.future), AiVisionSupport.yes);

    final mealId = await h.meal();
    await h.queued(mealId);
    await c.read(mealAnalysisQueueProvider.notifier).drain();

    expect(h.requests, hasLength(2));
    expect(await c.read(aiPhotoVisionProvider.future), AiVisionSupport.no);
  });
}
