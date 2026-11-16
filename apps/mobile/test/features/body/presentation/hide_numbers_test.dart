import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/body/domain/weigh_in_store.dart';
import 'package:open_ring/features/body/presentation/body_module_screen.dart';
import 'package:open_ring/features/body/presentation/body_screen.dart';
import 'package:open_ring/features/body/presentation/weigh_in_sheet.dart';
import 'package:open_ring/features/body/presentation/weight_card.dart';
import 'package:open_ring/features/body/presentation/weight_chart.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/modules/presentation/modules_screen.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_screen.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/settings_fakes.dart';

final _weightValue = RegExp(r'\d\d\.\d|kg|lb');

WeighInDraft _draft(
  double kilograms, {
  required int daysAgo,
  double? bodyFat,
  double? waist,
}) => WeighInDraft(
  at: metricsNow.subtract(Duration(days: daysAgo, hours: 1)),
  offsetMinutes: 0,
  kilograms: kilograms,
  bodyFatPercent: bodyFat,
  waistCentimeters: waist,
);

Future<InMemoryWeighInStore> _store(List<WeighInDraft> drafts) async {
  final store = InMemoryWeighInStore();
  for (final draft in drafts) {
    await store.add(draft);
  }
  return store;
}

Future<InMemoryWeighInStore> _falling() => _store([
  for (var age = 19; age >= 0; age--)
    _draft(80 - 0.1 * (19 - age), daysAgo: age),
]);

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  required WeighInStore store,
}) => pumpScaled(
  tester,
  screenHost(screen),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: const Locale('en'),
  overrides: <Override>[
    ...metricsOverrides(fullDataScenario),
    moduleStoreProvider.overrideWithValue(InMemoryModuleStore({ModuleId.body})),
    weighInStoreProvider.overrideWithValue(store),
    hideNumbersStoreProvider.overrideWithValue(
      InMemoryHideNumbersStore(hidden: true),
    ),
  ],
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(WeighInSheetKeys.save));
  await tester.tap(find.byKey(WeighInSheetKeys.save));
  await tester.pumpAndSettle();
}

Finder _input(Key key) =>
    find.descendant(of: find.byKey(key), matching: find.byType(TextField));

String _field(WidgetTester tester, Key key) =>
    tester.widget<TextField>(_input(key)).controller!.text;

String _plain(Text text) => text.data ?? text.textSpan?.toPlainText() ?? '';

