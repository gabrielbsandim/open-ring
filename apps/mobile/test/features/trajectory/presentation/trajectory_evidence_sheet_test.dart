import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/goals/presentation/goal_evidence_sheet.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import 'trajectory_screen_fixtures.dart';

const _en = Locale('en');
const _tall = Size(360, 2000);

AppLocalizations get _l10n => lookupAppLocalizations(_en);

UnitFormat _units(UnitSystem system) => UnitFormat(
  MetricFormat(lookupAppLocalizations(_en), _en.toString()),
  system,
);

Future<void> _pump(
  WidgetTester tester, {
  required TrajectoryView view,
  UnitSystem units = UnitSystem.metric,
  bool hidden = false,
  LayoutCase layout = const LayoutCase(
    scale: 1,
    brightness: Brightness.light,
    locale: _en,
  ),
}) => pumpScaled(
  tester,
  screenHost(const TrajectoryScreen()),
  textScaler: layout.textScaler,
  brightness: layout.brightness,
  locale: layout.locale,
  size: _tall,
  overrides: trajectoryOverrides(view: view, units: units, hidden: hidden),
);

Future<void> _open(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

String _yours() {
  final finder = find.descendant(
    of: find.byKey(GoalEvidenceKeys.yours),
    matching: find.byType(Text),
  );
  return _texts(finder).join(' ');
}

List<String> _texts(Finder finder) => [
  for (final element in finder.evaluate())
    (element.widget as Text).data ??
        (element.widget as Text).textSpan!.toPlainText(),
];

String _title() =>
    (find.byKey(GoalEvidenceKeys.title).evaluate().single.widget as Text).data!;

String _signed(UnitFormat units, double kg) =>
    units.format.signed(units.bodyWeightIn(kg), digits: 2);

void main() {
  final metric = _units(UnitSystem.metric);

  group('rate sheet', () {
    testWidgets('the Now tile opens the rate sheet with the interval', (
      tester,
    ) async {
      await _pump(tester, view: readyView());
      await _open(tester, TrajectoryKeys.now);

      expect(find.byKey(GoalEvidenceKeys.sheet), findsOneWidget);
      expect(_title(), _l10n.bodyWeightRate);
      expect(
        _yours(),
        contains(
          _l10n.trajectorySheetRateYours(
            _signed(metric, losing.perWeek),
            _signed(metric, losing.low),
            _signed(metric, losing.high),
            'kg',
          ),
        ),
      );
      expect(find.textContaining('28 days'), findsWidgets);
      expect(find.textContaining('8 days with a weigh-in'), findsWidgets);
    });

    testWidgets('the rate row opens the same sheet', (tester) async {
      await _pump(tester, view: readyView());
      await _open(tester, TrajectoryKeys.rate);

      expect(_title(), _l10n.bodyWeightRate);
    });

    testWidgets('a stable rate says the interval includes zero', (
      tester,
    ) async {
      await _pump(tester, view: readyView(rate: stableRate));
      await _open(tester, TrajectoryKeys.rate);

      expect(_yours(), contains('The interval includes zero'));
      expect(_yours(), isNot(contains('does not include zero')));
    });
  });

  group('scenario sheets', () {
    testWidgets('the 4 week tile shows the bend of 28 days and the range', (
      tester,
    ) async {
      final view = readyView();
      await _pump(tester, view: view);
      await _open(tester, TrajectoryKeys.firm);

      expect(_title(), _l10n.trajectorySheetFirmTitle('4'));
      final yours = _yours();
      expect(yours, contains('Over 28 days the bend counts 27.0 days'));
      expect(yours, contains(metric.bodyWeight(view.trendKg)));
      expect(yours, contains(metric.bodyWeight(view.firm.mid)));
      expect(yours, contains(metric.bodyWeight(view.noiseKg)));
      expect(
        yours,
        contains(
          _l10n.trajectoryRange(
            metric.bodyWeightNumber(view.firm.low),
            metric.bodyWeightNumber(view.firm.high),
            'kg',
          ),
        ),
      );
      expect(yours, isNot(contains('BMI')));
    });

    testWidgets('the 12 week tile shows the bend of 84 days', (tester) async {
      await _pump(tester, view: readyView());
      await _open(tester, TrajectoryKeys.band);

      expect(_title(), _l10n.trajectorySheetBandTitle('12'));
      expect(_yours(), contains('Over 84 days the bend counts 75.0 days'));
      expect(find.textContaining('1% of body weight'), findsOneWidget);
    });

    testWidgets('a band held at the BMI floor says so', (tester) async {
      final raw = weightScenario(77.6, losing, 0.35, 84);
      final floored = ScenarioBand(
        days: 84,
        low: raw.low + 1.2,
        mid: raw.mid + 0.4,
        high: raw.high,
      );
      await _pump(tester, view: readyView(band: floored));
      await _open(tester, TrajectoryKeys.band);

      expect(_yours(), contains(_l10n.trajectorySheetScenarioFloor('18.5')));
    });

    testWidgets('a trend already under the floor is held at the trend', (
      tester,
    ) async {
      final raw = weightScenario(50, losing, 0.35, 84);
      final atTrend = ScenarioBand(days: 84, low: 50, mid: 50, high: raw.high);
      await _pump(tester, view: readyView(trendKg: 50, band: atTrend));
      await _open(tester, TrajectoryKeys.band);

      expect(
        _yours(),
        contains(_l10n.trajectorySheetScenarioFloorTrend('18.5')),
      );
      expect(_yours(), isNot(contains('held at the weight of BMI')));
    });

    testWidgets('imperial units show lb and never kg', (tester) async {
      final imperial = _units(UnitSystem.imperial);
      final view = readyView();
      await _pump(tester, view: view, units: UnitSystem.imperial);
      await _open(tester, TrajectoryKeys.band);

      final yours = _yours();
      expect(yours, contains(imperial.bodyWeight(view.trendKg)));
      expect(yours, contains(' lb'));
      expect(yours, isNot(contains('kg')));
    });
  });

  group('hidden numbers', () {
    testWidgets('no tile or rate row exists and the direction opens nothing', (
      tester,
    ) async {
      await _pump(tester, view: readyView(), hidden: true);

      expect(find.byKey(TrajectoryKeys.now), findsNothing);
      expect(find.byKey(TrajectoryKeys.firm), findsNothing);
      expect(find.byKey(TrajectoryKeys.band), findsNothing);
      expect(find.byKey(TrajectoryKeys.rate), findsNothing);
      await tester.tap(find.byKey(TrajectoryKeys.direction));
      await tester.pumpAndSettle();
      expect(find.byKey(GoalEvidenceKeys.sheet), findsNothing);
    });
  });

  group('no overflow', () {
    for (final layout in layoutMatrix()) {
      for (final key in [TrajectoryKeys.rate, TrajectoryKeys.band]) {
        testWidgets('$key sheet at $layout', (tester) async {
          await _pump(tester, view: readyView(), layout: layout);
          await expectNoLayoutOverflow(() => _open(tester, key));

          expect(find.byKey(GoalEvidenceKeys.sheet), findsOneWidget);
        });
      }
    }
  });
}
