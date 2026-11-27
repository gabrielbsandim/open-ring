import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/energy/application/energy_providers.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/trajectory/application/trajectory_kcal_providers.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import 'trajectory_screen_fixtures.dart';

const _en = Locale('en');
const _tall = Size(360, 4000);

const _prototypeDay = EnergyDayEstimate(
  resting: 1725,
  base: 1725,
  steps: 200,
  workouts: 0,
);

const _readyBalance = EnergyBalanceReady(
  low: -473,
  mid: -385,
  high: -286,
  weighIns: 25,
);

const _fullKcal = KcalReady(
  resting: (low: 1550, high: 1900),
  restChange12: -40,
  dayChange12: -90,
  balance: _readyBalance,
);

MetricFormat _format(Locale locale) =>
    MetricFormat(lookupAppLocalizations(locale), locale.toString());

Finder get _card => find.byKey(TrajectoryKeys.kcal);

String _cardText(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(of: _card, matching: find.byType(Text)),
  ))
    text.data ?? text.textSpan?.toPlainText() ?? '',
].join(' | ');

Future<void> _pump(
  WidgetTester tester, {
  TrajectoryView? view,
  EnergyGate gate = EnergyGate.on,
  EnergyDay day = _prototypeDay,
  TrajectoryKcal? kcal,
  double scale = 1,
  Brightness brightness = Brightness.light,
  Locale locale = _en,
  Size size = _tall,
}) async {
  final shown = view ?? readyView();
  await pumpScaled(
    tester,
    screenHost(const TrajectoryScreen()),
    textScaler: TextScaler.linear(scale),
    brightness: brightness,
    locale: locale,
    size: size,
    overrides: [
      ...trajectoryOverrides(view: shown),
      energyGateProvider.overrideWithValue(gate),
      energyTodayProvider.overrideWith((ref) async => day),
      activeGoalProvider.overrideWith((ref) async => null),
      if (kcal != null)
        trajectoryKcalProvider.overrideWith((ref) async => kcal),
    ],
  );
}

Future<void> _reveal(WidgetTester tester) => expectNoLayoutOverflow(() async {
  await tester.scrollUntilVisible(
    _card,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
});

Future<TrajectoryKcal> _provided(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(TrajectoryScreen)),
  );
  return container.read(trajectoryKcalProvider.future);
}

