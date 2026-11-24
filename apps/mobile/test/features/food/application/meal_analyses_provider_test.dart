import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';

import 'meal_analysis_harness.dart';

void main() {
  late MealQueueHarness h;

  setUp(() {
    h = MealQueueHarness();
    h.onAnalysisWrite = () =>
        h.container.read(mealAnalysisRevisionProvider.notifier).bump();
  });

  test('the rows of a meal come latest first and follow each write', () async {
    final meal = await h.meal();
    final older = await h.queued(meal);
    await h.analyses.skip(
      older,
      MealAnalysisErrorKind.cancelled,
      now: h.now.add(const Duration(minutes: 1)),
    );
    final newer = await h.queued(
      meal,
      at: h.now.add(const Duration(minutes: 5)),
      target: (
        providerHost: hostKey,
        model: 'other-m',
        promptVersion: photoTarget.promptVersion,
        outputSchema: photoTarget.outputSchema,
      ),
    );
    final sub = h.container.listen(mealAnalysesProvider(meal), (_, _) {});
    addTearDown(sub.close);

    final rows = await h.container.read(mealAnalysesProvider(meal).future);
    expect([for (final r in rows) r.id], [newer, older]);
  });

  test('the keep flag reads again after a write', () async {
    final meal = await h.meal();
    final sub = h.container.listen(mealKeepOnPhoneProvider(meal), (_, _) {});
    addTearDown(sub.close);
    expect(
      await h.container.read(mealKeepOnPhoneProvider(meal).future),
      isFalse,
    );

    await h.analyses.setKeepOnPhone(meal, keep: true);
    expect(
      await h.container.read(mealKeepOnPhoneProvider(meal).future),
      isTrue,
    );
  });
}
