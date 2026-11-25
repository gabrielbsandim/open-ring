import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/body/presentation/weigh_in_sheet.dart';
import 'package:open_ring/features/body/presentation/weight_chart.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_chart.dart';
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
  group('TR8 acceptance 1: three tiles', () {
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

  group('TR8 acceptance 2: stable rate', () {
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

  group('TR8 acceptance 3b: chart unit', () {
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

  group('TR8 acceptance 3: imperial units', () {
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

  group('TR9 acceptance 1: building', () {
    const missing = WeightRateBuilding(daysMissing: 6, spanMissing: 4);
    final dates = [
      for (final offset in [-29, -26, -22, -19, -15, -8, 0])
        november.addDays(offset),
    ];

    testWidgets('shows what is missing, the count and the first and last day', (
      tester,
    ) async {
      final units = _units(UnitSystem.metric);
      await pumpTrajectory(
        tester,
        view: const TrajectoryBuilding(missing),
        summaryLoad: () async => summaryOn(dates),
      );

      final text = _allText(tester, TrajectoryKeys.building);
      expect(find.byKey(TrajectoryKeys.building), findsOneWidget);
      expect(_hasNumber(text, 6), isTrue, reason: 'days missing in $text');
      expect(_hasNumber(text, 4), isTrue, reason: 'span missing in $text');
      expect(_hasNumber(text, 7), isTrue, reason: 'weigh-in days in $text');
      expect(text, contains(units.format.monthDay(dates.first)));
      expect(text, contains(units.format.monthDay(dates.last)));
    });

    testWidgets('draws the weigh-ins on the Body weight chart', (tester) async {
      await pumpTrajectory(
        tester,
        view: const TrajectoryBuilding(missing),
        summaryLoad: () async => summaryOn(dates),
      );

      expect(
        _inside(TrajectoryKeys.building, find.byType(WeightChart)),
        findsOneWidget,
      );
      expect(find.byKey(TrajectoryKeys.card), findsNothing);
      expect(find.byKey(TrajectoryKeys.firm), findsNothing);
    });

    testWidgets('a single weigh-in names that one day as first and last', (
      tester,
    ) async {
      final units = _units(UnitSystem.metric);
      await pumpTrajectory(
        tester,
        view: const TrajectoryBuilding(
          WeightRateBuilding(daysMissing: 7, spanMissing: 13),
        ),
        summaryLoad: () async => summaryOn([november]),
      );

      expect(find.byKey(TrajectoryKeys.building), findsOneWidget);
      expect(
        _textIn(TrajectoryKeys.building, units.format.monthDay(november)),
        findsWidgets,
      );
      expect(
        _inside(TrajectoryKeys.building, find.byType(WeightChart)),
        findsOneWidget,
      );
    });
  });

  group('TR9 acceptance 2: no weigh-ins', () {
    testWidgets('shows the empty title and the log first weigh-in button', (
      tester,
    ) async {
      await pumpTrajectory(
        tester,
        view: const TrajectoryBuilding(null),
        summaryLoad: () async => null,
      );

      expect(find.byKey(TrajectoryKeys.none), findsOneWidget);
      expect(
        _inside(TrajectoryKeys.none, find.text(_l10n.bodyEmptyTitle)),
        findsOneWidget,
      );
      expect(
        _inside(TrajectoryKeys.none, find.text(_l10n.bodyWeightLogFirst)),
        findsOneWidget,
      );
      expect(find.byKey(TrajectoryKeys.building), findsNothing);
    });

    testWidgets('the button opens the weigh-in sheet', (tester) async {
      await pumpTrajectory(
        tester,
        view: const TrajectoryBuilding(null),
        summaryLoad: () async => null,
      );

      await tester.tap(find.text(_l10n.bodyWeightLogFirst));
      await tester.pumpAndSettle();

      expect(find.byType(WeighInSheet), findsOneWidget);
    });

    testWidgets('a view with no trend but a summary shows neither the card '
        'nor the placeholder', (tester) async {
      await pumpTrajectory(tester, view: const TrajectoryBuilding(null));

      final shown =
          find.byKey(TrajectoryKeys.none).evaluate().length +
          find.byKey(TrajectoryKeys.building).evaluate().length;
      expect(shown, 1);
      expect(find.byKey(TrajectoryKeys.card), findsNothing);
      expect(find.byKey(TrajectoryKeys.placeholder), findsNothing);
    });
  });

  group('TR9 acceptance 3: guard', () {
    testWidgets('shows both percents with two digits and no tiles', (
      tester,
    ) async {
      await pumpTrajectory(tester, view: guardView);

      final text = _allText(tester, TrajectoryKeys.guard);
      expect(find.byKey(TrajectoryKeys.guard), findsOneWidget);
      expect(text, contains('1.20'));
      expect(text, contains('1.60'));
      expect(text, contains('%'));
      expect(find.byKey(TrajectoryKeys.now), findsNothing);
      expect(find.byKey(TrajectoryKeys.firm), findsNothing);
      expect(find.byKey(TrajectoryKeys.band), findsNothing);
      expect(find.byKey(TrajectoryKeys.placeholder), findsNothing);
    });

    testWidgets('whole percents still get two digits', (tester) async {
      await pumpTrajectory(
        tester,
        view: const TrajectoryGuard(
          LossRate(
            kg: 1.5,
            kgLow: 1,
            kgHigh: 2,
            percent: 1.5,
            percentLow: 1,
            percentHigh: 2,
          ),
        ),
      );

      final text = _allText(tester, TrajectoryKeys.guard);
      expect(text, contains('1.00'));
      expect(text, contains('2.00'));
    });

    testWidgets('with numbers hidden no percent is written', (tester) async {
      await pumpTrajectory(tester, view: guardView, hidden: true);

      expect(find.byKey(TrajectoryKeys.guard), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('1.20'), findsNothing);
      expect(find.textContaining('1.60'), findsNothing);
    });
  });

  group('TR9 acceptance 4: refusals', () {
    final reasons = [
      TrajectoryRefusal.underage,
      TrajectoryRefusal.pregnancy,
      TrajectoryRefusal.noHeight,
    ];

    testWidgets('each reason shows its own copy', (tester) async {
      final copies = <String>{};
      for (final reason in reasons) {
        await tester.pumpWidget(const SizedBox());
        await pumpTrajectory(tester, view: TrajectoryRefused(reason));
        expect(find.byKey(TrajectoryKeys.refused), findsOneWidget);
        copies.add(_allText(tester, TrajectoryKeys.refused));
      }

      expect(copies, hasLength(reasons.length));
      expect(copies, isNot(contains('')));
    });

    testWidgets('only no height offers the profile button', (tester) async {
      for (final reason in reasons) {
        await tester.pumpWidget(const SizedBox());
        await pumpTrajectory(tester, view: TrajectoryRefused(reason));
        final button = _inside(
          TrajectoryKeys.refused,
          find.text(_l10n.energyOpenProfile),
        );

        expect(
          button,
          reason == TrajectoryRefusal.noHeight ? findsOneWidget : findsNothing,
          reason: '$reason',
        );
      }
    });

    testWidgets('the profile button goes to settings', (tester) async {
      await pumpTrajectoryRouted(
        tester,
        view: const TrajectoryRefused(TrajectoryRefusal.noHeight),
      );

      await tester.tap(find.text(_l10n.energyOpenProfile));
      await tester.pumpAndSettle();

      expect(find.text(settingsStub), findsOneWidget);
    });

    testWidgets('a refusal shows no placeholder, tile or retry', (
      tester,
    ) async {
      await pumpTrajectory(
        tester,
        view: const TrajectoryRefused(TrajectoryRefusal.pregnancy),
      );

      expect(find.byKey(TrajectoryKeys.placeholder), findsNothing);
      expect(find.byKey(TrajectoryKeys.firm), findsNothing);
      expect(find.byKey(TrajectoryKeys.retry), findsNothing);
    });
  });

  group('TR9 acceptance 5: error and retry', () {
    void expectErrorWithRetry() {
      expect(find.byKey(TrajectoryKeys.error), findsOneWidget);
      expect(find.byKey(TrajectoryKeys.retry), findsOneWidget);
      expect(find.byKey(TrajectoryKeys.placeholder), findsNothing);
      expect(find.byKey(TrajectoryKeys.card), findsNothing);
    }

    testWidgets('a TrajectoryError shows the error copy and a retry', (
      tester,
    ) async {
      await pumpTrajectory(tester, view: TrajectoryError(StateError('x')));

      expectErrorWithRetry();
    });

    testWidgets('an AsyncError of the view shows the error and a retry', (
      tester,
    ) async {
      await pumpTrajectory(
        tester,
        view: readyView(),
        load: () => Future.error(StateError('view')),
      );

      expectErrorWithRetry();
    });

    testWidgets('an AsyncError of the summary shows the error and a retry', (
      tester,
    ) async {
      await pumpTrajectory(
        tester,
        view: readyView(),
        summaryLoad: () => Future.error(StateError('summary')),
      );

      expectErrorWithRetry();
    });

    testWidgets('retry refreshes the weigh-ins and the view, then Ready', (
      tester,
    ) async {
      var viewBuilds = 0;
      var weighInBuilds = 0;
      await pumpTrajectory(
        tester,
        view: readyView(),
        load: () {
          viewBuilds++;
          return viewBuilds == 1
              ? Future.error(StateError('first build'))
              : Future.value(readyView());
        },
        weighIns: () {
          weighInBuilds++;
          return Future.value(const <WeighIn>[]);
        },
      );
      expectErrorWithRetry();
      expect(viewBuilds, 1);
      expect(weighInBuilds, 1);

      await tester.tap(find.byKey(TrajectoryKeys.retry));
      await tester.pumpAndSettle();

      expect(viewBuilds, 2);
      expect(weighInBuilds, 2);
      expect(find.byKey(TrajectoryKeys.card), findsOneWidget);
      expect(find.byKey(TrajectoryKeys.error), findsNothing);
      expect(find.byKey(TrajectoryKeys.retry), findsNothing);
    });

    testWidgets('retry after a TrajectoryError reaches Ready', (tester) async {
      var builds = 0;
      await pumpTrajectory(
        tester,
        view: readyView(),
        load: () async {
          builds++;
          return builds == 1 ? TrajectoryError(StateError('x')) : readyView();
        },
      );
      expectErrorWithRetry();

      await tester.tap(find.byKey(TrajectoryKeys.retry));
      await tester.pumpAndSettle();

      expect(builds, 2);
      expect(find.byKey(TrajectoryKeys.card), findsOneWidget);
    });

    testWidgets('retry after a summary failure reaches Ready', (tester) async {
      var builds = 0;
      await pumpTrajectory(
        tester,
        view: readyView(),
        summaryLoad: () {
          builds++;
          return builds == 1
              ? Future.error(StateError('first read'))
              : Future.value(summaryEnding(november));
        },
      );
      expectErrorWithRetry();

      await tester.tap(find.byKey(TrajectoryKeys.retry));
      await tester.pumpAndSettle();

      expect(builds, 2);
      expect(find.byKey(TrajectoryKeys.card), findsOneWidget);
    });

    testWidgets('a retry that fails again still shows the error and retry', (
      tester,
    ) async {
      var builds = 0;
      await pumpTrajectory(
        tester,
        view: readyView(),
        load: () {
          builds++;
          return Future.error(StateError('always'));
        },
      );

      await tester.tap(find.byKey(TrajectoryKeys.retry));
      await tester.pumpAndSettle();

      expect(builds, 2);
      expectErrorWithRetry();
    });
  });

  group('TR9 acceptance 6: hidden numbers', () {
    testWidgets('Ready shows the chart, the direction row and the notice', (
      tester,
    ) async {
      await pumpTrajectory(tester, view: readyView(), hidden: true);

      final chart = tester.widget<TrajectoryChart>(
        find.byKey(TrajectoryKeys.chart),
      );
      expect(chart.hidden, isTrue);
      expect(find.byKey(TrajectoryKeys.hidden), findsOneWidget);
      expect(
        _textIn(TrajectoryKeys.direction, _l10n.bodyDirectionDown),
        findsWidgets,
      );
      expect(
        _textIn(TrajectoryKeys.direction, _l10n.bodyDirectionMovingWhy),
        findsWidgets,
      );
      expect(find.byKey(TrajectoryKeys.placeholder), findsNothing);
    });

    testWidgets('a stable rate reads stable in the direction row', (
      tester,
    ) async {
      await pumpTrajectory(
        tester,
        view: readyView(rate: stableRate),
        hidden: true,
      );

      expect(
        _textIn(TrajectoryKeys.direction, _l10n.bodyDirectionStable),
        findsWidgets,
      );
      expect(
        _textIn(TrajectoryKeys.direction, _l10n.bodyDirectionStableWhy),
        findsWidgets,
      );
    });

    testWidgets('shows no tile, no kg and no lb text', (tester) async {
      await pumpTrajectory(tester, view: readyView(), hidden: true);

      expect(find.byKey(TrajectoryKeys.now), findsNothing);
      expect(find.byKey(TrajectoryKeys.firm), findsNothing);
      expect(find.byKey(TrajectoryKeys.band), findsNothing);
      expect(find.textContaining('kg'), findsNothing);
      expect(find.textContaining('lb'), findsNothing);
    });

    testWidgets('imperial with numbers hidden shows no lb or kg text', (
      tester,
    ) async {
      await pumpTrajectory(
        tester,
        view: readyView(),
        units: UnitSystem.imperial,
        hidden: true,
      );

      expect(find.byKey(TrajectoryKeys.chart), findsOneWidget);
      expect(find.textContaining('lb'), findsNothing);
      expect(find.textContaining('kg'), findsNothing);
    });

    testWidgets('the chart draws no dots', (tester) async {
      await pumpTrajectory(tester, view: readyView(), hidden: true);

      final paint = find.descendant(
        of: find.byKey(TrajectoryKeys.chart),
        matching: find.byType(CustomPaint),
      );
      expect(tester.renderObject(paint), isNot(paints..circle()));
    });

    testWidgets(
      'with numbers shown the chart is not hidden and has no notice',
      (tester) async {
        await pumpTrajectory(tester, view: readyView());

        final chart = tester.widget<TrajectoryChart>(
          find.byKey(TrajectoryKeys.chart),
        );
        expect(chart.hidden, isFalse);
        expect(find.byKey(TrajectoryKeys.hidden), findsNothing);
        expect(find.byKey(TrajectoryKeys.direction), findsNothing);
      },
    );
  });

  group('TR9 only Off keeps the placeholder', () {
    testWidgets('Off shows the placeholder and nothing else', (tester) async {
      await pumpTrajectory(tester, view: const TrajectoryOff());

      expect(find.byKey(TrajectoryKeys.placeholder), findsOneWidget);
      expect(find.byKey(TrajectoryKeys.chart), findsNothing);
      expect(find.byKey(TrajectoryKeys.retry), findsNothing);
    });

    final others = <String, TrajectoryView>{
      'Refused': const TrajectoryRefused(TrajectoryRefusal.underage),
      'Building': const TrajectoryBuilding(
        WeightRateBuilding(daysMissing: 6, spanMissing: 4),
      ),
      'Guard': guardView,
      'Error': TrajectoryError(StateError('x')),
    };
    for (final MapEntry(:key, :value) in others.entries) {
      testWidgets('$key does not show the placeholder', (tester) async {
        await pumpTrajectory(tester, view: value);

        expect(find.byKey(TrajectoryKeys.placeholder), findsNothing);
      });
    }
  });

  group('TR9 acceptance 9: new states do not overflow', () {
    final states = <String, _State>{
      'building': const _State(
        view: TrajectoryBuilding(
          WeightRateBuilding(daysMissing: 6, spanMissing: 4),
        ),
        key: TrajectoryKeys.building,
      ),
      'none': _State(
        view: const TrajectoryBuilding(null),
        key: TrajectoryKeys.none,
        summary: () async => null,
      ),
      'guard': const _State(view: guardView, key: TrajectoryKeys.guard),
      'guard hidden': const _State(
        view: guardView,
        key: TrajectoryKeys.guard,
        hidden: true,
      ),
      'underage': const _State(
        view: TrajectoryRefused(TrajectoryRefusal.underage),
        key: TrajectoryKeys.refused,
      ),
      'pregnancy': const _State(
        view: TrajectoryRefused(TrajectoryRefusal.pregnancy),
        key: TrajectoryKeys.refused,
      ),
      'no height': const _State(
        view: TrajectoryRefused(TrajectoryRefusal.noHeight),
        key: TrajectoryKeys.refused,
      ),
      'error': _State(
        view: TrajectoryError(StateError('x')),
        key: TrajectoryKeys.error,
      ),
      'ready hidden': _State(
        view: readyView(),
        key: TrajectoryKeys.hidden,
        hidden: true,
      ),
    };
    for (final layout in layoutMatrix()) {
      for (final MapEntry(:key, :value) in states.entries) {
        testWidgets('$key at $layout', (tester) async {
          await pumpTrajectory(
            tester,
            view: value.view,
            hidden: value.hidden,
            summaryLoad: value.summary,
            scale: layout.scale,
            brightness: layout.brightness,
            locale: layout.locale,
          );

          expect(find.byKey(value.key), findsOneWidget);
        });
      }
    }
  });

  group('TR8 acceptance 6: no overflow', () {
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

typedef _SummaryLoad = Future<WeightSummary?> Function();

class _State {
  const new({
    required this.view,
    required this.key,
    this.hidden = false,
    this.summary,
  });

  final TrajectoryView view;
  final Key key;
  final bool hidden;
  final _SummaryLoad? summary;
}

bool _hasNumber(String text, int number) =>
    RegExp('(?<![0-9.])$number(?![0-9.])').hasMatch(text);

String _allText(WidgetTester tester, Key key) => tester
    .widgetList<Text>(_inside(key, find.byType(Text)))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join('|');