void main() {
  group('TR10a acceptance 1: Energy gate not on', () {
    for (final gate in [
      EnergyGate.off,
      EnergyGate.underage,
      EnergyGate.hidden,
    ]) {
      testWidgets('${gate.name} shows no kcal card and no kcal text', (
        tester,
      ) async {
        await _pump(tester, gate: gate);

        expect(await _provided(tester), isA<KcalOff>());
        expect(find.byKey(TrajectoryKeys.card), findsOneWidget);
        expect(_card, findsNothing);
        expect(find.textContaining('kcal'), findsNothing);
      });
    }

    testWidgets('on shows the kcal card with kcal text', (tester) async {
      await _pump(tester);

      expect(await _provided(tester), isA<KcalReady>());
      expect(_card, findsOneWidget);
      expect(
        find.descendant(of: _card, matching: find.textContaining('kcal')),
        findsWidgets,
      );
    });
  });

  group('TR10a acceptance 2: prototype numbers', () {
    for (final locale in layoutLocales) {
      testWidgets('resting range and changes read in $locale', (tester) async {
        final format = _format(locale);
        await _pump(tester, locale: locale);

        final text = _cardText(tester);
        expect(text, contains(format.integer(1550)));
        expect(text, contains(format.integer(1900)));
        expect(text, contains(format.integer(40)));
      });

      testWidgets('whole day change reads 90 in $locale', (tester) async {
        final format = _format(locale);
        await _pump(
          tester,
          locale: locale,
          day: const EnergyDayMissing({EnergyField.sex}),
        );

        expect(_cardText(tester), contains(format.integer(90)));
      });
    }

    testWidgets('sex missing drops the resting row and keeps the rest', (
      tester,
    ) async {
      final format = _format(_en);
      await _pump(tester, day: const EnergyDayMissing({EnergyField.sex}));

      final text = _cardText(tester);
      expect(_card, findsOneWidget);
      expect(text, isNot(contains(format.integer(1550))));
      expect(text, isNot(contains(format.integer(1900))));
      expect(text, contains(format.integer(90)));
    });

    testWidgets('a floored band middle moves the numbers shown', (
      tester,
    ) async {
      final format = _format(_en);
      final view = readyView(
        band: const ScenarioBand(days: 84, low: 72.6, mid: 74.6, high: 75.1),
      );
      await _pump(
        tester,
        view: view,
        day: const EnergyDayMissing({EnergyField.sex}),
      );

      final text = _cardText(tester);
      expect(text, contains(format.integer(30)));
      expect(text, contains(format.integer(70)));
      expect(text, isNot(contains(format.integer(90))));
    });
  });

  group('TR10a acceptance 3: balance states', () {
    final states = <String, TrajectoryKcal>{
      'ready': _fullKcal,
      'no rate': const KcalReady(
        resting: (low: 1550, high: 1900),
        restChange12: -40,
        dayChange12: -90,
        balance: EnergyBalanceNoRate(),
      ),
      'count': const KcalReady(
        resting: (low: 1550, high: 1900),
        restChange12: -40,
        dayChange12: -90,
        balance: EnergyBalanceCount(12),
      ),
      'block': const KcalReady(
        resting: (low: 1550, high: 1900),
        restChange12: -40,
        dayChange12: -90,
        balance: EnergyBalanceBlock(LocalDate(2026, 12, 27)),
      ),
      'near balance': const KcalReady(
        resting: (low: 1550, high: 1900),
        restChange12: -40,
        dayChange12: -90,
        balance: EnergyBalanceReady(low: -108, mid: 0, high: 79, weighIns: 25),
      ),
    };

    testWidgets('each state reads differently from the others', (tester) async {
      final texts = <String, String>{};
      for (final MapEntry(:key, :value) in states.entries) {
        await tester.pumpWidget(const SizedBox());
        await _pump(tester, kcal: value);
        texts[key] = _cardText(tester);
      }

      expect(texts.values.toSet(), hasLength(states.length));
    });

    testWidgets('a count state names the number of weigh-ins', (tester) async {
      await _pump(tester, kcal: states['count']);

      expect(_cardText(tester), contains(_format(_en).integer(12)));
    });

    testWidgets('a block state names the day it waits for', (tester) async {
      await _pump(tester, kcal: states['block']);

      expect(
        _cardText(tester),
        contains(_format(_en).monthDay(const LocalDate(2026, 12, 27))),
      );
    });

    testWidgets('a ready balance shows the stepped range', (tester) async {
      await _pump(tester, kcal: states['ready']);

      final text = _cardText(tester);
      expect(text, contains(_format(_en).integer(450)));
      expect(text, contains(_format(_en).integer(300)));
    });
  });

  group('TR10a acceptance 4: the card appears only on Ready', () {
    final views = <String, TrajectoryView>{
      'guard': guardView,
      'building': const TrajectoryBuilding(null),
      'refused': const TrajectoryRefused(TrajectoryRefusal.noHeight),
    };
    for (final MapEntry(:key, :value) in views.entries) {
      testWidgets('$key shows no kcal card even with Energy on', (
        tester,
      ) async {
        await _pump(tester, view: value, kcal: _fullKcal);

        expect(_card, findsNothing);
        expect(find.textContaining('kcal'), findsNothing);
      });
    }

    testWidgets('ready shows the kcal card', (tester) async {
      await _pump(tester, kcal: _fullKcal);

      expect(_card, findsOneWidget);
    });
  });

  group('TR10a acceptance 5: no overflow', () {
    for (final layout in layoutMatrix()) {
      testWidgets('ready card at $layout', (tester) async {
        await _pump(
          tester,
          kcal: _fullKcal,
          scale: layout.scale,
          brightness: layout.brightness,
          locale: layout.locale,
          size: phoneSize,
        );
        await _reveal(tester);

        expect(_card, findsOneWidget);
      });
    }

    for (final locale in layoutLocales) {
      testWidgets('block and count states at 2.0x in $locale', (tester) async {
        const block = KcalReady(
          resting: (low: 1550, high: 1900),
          restChange12: -40,
          dayChange12: -90,
          balance: EnergyBalanceBlock(LocalDate(2026, 12, 27)),
        );
        await _pump(
          tester,
          kcal: block,
          scale: 2,
          locale: locale,
          size: phoneSize,
        );
        await _reveal(tester);
        expect(_card, findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        const count = KcalReady(
          resting: null,
          restChange12: null,
          dayChange12: -90,
          balance: EnergyBalanceCount(12),
        );
        await _pump(
          tester,
          kcal: count,
          scale: 2,
          locale: locale,
          size: phoneSize,
        );
        await _reveal(tester);
        expect(_card, findsOneWidget);
      });
    }
  });

  group('TR10a review round 1: wording and near zero balance', () {
    KcalReady withBalance(EnergyBalanceReady balance) => KcalReady(
      resting: (low: 1550, high: 1900),
      restChange12: -40,
      dayChange12: -90,
      balance: balance,
    );

    void expectNoMinus(String text) {
      expect(RegExp('[-\u2212]\\s?[0-9]').hasMatch(text), isFalse);
    }

    testWidgets('F1: a range ending near zero below reads Below, unsigned', (
      tester,
    ) async {
      const balance = EnergyBalanceReady(
        low: -300,
        mid: -160,
        high: -20,
        weighIns: 20,
      );
      await _pump(tester, kcal: withBalance(balance));

      final text = _cardText(tester);
      expect(text, contains('Below what you spent'));
      expect(text, isNot(contains('Above')));
      expectNoMinus(text);
    });

    testWidgets('F3: the near balance state reads in balance', (tester) async {
      const balance = EnergyBalanceReady(
        low: -108,
        mid: 0,
        high: 79,
        weighIns: 25,
      );
      await _pump(tester, kcal: withBalance(balance));

      final text = _cardText(tester);
      expect(text, contains('in balance'));
      expect(text, contains('Near balance'));
      expect(text, isNot(contains('Below')));
      expect(text, isNot(contains('Above')));
    });

    testWidgets('F4: a losing trend reads Less at rest', (tester) async {
      await _pump(tester);

      final text = _cardText(tester);
      expect(text, contains('Less at rest'));
      expect(text, isNot(contains('More at rest')));
    });

    testWidgets('F4: a gaining trend reads More at rest', (tester) async {
      final view = readyView(
        rate: const WeightRateReady(perWeek: 0.3, low: 0.2, high: 0.4),
        band: const ScenarioBand(days: 84, low: 77, mid: 81.3, high: 82),
      );
      await _pump(tester, view: view);

      final text = _cardText(tester);
      expect(text, contains('More at rest'));
      expect(text, isNot(contains('Less at rest')));
    });

    testWidgets('F4: a deficit balance reads Below, with no minus sign', (
      tester,
    ) async {
      await _pump(tester, kcal: _fullKcal);

      final text = _cardText(tester);
      expect(text, contains('Below what you spent'));
      expect(text, isNot(contains('Above')));
      expectNoMinus(text);
    });

    testWidgets('F4: a surplus balance reads Above', (tester) async {
      const balance = EnergyBalanceReady(
        low: 120,
        mid: 200,
        high: 280,
        weighIns: 25,
      );
      await _pump(tester, kcal: withBalance(balance));

      expect(_cardText(tester), contains('Above what you spent'));
    });
  });
}
