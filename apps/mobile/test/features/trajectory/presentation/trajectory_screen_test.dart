import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import 'trajectory_screen_fixtures.dart';

const _en = Locale('en');
const _gaining = WeightRateReady(perWeek: 0.3, low: 0.2, high: 0.4);

AppLocalizations get _l10n => lookupAppLocalizations(_en);

UnitFormat _units(UnitSystem system) => UnitFormat(
  MetricFormat(lookupAppLocalizations(_en), _en.toString()),
  system,
);

Finder _inside(Key key, Finder matching) =>
    find.descendant(of: find.byKey(key), matching: matching);

Finder _textIn(Key key, String text) => _inside(key, find.textContaining(text));

void _expectTile(
  Key key, {
  required UnitFormat units,
  required LocalDate date,
  required ScenarioBand band,
}) {
  expect(_textIn(key, units.format.monthDay(date)), findsWidgets);
  expect(_textIn(key, units.bodyWeightNumber(band.low)), findsWidgets);
  expect(_textIn(key, units.bodyWeightNumber(band.high)), findsWidgets);
}

void main() {
  group('acceptance 1: three tiles', () {
    testWidgets('Now, 4 weeks and 12 weeks tiles show dates and weights', (
      tester,
    ) async {
      final view = readyView();
      final units = _units(UnitSystem.metric);
      await pumpTrajectory(tester, view: view);

      expect(find.byKey(TrajectoryKeys.card), findsOneWidget);
      expect(find.byKey(TrajectoryKeys.chart), findsOneWidget);
      expect(
        _textIn(TrajectoryKeys.now, units.bodyWeightNumber(view.trendKg)),
        findsWidgets,
      );
      _expectTile(
        TrajectoryKeys.firm,
        units: units,
        date: november.addDays(28),
        band: view.firm,
      );
      _expectTile(
        TrajectoryKeys.band,
        units: units,
        date: november.addDays(84),
        band: view.band,
      );
      expect(find.byKey(TrajectoryKeys.placeholder), findsNothing);
    });

    testWidgets('an upper edge of 76.95 is formatted by the shared helper', (
      tester,
    ) async {
      final view = readyView(
        firm: const ScenarioBand(days: 28, low: 75.55, mid: 76.3, high: 76.95),
      );
      final units = _units(UnitSystem.metric);
      await pumpTrajectory(tester, view: view);

      expect(
        _textIn(TrajectoryKeys.firm, units.bodyWeightNumber(76.95)),
        findsWidgets,
      );
      expect(
        _textIn(TrajectoryKeys.firm, units.bodyWeightNumber(75.55)),
        findsWidgets,
      );
    });

    testWidgets('a band crossing a year boundary shows the January dates', (
      tester,
    ) async {
      final view = readyView(asOf: december);
      final units = _units(UnitSystem.metric);
      await pumpTrajectory(tester, view: view, asOf: december);

      expect(december.addDays(28).year, 2027);
      _expectTile(
        TrajectoryKeys.firm,
        units: units,
        date: december.addDays(28),
        band: view.firm,
      );
      _expectTile(
        TrajectoryKeys.band,
        units: units,
        date: december.addDays(84),
        band: view.band,
      );
    });
  });

  group('acceptance 2: stable rate', () {
    testWidgets('a rate interval containing 0 reads differently from a loss', (
      tester,
    ) async {
      await pumpTrajectory(tester, view: readyView());
      final losingText = _allText(tester, TrajectoryKeys.rate);
      expect(stableRate.stable, isTrue);

      // A new ProviderScope in the same slot keeps the first overrides.
      await tester.pumpWidget(const SizedBox());
      await pumpTrajectory(tester, view: readyView(rate: stableRate));
      final stableText = _allText(tester, TrajectoryKeys.rate);

      expect(find.byKey(TrajectoryKeys.rate), findsOneWidget);
      expect(stableText, isNotEmpty);
      expect(stableText, isNot(losingText));
    });

    testWidgets('a stable rate shows the stable title and the stable note', (
      tester,
    ) async {
      await pumpTrajectory(tester, view: readyView(rate: stableRate));

      expect(
        _inside(TrajectoryKeys.rate, find.text(_l10n.bodyRateStableTitle)),
        findsOneWidget,
      );
      expect(find.textContaining(_l10n.trajectoryStableNote), findsOneWidget);
    });

    testWidgets('a losing rate shows neither the stable title nor note', (
      tester,
    ) async {
      await pumpTrajectory(tester, view: readyView());

      expect(
        _inside(TrajectoryKeys.rate, find.text(_l10n.bodyRateStableTitle)),
        findsNothing,
      );
      expect(find.textContaining(_l10n.trajectoryStableNote), findsNothing);
    });
  });

  group('acceptance 3b: chart unit', () {
    Finder chartLabel(RegExp unit) => find.descendant(
      of: find.byKey(TrajectoryKeys.chart),
      matching: find.bySemanticsLabel(unit),
    );

    testWidgets('imperial chart label names lb and not kg', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTrajectory(
        tester,
        view: readyView(),
        units: UnitSystem.imperial,
      );

      expect(chartLabel(RegExp(r'\blb\b')), findsOneWidget);
      expect(chartLabel(RegExp(r'\bkg\b')), findsNothing);
      handle.dispose();
    });

    testWidgets('metric chart label names kg and not lb', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTrajectory(tester, view: readyView());

      expect(chartLabel(RegExp(r'\bkg\b')), findsOneWidget);
      expect(chartLabel(RegExp(r'\blb\b')), findsNothing);
      handle.dispose();
    });
  });

  group('bend note only where the burn falls', () {
    testWidgets('a gaining non stable rate shows no bend note', (tester) async {
      expect(_gaining.stable, isFalse);
      await pumpTrajectory(tester, view: readyView(rate: _gaining));

      expect(find.byKey(TrajectoryKeys.card), findsOneWidget);
      expect(find.textContaining(_l10n.trajectoryBendNote), findsNothing);
    });

    testWidgets('a losing rate shows the bend note', (tester) async {
      await pumpTrajectory(tester, view: readyView());

      expect(find.textContaining(_l10n.trajectoryBendNote), findsOneWidget);
    });
  });

  group('reload keeps the card', () {
    testWidgets('a pending reload still shows the previous card', (
      tester,
    ) async {
      final pending = Completer<TrajectoryView>();
      var builds = 0;
      await pumpScaled(
        tester,
        screenHost(const TrajectoryScreen()),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.light,
        locale: _en,
        overrides: [
          ...trajectoryOverrides(
            view: readyView(),
            load: () {
              builds++;
              return builds == 1 ? Future.value(readyView()) : pending.future;
            },
          ),
        ],
      );
      expect(find.byKey(TrajectoryKeys.card), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrajectoryScreen)),
      )..invalidate(trajectoryViewProvider);
      await tester.pump();
      await tester.pump();

      expect(builds, 2);
      expect(container.read(trajectoryViewProvider).isLoading, isTrue);
      expect(container.read(trajectoryViewProvider).hasValue, isTrue);
      expect(find.byKey(TrajectoryKeys.card), findsOneWidget);

      pending.complete(readyView());
      await tester.pump();
      await tester.pump();
      expect(find.byKey(TrajectoryKeys.card), findsOneWidget);
    });
  });

  group('acceptance 3: imperial units', () {
    testWidgets('tiles show lb values and no kg text', (tester) async {
      final view = readyView();
      final units = _units(UnitSystem.imperial);
      await pumpTrajectory(tester, view: view, units: UnitSystem.imperial);

      for (final key in [
        TrajectoryKeys.now,
        TrajectoryKeys.firm,
        TrajectoryKeys.band,
      ]) {
        expect(_textIn(key, 'lb'), findsWidgets, reason: '$key');
      }
      expect(
        _textIn(TrajectoryKeys.firm, units.bodyWeightNumber(view.firm.low)),
        findsWidgets,
      );
      expect(
        _textIn(TrajectoryKeys.band, units.bodyWeightNumber(view.band.high)),
        findsWidgets,
      );
      expect(find.textContaining('kg'), findsNothing);
    });

    testWidgets('metric tiles show kg', (tester) async {
      await pumpTrajectory(tester, view: readyView());

      expect(_textIn(TrajectoryKeys.firm, 'kg'), findsWidgets);
      expect(find.textContaining('lb'), findsNothing);
    });
  });

  group('acceptance 4: hidden numbers', () {
    testWidgets('shows the placeholder and no weight unit text', (
      tester,
    ) async {
      await pumpTrajectory(tester, view: readyView(), hidden: true);

      expect(find.byKey(TrajectoryKeys.placeholder), findsOneWidget);
      expect(find.byKey(TrajectoryKeys.firm), findsNothing);
      expect(find.byKey(TrajectoryKeys.band), findsNothing);
      expect(find.textContaining('kg'), findsNothing);
      expect(find.textContaining('lb'), findsNothing);
    });

    testWidgets('imperial with hidden numbers shows no lb text', (
      tester,
    ) async {
      await pumpTrajectory(
        tester,
        view: readyView(),
        units: UnitSystem.imperial,
        hidden: true,
      );

      expect(find.byKey(TrajectoryKeys.placeholder), findsOneWidget);
      expect(find.textContaining('lb'), findsNothing);
      expect(find.textContaining('kg'), findsNothing);
    });
  });

  group('acceptance 5: other states show the placeholder', () {
    final states = <String, TrajectoryView>{
      'Off': const TrajectoryOff(),
      'Refused': const TrajectoryRefused(TrajectoryRefusal.pregnancy),
      'Building': const TrajectoryBuilding(null),
      'Guard': guardView,
    };
    for (final MapEntry(:key, :value) in states.entries) {
      testWidgets('$key shows the placeholder only', (tester) async {
        await pumpTrajectory(tester, view: value);

        expect(find.byKey(TrajectoryKeys.placeholder), findsOneWidget);
        expect(find.byKey(TrajectoryKeys.firm), findsNothing);
        expect(find.byKey(TrajectoryKeys.chart), findsNothing);
      });
    }

    testWidgets('Error shows the placeholder and metricLoadError', (
      tester,
    ) async {
      await pumpTrajectory(tester, view: TrajectoryError(StateError('x')));

      expect(find.byKey(TrajectoryKeys.placeholder), findsOneWidget);
      expect(
        find.text(lookupAppLocalizations(_en).metricLoadError),
        findsOneWidget,
      );
      expect(find.byKey(TrajectoryKeys.firm), findsNothing);
    });
  });

  group('acceptance 6: no overflow', () {
    for (final layout in layoutMatrix()) {
      testWidgets('Ready at $layout', (tester) async {
        await pumpTrajectory(
          tester,
          view: readyView(asOf: december),
          asOf: december,
          scale: layout.scale,
          brightness: layout.brightness,
          locale: layout.locale,
        );

        expect(find.byKey(TrajectoryKeys.card), findsOneWidget);
      });

      testWidgets('stable Ready imperial at $layout', (tester) async {
        await pumpTrajectory(
          tester,
          view: readyView(rate: stableRate),
          units: UnitSystem.imperial,
          scale: layout.scale,
          brightness: layout.brightness,
          locale: layout.locale,
        );

        expect(find.byKey(TrajectoryKeys.card), findsOneWidget);
      });

      testWidgets('placeholder at $layout', (tester) async {
        await pumpTrajectory(
          tester,
          view: const TrajectoryOff(),
          scale: layout.scale,
          brightness: layout.brightness,
          locale: layout.locale,
        );

        expect(find.byKey(TrajectoryKeys.placeholder), findsOneWidget);
      });
    }
  });
}

String _allText(WidgetTester tester, Key key) => tester
    .widgetList<Text>(_inside(key, find.byType(Text)))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join('|');
