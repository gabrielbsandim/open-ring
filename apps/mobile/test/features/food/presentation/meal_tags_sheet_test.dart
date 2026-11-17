import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/presentation/food_row.dart';
import 'package:open_ring/features/food/presentation/meal_saved_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../food_fakes.dart';

final _lunch = DateTime(2026, 11, 17, 12, 30);

Future<ProviderContainer> _pumpRow(
  WidgetTester tester,
  TestMealStore meals, {
  MealCamera? camera,
  PhotoStore? photos,
}) async {
  await pumpScaled(
    tester,
    screenHost(
      const Scaffold(body: SingleChildScrollView(child: FoodRowSlot())),
    ),
    textScaler: TextScaler.noScaling,
    brightness: Brightness.dark,
    locale: const Locale('en'),
    overrides: foodOverrides(
      meals: meals,
      camera: camera ?? FakeMealCamera(photo: returnedPhoto),
      photos: photos,
      clock: () => _lunch,
    ),
  );
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
}

Future<void> _tapCamera(WidgetTester tester) async {
  await tester.tap(find.byKey(FoodRowKeys.camera));
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Future<void> _done(WidgetTester tester) =>
    _tapKey(tester, MealSavedSheetKeys.done);

Finder _inRow(Finder matching) =>
    find.descendant(of: find.byKey(FoodRowKeys.row), matching: matching);

int _revision(ProviderContainer container) =>
    container.read(dataRevisionProvider);

final List<Key> _kindKeys = [
  for (final kind in MealKind.values) MealSavedSheetKeys.kind(kind),
];
final List<Key> _flagKeys = [
  for (final flag in MealFlag.values) MealSavedSheetKeys.flag(flag),
];
final List<Key> _vegKeys = [
  for (final veg in MealVeg.values) MealSavedSheetKeys.veg(veg),
];
final List<Key> _alcoholKeys = [
  for (final alcohol in MealAlcohol.values) MealSavedSheetKeys.alcohol(alcohol),
];
final List<Key> _processedKeys = [
  for (final processed in MealProcessed.values)
    MealSavedSheetKeys.processed(processed),
];
final List<Key> _placeKeys = [
  for (final place in MealPlace.values) MealSavedSheetKeys.place(place),
];

List<Key> get _chipKeys => [
  ..._kindKeys,
  ..._flagKeys,
  ..._vegKeys,
  ..._alcoholKeys,
  ..._processedKeys,
  ..._placeKeys,
];

/// The 10 groups by their label, each with the chips it must hold.
Map<String, List<Key>> _groups(AppLocalizations l10n) => {
  l10n.foodKindLabel: _kindKeys,
  l10n.foodProteinLabel: [MealSavedSheetKeys.flag(MealFlag.protein)],
  l10n.foodVegLabel: _vegKeys,
  l10n.foodAlcoholLabel: _alcoholKeys,
  l10n.foodCaffeineLabel: [MealSavedSheetKeys.flag(MealFlag.caffeine)],
  l10n.foodHeavyLabel: [MealSavedSheetKeys.flag(MealFlag.heavy)],
  l10n.foodFriedLabel: [MealSavedSheetKeys.flag(MealFlag.fried)],
  l10n.foodSugarLabel: [MealSavedSheetKeys.flag(MealFlag.sugar)],
  l10n.foodProcessedLabel: _processedKeys,
  l10n.foodPlaceLabel: _placeKeys,
};

bool _selected(WidgetTester tester, Key key) {
  final chip = find.descendant(
    of: find.byKey(key),
    matching: find.byWidgetPredicate((w) => w is SelectableChipAttributes),
    matchRoot: true,
  );
  return (tester.widget(chip.first) as SelectableChipAttributes).selected;
}

List<Key> _selectedKeys(WidgetTester tester) => [
  for (final key in _chipKeys)
    if (_selected(tester, key)) key,
];

bool _switchOn(WidgetTester tester) => tester
    .widget<Switch>(
      find.descendant(
        of: find.byKey(MealSavedSheetKeys.last),
        matching: find.byType(Switch),
        matchRoot: true,
      ),
    )
    .value;

void main() {
  group('criterion 4: the sheet opens empty', () {
    testWidgets('no chip is selected and the switch is off', (tester) async {
      await _pumpRow(tester, TestMealStore());
      await _tapCamera(tester);

      for (final key in _chipKeys) {
        expect(find.byKey(key), findsOneWidget, reason: '$key');
      }
      expect(_selectedKeys(tester), isEmpty);
      expect(_switchOn(tester), isFalse);
    });

    testWidgets('kind and the 4 one of groups are ChoiceChips, the 5 flags '
        'are FilterChips', (tester) async {
      await _pumpRow(tester, TestMealStore());
      await _tapCamera(tester);

      Finder chip<T extends Widget>(Key key) => find.descendant(
        of: find.byKey(key),
        matching: find.byType(T),
        matchRoot: true,
      );
      for (final key in [
        ..._kindKeys,
        ..._vegKeys,
        ..._alcoholKeys,
        ..._processedKeys,
        ..._placeKeys,
      ]) {
        expect(chip<ChoiceChip>(key), findsOneWidget, reason: '$key');
      }
      for (final key in _flagKeys) {
        expect(chip<FilterChip>(key), findsOneWidget, reason: '$key');
      }
    });

    testWidgets('each of the 10 groups sits in a container Semantics with '
        'its label', (tester) async {
      await _pumpRow(tester, TestMealStore());
      await _tapCamera(tester);
      final groups = _groups(lookupAppLocalizations(const Locale('en')));

      expect(groups, hasLength(10));
      for (final MapEntry(key: label, value: keys) in groups.entries) {
        final group = find.byWidgetPredicate(
          (w) => w is Semantics && w.container && w.properties.label == label,
        );
        expect(group, findsOneWidget, reason: label);
        for (final key in keys) {
          expect(
            find.descendant(of: group, matching: find.byKey(key)),
            findsOneWidget,
            reason: '$label holds $key',
          );
        }
      }
    });
  });

  group('criterion 5: one tap chips', () {
    testWidgets('Snack then Snack leaves kind null and writes nothing', (
      tester,
    ) async {
      final meals = TestMealStore();
      final container = await _pumpRow(tester, meals);
      await _tapCamera(tester);
      final before = _revision(container);
      final snack = MealSavedSheetKeys.kind(MealKind.snack);

      await _tapKey(tester, snack);
      expect(_selectedKeys(tester), [snack]);
      await _tapKey(tester, snack);
      expect(_selectedKeys(tester), isEmpty);
      await _done(tester);

      expect(meals.rows.single.kind, isNull);
      expect(meals.updates, 0);
      expect(_revision(container), before);
    });

    testWidgets('Main then Drink keeps drink alone', (tester) async {
      final meals = TestMealStore();
      final container = await _pumpRow(tester, meals);
      await _tapCamera(tester);
      final before = _revision(container);
      final drink = MealSavedSheetKeys.kind(MealKind.drink);

      await _tapKey(tester, MealSavedSheetKeys.kind(MealKind.main));
      await _tapKey(tester, drink);
      expect(_selectedKeys(tester), [drink]);
      await _done(tester);

      expect(meals.rows.single.kind, MealKind.drink);
      expect(meals.updates, 1);
      expect(_revision(container), before + 1);
    });

    testWidgets('Protein twice is off and writes nothing', (tester) async {
      final meals = TestMealStore();
      await _pumpRow(tester, meals);
      await _tapCamera(tester);
      final protein = MealSavedSheetKeys.flag(MealFlag.protein);

      await _tapKey(tester, protein);
      expect(_selectedKeys(tester), [protein]);
      await _tapKey(tester, protein);
      expect(_selectedKeys(tester), isEmpty);
      await _done(tester);

      expect(meals.rows.single.tags.protein, isFalse);
      expect(meals.updates, 0);
    });

    testWidgets('Some then Half keeps halfOrMore alone', (tester) async {
      final meals = TestMealStore();
      await _pumpRow(tester, meals);
      await _tapCamera(tester);
      final half = MealSavedSheetKeys.veg(MealVeg.halfOrMore);

      await _tapKey(tester, MealSavedSheetKeys.veg(MealVeg.some));
      await _tapKey(tester, half);
      expect(_selectedKeys(tester), [half]);
      await _done(tester);

      expect(meals.rows.single.tags.veg, MealVeg.halfOrMore);
      expect(meals.updates, 1);
    });

    final oneOf = <String, List<Key> Function()>{
      'alcohol': () => _alcoholKeys,
      'processed': () => _processedKeys,
      'place': () => _placeKeys,
    };
    for (final MapEntry(key: name, value: keysOf) in oneOf.entries) {
      testWidgets('$name: tapping the chosen chip clears it, and a second '
          'choice replaces the first', (tester) async {
        await _pumpRow(tester, TestMealStore());
        await _tapCamera(tester);
        final keys = keysOf();

        await _tapKey(tester, keys.first);
        await _tapKey(tester, keys.first);
        expect(_selectedKeys(tester), isEmpty);
        await _tapKey(tester, keys.first);
        await _tapKey(tester, keys.last);
        expect(_selectedKeys(tester), [keys.last]);
      });
    }

    testWidgets('the 5 flags toggle on and off on their own', (tester) async {
      await _pumpRow(tester, TestMealStore());
      await _tapCamera(tester);

      for (final key in _flagKeys) {
        await _tapKey(tester, key);
      }
      expect(_selectedKeys(tester), _flagKeys);
      for (final key in _flagKeys) {
        await _tapKey(tester, key);
      }
      expect(_selectedKeys(tester), isEmpty);
    });

    testWidgets('a choice in one group leaves the others as they were', (
      tester,
    ) async {
      await _pumpRow(tester, TestMealStore());
      await _tapCamera(tester);
      final chosen = [
        MealSavedSheetKeys.kind(MealKind.main),
        MealSavedSheetKeys.flag(MealFlag.fried),
        MealSavedSheetKeys.veg(MealVeg.some),
        MealSavedSheetKeys.alcohol(MealAlcohol.oneToTwo),
        MealSavedSheetKeys.processed(MealProcessed.unsure),
        MealSavedSheetKeys.place(MealPlace.restaurant),
      ];

      for (final key in chosen) {
        await _tapKey(tester, key);
      }

      expect(_selectedKeys(tester).toSet(), chosen.toSet());
      expect(_switchOn(tester), isFalse);
    });
  });

  group('criterion 6: the row reads the kind and tags', () {
    testWidgets('Drink then Done shows "1 today" with no window', (
      tester,
    ) async {
      final meals = TestMealStore();
      await _pumpRow(tester, meals);
      await _tapCamera(tester);

      await _tapKey(tester, MealSavedSheetKeys.kind(MealKind.drink));
      await _done(tester);

      expect(_inRow(find.text('1 today')), findsOneWidget);
      expect(_inRow(find.textContaining('window')), findsNothing);
      expect(_inRow(find.textContaining('12:30')), findsNothing);
    });

    testWidgets('Drink with sugar shows "window since 12:30"', (tester) async {
      final meals = TestMealStore();
      await _pumpRow(tester, meals);
      await _tapCamera(tester);

      await _tapKey(tester, MealSavedSheetKeys.kind(MealKind.drink));
      await _tapKey(tester, MealSavedSheetKeys.flag(MealFlag.sugar));
      await _done(tester);

      expect(_inRow(find.textContaining('1 today')), findsOneWidget);
      expect(_inRow(find.textContaining('window since 12:30')), findsOneWidget);
    });

    testWidgets('review focus: a plain drink marked last counts, opens no '
        'window and stores last', (tester) async {
      final meals = TestMealStore();
      final container = await _pumpRow(tester, meals);
      await _tapCamera(tester);
      final before = _revision(container);

      await _tapKey(tester, MealSavedSheetKeys.kind(MealKind.drink));
      await _tapKey(tester, MealSavedSheetKeys.last);
      await _done(tester);

      final row = meals.rows.single;
      expect(row.kind, MealKind.drink);
      expect(row.last, isTrue);
      expect(meals.updates, 1);
      expect(_revision(container), before + 1);
      expect(_inRow(find.text('1 today')), findsOneWidget);
      expect(_inRow(find.textContaining('window')), findsNothing);
    });
  });

  group('criterion 7: back with no Done', () {
    testWidgets('writes the edit in one update and bumps once', (tester) async {
      final meals = TestMealStore();
      final container = await _pumpRow(tester, meals);
      await _tapCamera(tester);
      final before = _revision(container);
      final photo = meals.rows.single.photo;

      await _tapKey(tester, MealSavedSheetKeys.kind(MealKind.main));
      await _tapKey(tester, MealSavedSheetKeys.veg(MealVeg.some));
      await _tapKey(tester, MealSavedSheetKeys.flag(MealFlag.protein));
      await _tapKey(tester, MealSavedSheetKeys.place(MealPlace.home));
      await _back(tester);

      final row = meals.rows.single;
      expect(find.byType(MealSavedSheet), findsNothing);
      expect(row.kind, MealKind.main);
      expect(row.tags.veg, MealVeg.some);
      expect(row.tags.protein, isTrue);
      expect(row.tags.place, MealPlace.home);
      expect(row.last, isFalse);
      expect(row.photo, photo);
      expect(meals.updates, 1);
      expect(_revision(container), before + 1);
    });

    testWidgets('back with the switch and a tag writes both in one update', (
      tester,
    ) async {
      final meals = TestMealStore();
      await _pumpRow(tester, meals);
      await _tapCamera(tester);

      await _tapKey(tester, MealSavedSheetKeys.flag(MealFlag.caffeine));
      await _tapKey(tester, MealSavedSheetKeys.last);
      await _back(tester);

      expect(meals.rows.single.tags.caffeine, isTrue);
      expect(meals.rows.single.last, isTrue);
      expect(meals.updates, 1);
    });
  });

  group('review focus: a failed update', () {
    testWidgets('a throwing update shows "Could not save the tags"', (
      tester,
    ) async {
      final meals = TestMealStore();
      final container = await _pumpRow(tester, meals);
      await _tapCamera(tester);
      final before = _revision(container);

      await _tapKey(tester, MealSavedSheetKeys.kind(MealKind.main));
      meals.updateError = Exception('disk I/O error');
      await _done(tester);

      expect(find.byType(MealSavedSheet), findsNothing);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Could not save the tags'),
        ),
        findsOneWidget,
      );
      expect(meals.updates, 1);
      expect(meals.rows.single.kind, isNull);
      expect(_revision(container), before);
    });

    testWidgets('a written edit shows no message', (tester) async {
      final meals = TestMealStore();
      await _pumpRow(tester, meals);
      await _tapCamera(tester);

      await _tapKey(tester, MealSavedSheetKeys.kind(MealKind.main));
      await _done(tester);

      expect(find.byType(SnackBar), findsNothing);
      expect(meals.rows.single.kind, MealKind.main);
    });
  });

  group('D5: a meal saved without a photo shows no tags', () {
    late TestMealStore meals;

    setUp(() => meals = TestMealStore());

    Future<void> openNoSpace(WidgetTester tester) async {
      await _pumpRow(tester, meals, photos: FullPhotoStore());
      await _tapCamera(tester);
      expect(find.byType(MealNoSpaceSheet), findsOneWidget);
      expect(find.byKey(MealSavedSheetKeys.kind(MealKind.main)), findsNothing);
    }

    final closes = <String, Future<void> Function(WidgetTester)>{
      'Without photo': (tester) =>
          _tapKey(tester, MealSavedSheetKeys.withoutPhoto),
      'back on the no space sheet': _back,
    };
    for (final MapEntry(key: name, value: close) in closes.entries) {
      testWidgets('$name opens no tag chips and writes nothing', (
        tester,
      ) async {
        await openNoSpace(tester);

        await close(tester);

        expect(find.byType(MealNoSpaceSheet), findsNothing);
        expect(find.byType(MealSavedSheet), findsNothing);
        for (final key in _chipKeys) {
          expect(find.byKey(key), findsNothing, reason: '$key');
        }
        expect(meals.rows.single.photo, isNull);
        expect(meals.updates, 0);
      });
    }

    testWidgets('a camera error shows no tag chips', (tester) async {
      await _pumpRow(tester, meals, camera: ThrowingMealCamera());

      await tester.tap(find.byKey(FoodRowKeys.camera));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      expect(find.byType(SnackBar), findsOneWidget);
      for (final key in _chipKeys) {
        expect(find.byKey(key), findsNothing, reason: '$key');
      }
      expect(meals.rows, isEmpty);
      expect(meals.updates, 0);
    });
  });

  group('review focus: a retry that attached a photo, then the edit', () {
    testWidgets('Retry opens the saved sheet, and its tags land on the row '
        'with the photo', (tester) async {
      final meals = TestMealStore();
      final full = FullPhotoStore();
      await _pumpRow(tester, meals, photos: full);
      await _tapCamera(tester);
      full.full = false;

      await _tapKey(tester, MealSavedSheetKeys.retry);
      expect(find.byType(MealSavedSheet), findsOneWidget);
      expect(_selectedKeys(tester), isEmpty);
      final photo = meals.rows.single.photo;
      expect(photo, isNotNull);

      await _tapKey(tester, MealSavedSheetKeys.kind(MealKind.snack));
      await _tapKey(tester, MealSavedSheetKeys.flag(MealFlag.sugar));
      await _done(tester);

      final row = meals.rows.single;
      expect(row.kind, MealKind.snack);
      expect(row.tags.sugar, isTrue);
      expect(row.photo, photo);
      expect(await full.inner.read(photo!), isNotNull);
      expect(meals.updates, 1);
    });
  });
}
