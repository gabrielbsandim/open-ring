import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/food/application/meal_analysis_trigger.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';

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
}
