import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/body/domain/weigh_in_store.dart';
import 'package:open_ring/features/body/presentation/weigh_in_sheet.dart';
import 'package:open_ring/features/body/presentation/weight_card.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/settings_fakes.dart';

const _neverSynced = MetricsScenario(
  nights: 0,
  activityDays: 0,
  ring: RingStatus(paired: true, name: 'R09_C0FE', model: 'R09'),
);

WeighInDraft _draft(double kilograms, Duration ago) => WeighInDraft(
  at: metricsNow.subtract(ago),
  offsetMinutes: 0,
  kilograms: kilograms,
);

Future<InMemoryWeighInStore> _store(List<WeighInDraft> drafts) async {
  final store = InMemoryWeighInStore();
  for (final draft in drafts) {
    await store.add(draft);
  }
  return store;
}

Future<void> _pump(
  WidgetTester tester, {
  required WeighInStore store,
  MetricsScenario? scenario,
  Set<ModuleId> modules = const {ModuleId.body},
  UnitSystem units = UnitSystem.metric,
}) => pumpScaled(
  tester,
  screenHost(const TodayScreen()),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: const Locale('en'),
  overrides: <Override>[
    ...metricsOverrides(scenario ?? fullDataScenario),
    moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
    weighInStoreProvider.overrideWithValue(store),
    unitSystemStoreProvider.overrideWithValue(InMemoryUnitSystemStore(units)),
  ],
);

Future<void> _openSheet(WidgetTester tester) async {
  await reveal(tester, find.byKey(WeightCardKeys.log));
  await tester.tap(find.byKey(WeightCardKeys.log));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(WeighInSheetKeys.save));
  await tester.tap(find.byKey(WeighInSheetKeys.save));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with Body off Today has no weight card', (tester) async {
    await _pump(tester, store: InMemoryWeighInStore(), modules: const {});

    expect(find.byKey(WeightCardKeys.card), findsNothing);
  });

  final states = {
    'without a ring': noDataScenario,
    'before the first sync': _neverSynced,
    'with fresh data': fullDataScenario,
    'with stale data': offlineScenario,
  };
  for (final MapEntry(key: name, value: scenario) in states.entries) {
    testWidgets('with Body on the weight card shows $name', (tester) async {
      await _pump(tester, store: InMemoryWeighInStore(), scenario: scenario);
      await reveal(tester, find.byKey(WeightCardKeys.card));

      expect(find.byKey(WeightCardKeys.card), findsOneWidget);
      expect(find.text('Log first weigh-in'), findsOneWidget);
      expect(find.textContaining('No weigh-ins yet'), findsOneWidget);
    });
  }

  testWidgets('the card shows trend, last weigh-in and rate', (tester) async {
    final store = await _store([
      _draft(80, const Duration(days: 1)),
      _draft(78, const Duration(hours: 1)),
    ]);
    await _pump(tester, store: store);
    await reveal(tester, find.byKey(WeightCardKeys.card));

    expect(find.text('78.9'), findsOneWidget);
    expect(find.text('78.0 kg · 08:00'), findsOneWidget);
    expect(find.text('not yet'), findsOneWidget);
    expect(find.text('Log weight'), findsOneWidget);
  });

  testWidgets('in imperial units the card shows pounds', (tester) async {
    final store = await _store([_draft(100, const Duration(hours: 1))]);
    await _pump(tester, store: store, units: UnitSystem.imperial);
    await reveal(tester, find.byKey(WeightCardKeys.card));

    expect(find.text('220.5'), findsOneWidget);
    expect(find.text('220.5 lb · 08:00'), findsOneWidget);
  });

  group('the sheet', () {
    testWidgets('starts at the last weight and saves one step up', (
      tester,
    ) async {
      final store = await _store([_draft(78, const Duration(days: 1))]);
      await _pump(tester, store: store);
      await _openSheet(tester);

      expect(find.widgetWithText(TextField, '78.0'), findsOneWidget);
      await tester.tap(find.byKey(WeighInSheetKeys.increase));
      await tester.pump();
      await _save(tester);

      final saved = await store.all();
      expect(saved, hasLength(2));
      expect(saved.first.kilograms, 78.1);
      expect(saved.first.at, metricsNow);
      expect(find.byKey(WeighInSheetKeys.save), findsNothing);
      expect(find.text('78.1 kg · 09:00'), findsOneWidget);
    });

    testWidgets('with no weight it says so and saves nothing', (tester) async {
      final store = InMemoryWeighInStore();
      await _pump(tester, store: store);
      await _openSheet(tester);
      await _save(tester);

      expect(find.text('Enter the weight to save.'), findsOneWidget);
      expect(await store.count(), 0);
    });

    testWidgets('a weight out of range names the range', (tester) async {
      final store = InMemoryWeighInStore();
      await _pump(tester, store: store);
      await _openSheet(tester);
      await tester.enterText(find.byKey(WeighInSheetKeys.weight), '500');
      await _save(tester);

      expect(find.text('Enter a weight from 20 to 300 kg.'), findsOneWidget);
      expect(await store.count(), 0);
    });

    testWidgets('a comma decimal typed in pounds is stored in kilograms', (
      tester,
    ) async {
      final store = InMemoryWeighInStore();
      await _pump(tester, store: store, units: UnitSystem.imperial);
      await _openSheet(tester);
      await tester.enterText(find.byKey(WeighInSheetKeys.weight), '220,5');
      await _save(tester);

      expect((await store.all()).single.kilograms, 100.02);
    });

    testWidgets('pounds out of range name the range in pounds', (tester) async {
      final store = InMemoryWeighInStore();
      await _pump(tester, store: store, units: UnitSystem.imperial);
      await _openSheet(tester);
      await tester.enterText(find.byKey(WeighInSheetKeys.weight), '30');
      await _save(tester);

      expect(find.text('Enter a weight from 45 to 661 lb.'), findsOneWidget);
    });

    testWidgets('body fat and waist are saved, waist in centimeters', (
      tester,
    ) async {
      final store = InMemoryWeighInStore();
      await _pump(tester, store: store, units: UnitSystem.imperial);
      await _openSheet(tester);
      await tester.enterText(find.byKey(WeighInSheetKeys.weight), '180');
      await tester.tap(find.byKey(WeighInSheetKeys.more));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(WeighInSheetKeys.bodyFat), '21.5');
      await tester.enterText(find.byKey(WeighInSheetKeys.waist), '34');
      await _save(tester);

      final saved = (await store.all()).single;
      expect(saved.bodyFatPercent, 21.5);
      expect(saved.waistCentimeters, closeTo(86.36, 1e-9));
    });

    testWidgets('body fat out of range names the range', (tester) async {
      final store = InMemoryWeighInStore();
      await _pump(tester, store: store);
      await _openSheet(tester);
      await tester.enterText(find.byKey(WeighInSheetKeys.weight), '80');
      await tester.tap(find.byKey(WeighInSheetKeys.more));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(WeighInSheetKeys.bodyFat), '80');
      await _save(tester);

      expect(find.text('Body fat goes from 3 to 70%.'), findsOneWidget);
      expect(await store.count(), 0);
    });
  });
}
