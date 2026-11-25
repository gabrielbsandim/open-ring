import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/ai/domain/meal_photo_result.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/presentation/food_meal_screen.dart';
import 'package:open_ring/features/food/presentation/meal_analysis_section.dart';
import 'package:open_ring/features/food/presentation/meal_saved_sheet.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../application/meal_analysis_harness.dart';

const _suggestion = MealPhotoSuggestion(
  isFood: MealPhotoFlag.yes,
  kind: MealPhotoKind.main,
  protein: MealPhotoFlag.yes,
  caffeine: MealPhotoFlag.no,
  fried: MealPhotoFlag.unsure,
  sugaryDrink: MealPhotoFlag.no,
  veg: MealPhotoVeg.some,
  alcohol: MealPhotoAlcohol.none,
  processed: MealPhotoProcessed.unsure,
);

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late MealQueueHarness h;
  late int mealId;
  late int bumps;

  setUp(() {
    h = MealQueueHarness();
    h.onAnalysisWrite = () =>
        h.container.read(mealAnalysisRevisionProvider.notifier).bump();
  });

  Future<void> done(int id) async {
    final row = await h.queued(id);
    await h.analyses.markSending(row, now: h.now);
    await h.analyses.complete(row, (
      status: MealAnalysisStatus.done,
      sent: (sha256: 'abc', width: 768, height: 576, bytes: 4100),
      suggestion: _suggestion,
      confidence: MealPhotoConfidence.medium,
      rawText: '{}',
      usage: null,
      cost: null,
      errorKind: null,
    ), now: h.now);
  }

  Future<void> pump(
    WidgetTester tester, {
    MealEdit? tags,
    bool analyzed = true,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 3200);
    addTearDown(tester.view.reset);
    await h.start();
    mealId = await h.meal();
    if (tags != null) {
      final meal = (await h.meals.byId(mealId))!;
      await h.meals.update(meal.id, tags.draftOf(meal));
    }
    if (analyzed) await done(mealId);
    bumps = 0;
    h.container.listen(dataRevisionProvider, (_, _) => bumps++);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: screenHost(FoodMealScreen(mealId: mealId)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder dashed(Key key) =>
      find.descendant(of: find.byKey(key), matching: find.byType(ActionChip));

  Future<Meal> stored() async => (await h.meals.byId(mealId))!;

  testWidgets('a done row draws the mapped chips dashed and changes no '
      'metric', (tester) async {
    await pump(tester);

    expect(dashed(MealSavedSheetKeys.kind(MealKind.main)), findsOneWidget);
    expect(dashed(MealSavedSheetKeys.flag(MealFlag.protein)), findsOneWidget);
    expect(dashed(MealSavedSheetKeys.veg(MealVeg.some)), findsOneWidget);
    expect(find.byType(ActionChip), findsNWidgets(3));
    expect(find.text(l10n.foodAiSuggestedHint), findsOneWidget);
    expect(find.text(l10n.foodAiConfirmAll(3)), findsOneWidget);
    expect(bumps, 0);
    expect(h.container.read(dataRevisionProvider), 0);
    final meal = await stored();
    expect(meal.kind, isNull);
    expect(meal.tags.isEmpty, isTrue);
  });

  testWidgets("the model's unsure never shows the person's Not sure chip", (
    tester,
  ) async {
    await pump(tester);

    final unsure = MealSavedSheetKeys.processed(MealProcessed.unsure);
    expect(dashed(unsure), findsNothing);
    expect(dashed(MealSavedSheetKeys.flag(MealFlag.fried)), findsNothing);
    expect(dashed(MealSavedSheetKeys.flag(MealFlag.heavy)), findsNothing);
  });

  testWidgets('a dashed chip reads as a suggestion to confirm', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    expect(
      find.bySemanticsLabel(l10n.foodAiSuggestedChip(l10n.foodProtein)),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('a tap on one dashed chip saves only that tag once and turns '
      'it solid', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(MealSavedSheetKeys.flag(MealFlag.protein)));
    await tester.pumpAndSettle();

    final meal = await stored();
    expect(bumps, 1);
    expect(meal.tags.protein, isTrue);
    expect(meal.kind, isNull);
    expect(meal.tags.veg, isNull);
    final chip = MealSavedSheetKeys.flag(MealFlag.protein);
    expect(dashed(chip), findsNothing);
    expect(
      tester
          .widget<FilterChip>(
            find.descendant(
              of: find.byKey(chip),
              matching: find.byType(FilterChip),
            ),
          )
          .selected,
      isTrue,
    );
    expect(find.text(l10n.foodAiConfirmAll(2)), findsOneWidget);
  });

  testWidgets('Confirm all saves the 3 pending tags in one update', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(MealAnalysisKeys.confirmAll));
    await tester.pump();
    expect(find.text(l10n.foodAiConfirmed), findsOneWidget);
    await tester.pumpAndSettle();

    final meal = await stored();
    expect(bumps, 1);
    expect(meal.kind, MealKind.main);
    expect(meal.tags.protein, isTrue);
    expect(meal.tags.veg, MealVeg.some);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.byKey(MealAnalysisKeys.confirmAll), findsNothing);
    expect(find.text(l10n.foodAiChecked), findsOneWidget);
  });

  testWidgets('Confirm all keeps the tags the person set before', (
    tester,
  ) async {
    await pump(
      tester,
      tags: const MealEdit()
          .withFlag(MealFlag.caffeine, true)
          .withPlace(MealPlace.home),
    );
    await tester.tap(find.byKey(MealAnalysisKeys.confirmAll));
    await tester.pumpAndSettle();

    final meal = await stored();
    expect(bumps, 1);
    expect(meal.kind, MealKind.main);
    expect(meal.tags.protein, isTrue);
    expect(meal.tags.veg, MealVeg.some);
    expect(meal.tags.caffeine, isTrue);
    expect(meal.tags.place, MealPlace.home);
  });

  testWidgets('a dashed chip keeps the 48 dp tap target', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    expect(dashed(MealSavedSheetKeys.kind(MealKind.main)), findsOneWidget);
    final size = tester.getSize(dashed(MealSavedSheetKeys.kind(MealKind.main)));
    expect(size.height, greaterThanOrEqualTo(kMinInteractiveDimension));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('a group the person set and a flag already on show no dashed '
      'chip', (tester) async {
    await pump(
      tester,
      tags: const MealEdit()
          .withKind(MealKind.snack)
          .withFlag(MealFlag.protein, true),
    );

    expect(dashed(MealSavedSheetKeys.kind(MealKind.main)), findsNothing);
    expect(dashed(MealSavedSheetKeys.flag(MealFlag.protein)), findsNothing);
    expect(dashed(MealSavedSheetKeys.veg(MealVeg.some)), findsOneWidget);
    expect(find.text(l10n.foodAiConfirmAll(1)), findsOneWidget);
  });

  testWidgets('demo mode draws no dashed chip', (tester) async {
    h.demo = true;
    await pump(tester);

    expect(find.byType(ActionChip), findsNothing);
    expect(find.byKey(MealAnalysisKeys.sample), findsOneWidget);
  });

  testWidgets('with AI off the chips are plain and nothing is suggested', (
    tester,
  ) async {
    h.modules = {ModuleId.food};
    await pump(tester);

    expect(find.byType(ActionChip), findsNothing);
    expect(find.text(l10n.foodAiSuggestedHint), findsNothing);
  });

  testWidgets('a meal kept on this phone shows no suggestion', (tester) async {
    await pump(tester, analyzed: false);
    await done(mealId);
    await h.analyses.setKeepOnPhone(mealId, keep: true);
    await tester.pumpAndSettle();

    expect(find.byType(ActionChip), findsNothing);
  });
}
