import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/food/application/meal_capture.dart';
import 'package:open_ring/features/food/application/meal_photo_saver.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/presentation/meal_capture_presenter.dart';
import 'package:open_ring/features/food/presentation/meal_keep_switch.dart';
import 'package:open_ring/features/food/presentation/meal_saved_sheet.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../application/meal_analysis_harness.dart';

class _Held extends MealCapture {
  new(this.result);

  final SaveResult result;

  @override
  CaptureState build() => CaptureState(result: result);
}

class _Present extends ConsumerWidget {
  const new(this.token, this.result);

  final Object token;
  final SaveResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: TextButton(
      key: const Key('present'),
      onPressed: () => unawaited(
        presentMealCapture(
          context: context,
          ref: ref,
          hostToken: token,
          result: result,
          recovered: false,
        ),
      ),
      child: const Text('present'),
    ),
  );
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late MealQueueHarness h;

  setUp(() => h = MealQueueHarness());

  Future<Meal> photoMeal() async => (await h.meals.byId(await h.meal()))!;

  Future<void> present(WidgetTester tester, Meal meal) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 2400);
    addTearDown(tester.view.reset);
    final result = SaveResult(SaveOutcome.saved, TimeSource.returned, meal);
    final token = Object();
    h.extraOverrides = [mealCaptureProvider.overrideWith(() => _Held(result))];
    h.container.read(mealCaptureHostsProvider).attach(token);
    await h.start();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: screenHost(_Present(token, result)),
      ),
    );
    await tester.tap(find.byKey(const Key('present')));
    await tester.pumpAndSettle();
    expect(find.byType(MealSavedSheet), findsOneWidget);
  }

  group('the AI slot is absent', () {
    testWidgets('with AI off', (tester) async {
      h.modules = {ModuleId.food};
      await present(tester, await photoMeal());
      expect(find.byKey(MealAiKeys.keep), findsNothing);
      expect(find.byKey(MealAiKeys.analyze), findsNothing);
    });

    testWidgets('in demo mode', (tester) async {
      h.demo = true;
      await present(tester, await photoMeal());
      expect(find.byKey(MealAiKeys.keep), findsNothing);
      expect(find.byKey(MealAiKeys.analyze), findsNothing);
    });

    testWidgets('for a meal without a photo', (tester) async {
      final meal = await h.meals.add(
        MealDraft(at: h.now, offsetMinutes: -180),
        now: h.now,
      );
      await present(tester, meal);
      expect(find.byKey(MealAiKeys.keep), findsNothing);
      expect(find.byKey(MealAiKeys.analyze), findsNothing);
    });
  });

  testWidgets('Analyze saves the sheet tags before the photo is enqueued', (
    tester,
  ) async {
    final meal = await photoMeal();
    MealKind? kindAtEnqueue;
    h.analyses.onEnqueue = (id) async =>
        kindAtEnqueue = (await h.meals.byId(id))?.kind;
    await present(tester, meal);
    expect(find.byKey(MealAiKeys.keep), findsOneWidget);
    await tester.tap(find.byKey(MealSavedSheetKeys.kind(MealKind.snack)));
    await tester.pump();
    await tester.tap(find.byKey(MealAiKeys.analyze));
    await tester.pumpAndSettle();

    expect(find.byType(MealSavedSheet), findsNothing);
    expect(kindAtEnqueue, MealKind.snack);
    expect(find.text(l10n.foodAiQueued), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('Done saves the tags and enqueues nothing', (tester) async {
    final meal = await photoMeal();
    await present(tester, meal);
    await tester.tap(find.byKey(MealSavedSheetKeys.kind(MealKind.snack)));
    await tester.pump();
    await tester.tap(find.byKey(MealSavedSheetKeys.done));
    await tester.pumpAndSettle();

    expect((await h.meals.byId(meal.id))?.kind, MealKind.snack);
    expect(await h.analyses.byMeal(meal.id), isEmpty);
  });
}
