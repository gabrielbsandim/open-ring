import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
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
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/settings_fakes.dart';

WeighInDraft _draft(
  double kilograms, {
  required int daysAgo,
  double? bodyFat,
  double? waist,
  int offsetMinutes = 0,
}) => WeighInDraft(
  at: metricsNow.subtract(Duration(days: daysAgo, hours: 1)),
  offsetMinutes: offsetMinutes,
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

Future<InMemoryWeighInStore> _twentyDays({double perDay = 0}) => _store([
  for (var age = 19; age >= 0; age--)
    _draft(80 + perDay * (19 - age), daysAgo: age),
]);

Future<void> _pump(
  WidgetTester tester, {
  required WeighInStore store,
  UnitSystem units = UnitSystem.metric,
}) => pumpScaled(
  tester,
  screenHost(const BodyScreen()),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: const Locale('en'),
  overrides: <Override>[
    ...metricsOverrides(fullDataScenario),
    moduleStoreProvider.overrideWithValue(InMemoryModuleStore({ModuleId.body})),
    weighInStoreProvider.overrideWithValue(store),
    unitSystemStoreProvider.overrideWithValue(InMemoryUnitSystemStore(units)),
  ],
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

String _field(WidgetTester tester, Key key) => tester
    .widget<TextField>(
      find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
    )
    .controller!
    .text;

String _caption(WidgetTester tester, Key key) => tester
    .widget<Text>(
      find.descendant(of: find.byKey(key), matching: find.byType(Text)),
    )
    .data!;

void main() {
  group('weightAxis', () {
    test('a spread of about a kilogram gets half kilogram lines', () {
      expect(weightAxis([79.2, 80.4]), (low: 79.0, high: 81.0, step: 0.5));
    });

    test('a single value still gets a band around it', () {
      final axis = weightAxis([80]);

      expect(axis.low, lessThan(80));
      expect(axis.high, greaterThan(80));
    });

    test('a wide spread never draws more than five lines', () {
      final axis = weightAxis([60, 110]);

      expect((axis.high - axis.low) / axis.step, lessThanOrEqualTo(5));
    });
  });

  group('weightRangeStart', () {
    const today = LocalDate(2026, 11, 10);

    test('30 days ends today and starts 29 days back', () {
      expect(
        weightRangeStart(
          WeightRange.month,
          today: today,
          first: const LocalDate(2026, 1, 1),
        ),
        const LocalDate(2026, 10, 12),
      );
    });

    test('all starts at the first weigh-in', () {
      expect(
        weightRangeStart(
          WeightRange.all,
          today: today,
          first: const LocalDate(2026, 1, 1),
        ),
        const LocalDate(2026, 1, 1),
      );
    });

    test('all never shows less than a week', () {
      expect(
        weightRangeStart(WeightRange.all, today: today, first: today),
        const LocalDate(2026, 11, 4),
      );
    });
  });

  testWidgets('with no weigh-ins it explains and offers the first one', (
    tester,
  ) async {
    await _pump(tester, store: InMemoryWeighInStore());

    expect(find.text('No weigh-ins yet'), findsOneWidget);
    expect(find.byKey(BodyKeys.chart), findsNothing);
    await _tap(tester, find.byKey(BodyKeys.log));

    expect(find.byType(WeighInSheet), findsOneWidget);
  });

  testWidgets('three weigh-ins show the trend and what the rate still needs', (
    tester,
  ) async {
    final store = await _store([
      _draft(80, daysAgo: 2),
      _draft(80.4, daysAgo: 1),
      _draft(80.2, daysAgo: 0),
    ]);
    await _pump(tester, store: store);

    expect(find.text('80.2'), findsOneWidget);
    expect(find.byKey(BodyKeys.chart), findsOneWidget);
    expect(_text(tester, BodyKeys.rate), 'Not yet');
    expect(
      _caption(tester, BodyKeys.rateWhy),
      'It takes weigh-ins on 8 different days, spread over 14 days or more. '
      'Days with a weigh-in still missing: 5. '
      'Days still missing between the first and the last: 12.',
    );
  });

  testWidgets('a steady fall shows the weekly rate and its interval', (
    tester,
  ) async {
    await _pump(tester, store: await _twentyDays(perDay: -0.1));

    expect(_text(tester, BodyKeys.rate), '−0.70 kg/week');
    expect(
      _caption(tester, BodyKeys.rateWhy),
      '95% interval: from −0.70 to −0.70 kg per week.',
    );
  });

  testWidgets('a flat weight reads stable, with the interval around zero', (
    tester,
  ) async {
    await _pump(tester, store: await _twentyDays());

    expect(_text(tester, BodyKeys.rate), 'Stable, within the noise');
    expect(
      _caption(tester, BodyKeys.rateWhy),
      'The 95% interval goes from 0.00 to 0.00 kg per week and includes zero.',
    );
  });

  testWidgets('in imperial units the rate is in pounds', (tester) async {
    await _pump(
      tester,
      store: await _twentyDays(perDay: -0.1),
      units: UnitSystem.imperial,
    );

    expect(_text(tester, BodyKeys.rate), '−1.54 lb/week');
  });

  testWidgets('a range with no weigh-in says so, and All brings them back', (
    tester,
  ) async {
    final store = await _store([
      _draft(80, daysAgo: 50),
      _draft(80.4, daysAgo: 45),
    ]);
    await _pump(tester, store: store);

    expect(find.text('No weigh-ins in this period.'), findsOneWidget);
    await _tap(tester, find.text('All'));

    expect(find.text('No weigh-ins in this period.'), findsNothing);
    expect(find.byKey(BodyKeys.chart), findsOneWidget);
  });

  testWidgets('the list starts with eight and shows the rest on demand', (
    tester,
  ) async {
    await _pump(tester, store: await _twentyDays());

    await reveal(tester, find.byKey(BodyKeys.showMore));

    expect(find.text('Show 12 more'), findsOneWidget);
    expect(find.byKey(BodyKeys.entry(13)), findsOneWidget);
    expect(find.byKey(BodyKeys.entry(12)), findsNothing);
    await _tap(tester, find.byKey(BodyKeys.showMore));
    await reveal(tester, find.byKey(BodyKeys.entry(1)));

    expect(find.byKey(BodyKeys.showMore), findsNothing);
    expect(find.byKey(BodyKeys.entry(1)), findsOneWidget);
  });

  testWidgets('a row shows body fat and waist when they were logged', (
    tester,
  ) async {
    final store = await _store([
      _draft(80, daysAgo: 0, bodyFat: 18.5, waist: 86),
    ]);
    await _pump(tester, store: store);
    await reveal(tester, find.byKey(BodyKeys.entry(1)));

    expect(find.text('body fat 18.5% · waist 86.0 cm'), findsOneWidget);
  });

  testWidgets('deleting a weigh-in removes it and Undo brings it back', (
    tester,
  ) async {
    final store = await _store([
      _draft(80, daysAgo: 1),
      _draft(81, daysAgo: 0, bodyFat: 18.5),
    ]);
    await _pump(tester, store: store);
    await _tap(tester, find.byKey(BodyKeys.entry(2)));
    await _tap(tester, find.byKey(BodyKeys.delete));

    expect([for (final entry in await store.all()) entry.kilograms], [80.0]);
    expect(find.text('Weigh-in deleted.'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final restored = (await store.all()).first;
    expect(restored.kilograms, 81);
    expect(restored.bodyFatPercent, 18.5);
    expect(restored.at, metricsNow.subtract(const Duration(hours: 1)));
  });

  testWidgets('editing changes that weigh-in and keeps its time and offset', (
    tester,
  ) async {
    final store = await _store([
      _draft(80, daysAgo: 3, offsetMinutes: -180, waist: 86),
      _draft(82, daysAgo: 0),
    ]);
    final before = (await store.all()).last;
    await _pump(tester, store: store);
    await _tap(tester, find.byKey(BodyKeys.entry(1)));
    await _tap(tester, find.byKey(BodyKeys.edit));

    expect(find.text('Edit weigh-in'), findsOneWidget);
    expect(_field(tester, WeighInSheetKeys.weight), '80.0');
    expect(_field(tester, WeighInSheetKeys.waist), '86.0');
    await tester.tap(find.byKey(WeighInSheetKeys.increase));
    await tester.pump();
    await tester.ensureVisible(find.byKey(WeighInSheetKeys.save));
    await tester.tap(find.byKey(WeighInSheetKeys.save));
    await tester.pumpAndSettle();

    final after = (await store.all()).last;
    expect(await store.count(), 2);
    expect(after.id, before.id);
    expect(after.kilograms, 80.1);
    expect(after.at, before.at);
    expect(after.offsetMinutes, -180);
    expect(after.waistCentimeters, 86);
    expect(find.text('Weigh-in updated: 80.1 kg.'), findsOneWidget);
  });

  testWidgets('the Today card opens Body, and Body opens its module page', (
    tester,
  ) async {
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
      ],
    );
    await reveal(tester, find.byKey(WeightCardKeys.card));
    await tester.tapAt(
      tester.getTopLeft(find.byKey(WeightCardKeys.card)) + const Offset(24, 20),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BodyScreen), findsOneWidget);
    await tester.tap(find.byKey(BodyKeys.settings));
    await tester.pumpAndSettle();

    expect(find.byType(BodyModuleScreen), findsOneWidget);
    expect(
      find.text('The Body screen: chart, 28 day rate and history.'),
      findsOneWidget,
    );
  });
}
