import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart' show FoodGroup;
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/ai/domain/meal_photo_result.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/presentation/meal_analysis_section.dart';
import 'package:open_ring/features/food/presentation/meal_items_card.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../application/meal_analysis_harness.dart';

const _items = [
  MealPhotoItem(
    name: 'Rice',
    measure: MealPhotoMeasure.servingSpoon,
    countX2: 3,
    grams: 135,
  ),
  MealPhotoItem(
    name: 'Beans',
    measure: MealPhotoMeasure.ladle,
    countX2: 2,
    grams: 80,
  ),
  MealPhotoItem(
    name: 'Chicken',
    measure: MealPhotoMeasure.fillet,
    countX2: 1,
    grams: 50,
  ),
  MealPhotoItem(
    name: 'Salad',
    measure: MealPhotoMeasure.tongs,
    countX2: 4,
    grams: 30,
  ),
];

const _suggestion = MealPhotoSuggestion(
  isFood: MealPhotoFlag.yes,
  kind: MealPhotoKind.main,
  protein: MealPhotoFlag.yes,
  caffeine: MealPhotoFlag.no,
  fried: MealPhotoFlag.no,
  sugaryDrink: MealPhotoFlag.no,
  veg: MealPhotoVeg.some,
  alcohol: MealPhotoAlcohol.none,
  processed: MealPhotoProcessed.notMostly,
  items: _items,
);

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  late MealQueueHarness h;
  late int mealId;
  late int rowId;

  setUp(() {
    h = MealQueueHarness();
    h.onAnalysisWrite = () =>
        h.container.read(mealAnalysisRevisionProvider.notifier).bump();
  });

  Future<void> pump(
    WidgetTester tester, {
    bool gate = true,
    Locale locale = const Locale('en'),
    MealPhotoSuggestion suggestion = _suggestion,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 2400);
    addTearDown(tester.view.reset);
    if (gate) {
      h.extraOverrides = [
        mealPhotoItemsEnabledProvider.overrideWithValue(true),
      ];
    }
    await h.start();
    mealId = await h.meal();
    rowId = await h.queued(mealId);
    await h.analyses.markSending(rowId, now: h.now);
    await h.analyses.complete(rowId, (
      status: MealAnalysisStatus.done,
      sent: (sha256: 'abc', width: 768, height: 576, bytes: 4100),
      suggestion: suggestion,
      confidence: MealPhotoConfidence.medium,
      rawText: '{}',
      usage: null,
      cost: null,
      errorKind: null,
    ), now: h.now);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: ListView(children: [MealAnalysisSection(mealId: mealId)]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<MealAnalysisItem> item(String name) async =>
      (await h.row(mealId)).items.singleWhere((i) => i.name == name);

  testWidgets('the default gate renders no item and no hidden chip, even for '
      'a row with items', (tester) async {
    await pump(tester, gate: false);

    expect(find.byKey(MealAnalysisKeys.section), findsOneWidget);
    expect((await h.row(mealId)).items, hasLength(4));
    expect(find.byKey(MealItemsKeys.card), findsNothing);
    expect(find.text('Rice'), findsNothing);
    expect(find.text(en.foodAiHiddenOil), findsNothing);
    expect(find.text(en.foodAiItemsNote), findsNothing);
  });

  testWidgets('with the gate on, a done row with no items shows no card', (
    tester,
  ) async {
    await pump(tester, suggestion: _suggestion.withItems(const []));

    expect(find.byKey(MealAnalysisKeys.section), findsOneWidget);
    expect(find.byKey(MealItemsKeys.card), findsNothing);
    expect(find.text(en.foodAiHiddenOil), findsNothing);
  });

  testWidgets('two quick taps on plus both land', (tester) async {
    await pump(tester);
    final rice = await item('Rice');

    await tester.tap(find.byKey(MealItemsKeys.more(rice.id)));
    await tester.tap(find.byKey(MealItemsKeys.more(rice.id)));
    await tester.pumpAndSettle();

    final stepped = await item('Rice');
    expect((stepped.countX2, stepped.grams), (5, 225));
    expect(find.text('2.5 × serving spoon, about 225 g'), findsOneWidget);
  });

  testWidgets('a failed step shows the stored count and the next step still '
      'lands', (tester) async {
    await pump(tester);
    final rice = await item('Rice');
    final more = find.byKey(MealItemsKeys.more(rice.id));
    h.analyses.failNextItemCount = StateError('disk full');

    await tester.tap(more);
    await tester.pumpAndSettle();

    expect((await item('Rice')).countX2, 3);
    expect(find.text('1.5 × serving spoon, about 135 g'), findsOneWidget);

    await tester.tap(more);
    await tester.pumpAndSettle();

    expect((await item('Rice')).countX2, 4);
    expect(find.text('2 × serving spoon, about 180 g'), findsOneWidget);
  });

  testWidgets('steps queued before the screen closes all land', (tester) async {
    await pump(tester);
    final rice = await item('Rice');
    final gate = h.analyses.itemCountGate = Completer<void>();

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(MealItemsKeys.more(rice.id)));
    }
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }

    expect((await item('Rice')).countX2, 6);
  });

  testWidgets('plus is disabled at 6', (tester) async {
    await pump(tester);
    final rice = await item('Rice');
    final more = find.byKey(MealItemsKeys.more(rice.id));

    for (var i = 0; i < 9; i++) {
      await tester.tap(more);
      await tester.pumpAndSettle();
    }

    expect((await item('Rice')).countX2, 12);
    expect(tester.widget<IconButton>(more).onPressed, isNull);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect((await item('Rice')).countX2, 12);
  });

  testWidgets('the 4 items render with locale formatted halves', (
    tester,
  ) async {
    await pump(tester, locale: const Locale('pt'));

    expect(find.byKey(MealItemsKeys.card), findsOneWidget);
    for (final name in ['Rice', 'Beans', 'Chicken', 'Salad']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('1,5 × colher de servir, cerca de 135 g'), findsOneWidget);
    expect(find.text('0,5 × filé, cerca de 50 g'), findsOneWidget);
    expect(find.text('2 × pegador, cerca de 30 g'), findsOneWidget);
  });

  testWidgets('minus from a half removes the item and shows Removed', (
    tester,
  ) async {
    await pump(tester);
    final chicken = await item('Chicken');

    await tester.tap(find.byKey(MealItemsKeys.less(chicken.id)));
    await tester.pumpAndSettle();

    expect(find.text(en.foodAiItemRemoved), findsOneWidget);
    expect(find.text('Chicken'), findsOneWidget);
    expect((await h.row(mealId)).items.map((i) => i.name), [
      'Rice',
      'Beans',
      'Salad',
    ]);
    final less = tester.widget<IconButton>(
      find.byKey(MealItemsKeys.less(chicken.id)),
    );
    expect(less.onPressed, isNull);
  });

  testWidgets('plus writes one more half, scales grams and confirms', (
    tester,
  ) async {
    await pump(tester);
    final rice = await item('Rice');

    await tester.tap(find.byKey(MealItemsKeys.more(rice.id)));
    await tester.pumpAndSettle();

    final stepped = await item('Rice');
    expect((stepped.countX2, stepped.grams, stepped.confirmed), (4, 180, true));
    expect(find.text('2 × serving spoon, about 180 g'), findsOneWidget);
  });

  testWidgets('hidden chips toggle the three columns, survive again and touch '
      'no meal data', (tester) async {
    await pump(tester);
    final meal = await h.meals.byId(mealId);

    for (final chip in MealHiddenChip.values) {
      await tester.tap(find.byKey(MealItemsKeys.hidden(chip)));
      await tester.pumpAndSettle();
    }
    var row = await h.row(mealId);
    expect(
      (row.hiddenOil, row.hiddenSauce, row.hiddenSugar),
      (true, true, true),
    );
    final sauce = tester.widget<FilterChip>(
      find.byKey(MealItemsKeys.hidden(MealHiddenChip.sauce)),
    );
    expect(sauce.selected, isTrue);

    await tester.tap(find.byKey(MealItemsKeys.hidden(MealHiddenChip.sauce)));
    await tester.pumpAndSettle();
    row = await h.row(mealId);
    expect(
      (row.hiddenOil, row.hiddenSauce, row.hiddenSugar),
      (true, false, true),
    );

    final again = await h.analyses.enqueue(
      mealId,
      row.photoName,
      photoTarget,
      now: h.now,
      again: true,
    );
    expect(
      (again.hiddenOil, again.hiddenSauce, again.hiddenSugar),
      (true, false, true),
    );
    expect(h.container.read(dataRevisionProvider), 0);
    expect(await h.meals.byId(mealId), meal);
  });

  testWidgets('the card holds no kcal, energy or calorie number', (
    tester,
  ) async {
    await pump(tester);

    final texts = [
      for (final text in tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(MealItemsKeys.card),
          matching: find.byType(Text),
        ),
      ))
        text.data ?? '',
    ];
    expect(texts, contains(en.foodAiItemsNote));
    final energy = RegExp('kcal|kJ|calor|energ', caseSensitive: false);
    for (final text in texts) {
      expect(
        text.contains(energy) && text.contains(RegExp(r'\d')),
        isFalse,
        reason: text,
      );
      expect(text.toLowerCase(), isNot(contains('kcal')), reason: text);
    }
  });

  testWidgets('steppers and chips keep 48 dp tap targets', (tester) async {
    await pump(tester);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });

  group('A13b: Confirm', () {
    Future<List<bool>> confirmed() async => [
      for (final i in (await h.row(mealId)).items) i.confirmed,
    ];

    testWidgets('the check line and the button show while an item is '
        'unconfirmed; Confirm confirms all and shows Done', (tester) async {
      await pump(tester);
      expect(find.text(en.foodAiItemsCheck), findsOneWidget);
      expect(find.text(en.foodAiItemsDone), findsNothing);

      await tester.ensureVisible(find.byKey(MealItemsKeys.confirm));
      await tester.tap(find.byKey(MealItemsKeys.confirm));
      await tester.pumpAndSettle();

      expect(await confirmed(), [true, true, true, true]);
      expect(find.byKey(MealItemsKeys.confirm), findsNothing);
      expect(find.text(en.foodAiItemsCheck), findsNothing);
      expect(find.text(en.foodAiItemsDone), findsOneWidget);
      expect(h.container.read(dataRevisionProvider), 0);
    });

    testWidgets('a step confirms one item and the button stays for the '
        'rest', (tester) async {
      await pump(tester);
      final rice = await item('Rice');

      await tester.tap(find.byKey(MealItemsKeys.more(rice.id)));
      await tester.pumpAndSettle();

      expect(await confirmed(), [true, false, false, false]);
      expect(find.byKey(MealItemsKeys.confirm), findsOneWidget);
      expect(find.text(en.foodAiItemsDone), findsNothing);
    });

    testWidgets('Confirm waits for a pending step to land', (tester) async {
      await pump(tester);
      final rice = await item('Rice');
      final gate = Completer<void>();
      h.analyses.itemCountGate = gate;

      await tester.tap(find.byKey(MealItemsKeys.more(rice.id)));
      await tester.pump();
      await tester.ensureVisible(find.byKey(MealItemsKeys.confirm));
      await tester.tap(find.byKey(MealItemsKeys.confirm));
      await tester.pump();

      expect(h.analyses.confirmCalls, 0);
      expect(await confirmed(), everyElement(isFalse));

      gate.complete();
      await tester.pumpAndSettle();

      expect(h.analyses.confirmCalls, 1);
      expect((await item('Rice')).countX2, 4);
      expect(await confirmed(), [true, true, true, true]);
    });

    testWidgets('a failed Confirm leaves the button and shows no '
        'snackbar', (tester) async {
      await pump(tester);
      h.analyses.failNextConfirm = StateError('disk full');

      await tester.ensureVisible(find.byKey(MealItemsKeys.confirm));
      await tester.tap(find.byKey(MealItemsKeys.confirm));
      await tester.pumpAndSettle();

      expect(await confirmed(), everyElement(isFalse));
      expect(find.byKey(MealItemsKeys.confirm), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      await tester.tap(find.byKey(MealItemsKeys.confirm));
      await tester.pumpAndSettle();

      expect(find.text(en.foodAiItemsDone), findsOneWidget);
    });
  });

  testWidgets('end to end: opt in, enqueue, the model returns grouped '
      'items, the card shows them, Confirm confirms all', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 2400);
    addTearDown(tester.view.reset);
    await h.eligible();
    h.respond = () => completed(itemsAnswer());
    final id = await tester.runAsync(() async {
      final meal = await h.meal();
      expect(await h.optIn(), isTrue);
      await h.queue.enqueue(meal);
      await h.queue.drain();
      return meal;
    });
    final row = await h.row(id!);
    expect(row.target.outputSchema, 3);
    expect(row.items.map((i) => (i.name, i.group)), [
      ('rice', FoodGroup.grainCooked),
      ('chicken', FoodGroup.poultry),
    ]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
          theme: AppTheme.light(),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: ListView(children: [MealAnalysisSection(mealId: id)]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(MealItemsKeys.card), findsOneWidget);
    expect(find.text('rice'), findsOneWidget);
    expect(find.text('chicken'), findsOneWidget);
    await tester.ensureVisible(find.byKey(MealItemsKeys.confirm));
    await tester.tap(find.byKey(MealItemsKeys.confirm));
    await tester.pumpAndSettle();

    expect((await h.row(id)).items.map((i) => i.confirmed), [true, true]);
    expect(find.text(en.foodAiItemsDone), findsOneWidget);
  });
}