Iterable<String> _shown(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map(_plain)
    .where(_weightValue.hasMatch);

void main() {
  group('Body with numbers hidden', () {
    testWidgets('shows the direction and no weight value', (tester) async {
      await _pump(tester, const BodyScreen(), store: await _falling());

      expect(find.text('Numbers hidden. You keep logging.'), findsOneWidget);
      expect(find.text('28 day direction'), findsOneWidget);
      expect(find.text('28 day rate'), findsNothing);
      expect(find.text('Going down'), findsOneWidget);
      expect(
        find.text('The change is larger than the day to day variation.'),
        findsOneWidget,
      );
      expect(find.text('day to day variation'), findsOneWidget);
      expect(find.text('daily weigh-in'), findsNothing);
      expect(
        find.bySemanticsLabel('Weight trend with a band, no values.'),
        findsOneWidget,
      );
      expect(
        tester.widget<WeightChart>(find.byKey(BodyKeys.chart)).band,
        isNotNull,
      );
      await reveal(tester, find.byKey(BodyKeys.entry(20)));
      expect(find.text('logged'), findsWidgets);
      expect(_shown(tester), isEmpty);
    });

    testWidgets('a flat weight reads stable', (tester) async {
      final store = await _store([
        for (var age = 19; age >= 0; age--)
          _draft(age.isEven ? 80 : 80.2, daysAgo: age),
      ]);
      await _pump(tester, const BodyScreen(), store: store);

      expect(find.text('Stable, within the noise'), findsOneWidget);
      expect(
        find.text('Day to day variation is still larger than any change.'),
        findsOneWidget,
      );
      expect(_shown(tester), isEmpty);
    });

    testWidgets('too few weigh-ins still say what is missing', (tester) async {
      final store = await _store([
        _draft(80, daysAgo: 2),
        _draft(79.5, daysAgo: 0),
      ]);
      await _pump(tester, const BodyScreen(), store: store);

      expect(find.text('Not yet'), findsOneWidget);
      expect(_shown(tester), isEmpty);
    });

    for (final (bodyFat, waist, expected) in [
      (18.5, 86.0, 'with body fat and waist'),
      (18.5, null, 'with body fat'),
      (null, 86.0, 'with waist'),
    ]) {
      testWidgets('a row says "$expected" without the values', (tester) async {
        final store = await _store([
          _draft(80, daysAgo: 0, bodyFat: bodyFat, waist: waist),
        ]);
        await _pump(tester, const BodyScreen(), store: store);
        await reveal(tester, find.byKey(BodyKeys.entry(1)));

        expect(find.text(expected), findsOneWidget);
        expect(_shown(tester), isEmpty);
      });
    }

    testWidgets('editing with blank fields keeps every stored value', (
      tester,
    ) async {
      final store = await _store([
        _draft(80, daysAgo: 1, bodyFat: 18.5, waist: 86),
      ]);
      final before = (await store.all()).single;
      await _pump(tester, const BodyScreen(), store: store);
      await _tap(tester, find.byKey(BodyKeys.entry(1)));
      await _tap(tester, find.byKey(BodyKeys.edit));

      expect(_field(tester, WeighInSheetKeys.weight), isEmpty);
      expect(
        find.text('Numbers hidden. Leave a field blank to keep its value.'),
        findsOneWidget,
      );
      expect(_input(WeighInSheetKeys.bodyFat), findsNothing);
      await _save(tester);

      final after = (await store.all()).single;
      expect(after.kilograms, before.kilograms);
      expect(after.bodyFatPercent, before.bodyFatPercent);
      expect(after.waistCentimeters, before.waistCentimeters);
      expect(after.at, before.at);
      expect(find.text('Weigh-in updated.'), findsOneWidget);
    });

    testWidgets('editing with a typed weight changes only the weight', (
      tester,
    ) async {
      final store = await _store([
        _draft(80, daysAgo: 1, bodyFat: 18.5, waist: 86),
      ]);
      await _pump(tester, const BodyScreen(), store: store);
      await _tap(tester, find.byKey(BodyKeys.entry(1)));
      await _tap(tester, find.byKey(BodyKeys.edit));
      await tester.enterText(_input(WeighInSheetKeys.weight), '79.2');
      await _save(tester);

      final after = (await store.all()).single;
      expect(after.kilograms, 79.2);
      expect(after.bodyFatPercent, 18.5);
      expect(after.waistCentimeters, 86);
      expect(_shown(tester), isEmpty);
    });
  });

  group('the Today card with numbers hidden', () {
    testWidgets('shows the direction, the time and no weight value', (
      tester,
    ) async {
      await _pump(tester, const TodayScreen(), store: await _falling());
      await reveal(tester, find.byKey(WeightCardKeys.card));
      final card = find.byKey(WeightCardKeys.card);
      final texts = tester
          .widgetList<Text>(
            find.descendant(of: card, matching: find.byType(Text)),
          )
          .map(_plain)
          .toList();

      expect(texts, contains('numbers hidden'));
      expect(texts, contains('Going down'));
      expect(texts, contains('28 day trend'));
      expect(texts, contains('08:00'));
      expect(texts, isNot(contains('28 day rate')));
      expect(texts.where(_weightValue.hasMatch), isEmpty);
    });

    testWidgets('a new weigh-in opens blank and is saved without echo', (
      tester,
    ) async {
      final store = await _store([_draft(78, daysAgo: 1)]);
      await _pump(tester, const TodayScreen(), store: store);
      await _tap(tester, find.byKey(WeightCardKeys.log));

      expect(_field(tester, WeighInSheetKeys.weight), isEmpty);
      expect(
        find.text('Numbers hidden. The value leaves the screen after saving.'),
        findsOneWidget,
      );
      await _save(tester);
      expect(find.text('Enter the weight to save.'), findsOneWidget);
      expect(await store.count(), 1);

      await tester.enterText(_input(WeighInSheetKeys.weight), '77.4');
      await _save(tester);

      expect((await store.all()).first.kilograms, 77.4);
      expect(find.text('Weigh-in logged.'), findsOneWidget);
      expect(find.textContaining('77.4'), findsNothing);
    });
  });

  testWidgets('the Body detail switch hides and shows the numbers', (
    tester,
  ) async {
    final choice = InMemoryHideNumbersStore();
    await pumpScaled(
      tester,
      const OpenRingApp(),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(),
        ...settingsOverrides(),
        moduleStoreProvider.overrideWithValue(
          InMemoryModuleStore({ModuleId.body}),
        ),
        weighInStoreProvider.overrideWithValue(InMemoryWeighInStore()),
        hideNumbersStoreProvider.overrideWithValue(choice),
      ],
    );
    await tester.tap(find.byKey(AppNavigationBar.destinationKey(AppTab.ring)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RingScreen.settingsKey));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(SettingsScreen.modulesKey));
    await _tap(tester, find.byKey(ModulesKeys.bodyRow));

    await _tap(tester, find.byKey(BodyModuleKeys.hide));

    expect(choice.hidden, isTrue);
    expect(find.text('Numbers hidden on every screen.'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byKey(BodyModuleKeys.hide)).value,
      isTrue,
    );

    await _tap(tester, find.byKey(BodyModuleKeys.hide));

    expect(choice.hidden, isFalse);
    expect(find.text('Numbers visible again.'), findsOneWidget);
  });
  group('the hide numbers choice', () {
    Future<void> pump(WidgetTester tester, Set<ModuleId> modules) => pumpScaled(
      tester,
      screenHost(const BodyModuleScreen()),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      overrides: <Override>[
        ...metricsOverrides(fullDataScenario),
        moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
        weighInStoreProvider.overrideWithValue(InMemoryWeighInStore()),
        hideNumbersStoreProvider.overrideWithValue(InMemoryHideNumbersStore()),
      ],
    );

    String detail(WidgetTester tester) {
      final tile = tester.widget<SwitchListTile>(
        find.byKey(BodyModuleKeys.hide),
      );
      return (tile.subtitle! as CaptionText).text;
    }

    testWidgets('names the energy estimate while Energy is on', (tester) async {
      await pump(tester, {ModuleId.body, ModuleId.energy});
      await reveal(tester, find.byKey(BodyModuleKeys.hide));

      expect(detail(tester), endsWith('The energy estimate is hidden too.'));
    });

    testWidgets('does not name it while Energy is off', (tester) async {
      await pump(tester, {ModuleId.body});
      await reveal(tester, find.byKey(BodyModuleKeys.hide));

      expect(detail(tester), endsWith('no weight value on any screen.'));
    });
  });
}
