import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/features/goals/presentation/goal_evidence_sheet.dart';
import 'package:open_ring/features/trajectory/domain/levers_view.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_levers_card.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_screen.dart';

import '../../../helpers/layout_harness.dart';
import 'trajectory_screen_fixtures.dart';

LeverTrend _trend({
  required double change,
  required double low,
  required double high,
  required double typical,
  int validDays = 88,
}) => LeverTrend(
  slopePerDay: change / leverTrendWindowDays,
  slopeLow: low / leverTrendWindowDays,
  slopeHigh: high / leverTrendWindowDays,
  typical: typical,
  centerDay: 44.5,
  validDays: validDays,
);

final LeverTrend _steps = _trend(
  change: 1100,
  low: 600,
  high: 1600,
  typical: 8700,
);
final LeverTrend _regularity = _trend(change: 2, low: -1, high: 5, typical: 79);
final LeverTrend _duration = _trend(change: 14, low: 4, high: 24, typical: 426);
final LeverTrend _falling = _trend(change: -3, low: -4, high: -1, typical: 54);

LeversReady _levers({LeverTrend? resting, int restingDays = 30}) =>
    LeversReady({
      RingLever.steps: (validDays: 88, trend: _steps),
      RingLever.sleepRegularity: (validDays: 84, trend: _regularity),
      RingLever.restingHeartRate: (validDays: restingDays, trend: resting),
      RingLever.sleepDuration: (validDays: 84, trend: _duration),
    });

Future<void> _pump(
  WidgetTester tester, {
  LeversView? levers,
  TrajectoryView? view,
  bool noWeighIns = false,
  double scale = 1,
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
}) => pumpScaled(
  tester,
  screenHost(const TrajectoryScreen()),
  textScaler: TextScaler.linear(scale),
  brightness: brightness,
  locale: locale,
  size: const Size(360, 5000),
  overrides: trajectoryOverrides(
    view: view ?? readyView(),
    levers: levers ?? _levers(),
    summaryLoad: noWeighIns ? () async => null : null,
  ),
);

Finder _inCard(Finder finder) => find.descendant(
  of: find.byKey(TrajectoryLeversKeys.card),
  matching: finder,
);

Future<String> _yours(WidgetTester tester, RingLever lever) async {
  final row = find.byKey(TrajectoryLeversKeys.row(lever));
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pumpAndSettle();
  return tester.widget<GoalEvidenceSheet>(find.byType(GoalEvidenceSheet)).yours;
}

void main() {
  group('levers card', () {
    testWidgets('a moving lever reads its direction and its change', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.byKey(TrajectoryLeversKeys.card), findsOneWidget);
      expect(_inCard(find.text('Where the last 90 days point')), findsOne);
      expect(_inCard(find.text('typical 8,700 steps a day')), findsOne);
      expect(_inCard(find.text('rising')), findsOne);
      expect(_inCard(find.text('+1,100 in 90 days')), findsOne);
    });

    testWidgets('a lever with its interval over zero reads stable', (
      tester,
    ) async {
      await _pump(tester);

      expect(_inCard(find.text('typical 79 of 100')), findsOne);
      expect(_inCard(find.text('+2 in 90 days')), findsOne);
      expect(_inCard(find.text('+14 min in 90 days')), findsOne);
      expect(_inCard(find.text('stable')), findsNWidgets(2));
    });

    testWidgets('under the minimum of valid days reads not yet with counts', (
      tester,
    ) async {
      await _pump(tester);

      expect(_inCard(find.text('Resting HR')), findsOne);
      expect(_inCard(find.text('not yet')), findsOne);
      expect(
        _inCard(find.text('30 of 90 valid days so far; it needs 54.')),
        findsOne,
      );
    });

    testWidgets('no valid day at all still reads not yet', (tester) async {
      await _pump(tester, levers: _levers(restingDays: 0));

      expect(
        _inCard(find.text('0 of 90 valid days so far; it needs 54.')),
        findsOne,
      );
    });

    testWidgets('a falling lever reads falling with a signed change', (
      tester,
    ) async {
      await _pump(tester, levers: _levers(resting: _falling));

      expect(_inCard(find.text('falling')), findsOne);
      expect(_inCard(find.textContaining('3 bpm in 90 days')), findsOne);
      expect(_inCard(find.text('typical 54 bpm')), findsOne);
    });

    testWidgets('a change that rounds to zero carries no sign', (tester) async {
      final small = _trend(change: 0.4, low: -1, high: 2, typical: 79);
      await _pump(
        tester,
        levers: LeversReady({
          RingLever.sleepRegularity: (validDays: 84, trend: small),
        }),
      );

      expect(_inCard(find.text('0 in 90 days')), findsOne);
    });

    testWidgets('levers off or failing show no card', (tester) async {
      await _pump(tester, levers: const LeversOff());
      expect(find.byKey(TrajectoryLeversKeys.card), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await _pump(tester, levers: LeversError(StateError('ring')));
      expect(find.byKey(TrajectoryLeversKeys.card), findsNothing);
    });

    for (final (name, view, noWeighIns) in [
      ('refused', const TrajectoryRefused(TrajectoryRefusal.pregnancy), false),
      ('guard', guardView, false),
      ('building', const TrajectoryBuilding(null), false),
      ('no weigh-ins', readyView(), true),
    ]) {
      testWidgets('the card shows on the $name state', (tester) async {
        await _pump(tester, view: view, noWeighIns: noWeighIns);

        expect(find.byKey(TrajectoryLeversKeys.card), findsOneWidget);
      });
    }

    testWidgets('the card shows nowhere when Trajectory is off', (
      tester,
    ) async {
      await _pump(tester, view: const TrajectoryOff());

      expect(find.byKey(TrajectoryLeversKeys.card), findsNothing);
    });
  });

  group('lever evidence sheets', () {
    testWidgets('moving steps carry the 90 day fan', (tester) async {
      await _pump(tester);

      final yours = await _yours(tester, RingLever.steps);

      expect(
        yours,
        'Typical value: 8,700 steps a day, on 88 of 90 valid days. '
        'Change over 90 days: +1,100 (+600 to +1,600, 90% interval). '
        'If the line held another 90 days, the most the app draws: '
        '9,800 to 10,800 steps a day.',
      );
      expect(find.text('Steps'), findsAtLeast(1));
      expect(
        find.descendant(
          of: find.byKey(GoalEvidenceKeys.rule),
          matching: find.textContaining('passes 500 steps'),
        ),
        findsOne,
      );
    });

    testWidgets('stable steps carry no fan', (tester) async {
      final flat = _trend(change: 200, low: -300, high: 700, typical: 8700);
      await _pump(
        tester,
        levers: LeversReady({RingLever.steps: (validDays: 88, trend: flat)}),
      );

      final yours = await _yours(tester, RingLever.steps);

      expect(yours, isNot(contains('If the line held')));
      expect(
        yours,
        endsWith('The interval includes zero: stable, with no line ahead.'),
      );
    });

    testWidgets('an interval over zero names the minimum it misses', (
      tester,
    ) async {
      await _pump(tester);

      final yours = await _yours(tester, RingLever.sleepDuration);

      expect(yours, contains('7 h 6 min a night'));
      expect(
        yours,
        endsWith(
          'The interval leaves out zero, but the change is under 20 min: '
          'stable.',
        ),
      );
    });

    testWidgets('a stable lever with zero inside says so', (tester) async {
      await _pump(tester);

      final yours = await _yours(tester, RingLever.sleepRegularity);

      expect(
        yours,
        'Typical value: 79 of 100, on 88 of 90 valid days. '
        'Change over 90 days: +2 (\u22121 to +5, 90% interval). '
        'The interval includes zero: stable, with no line ahead.',
      );
    });

    testWidgets('a moving lever other than steps says why, with no fan', (
      tester,
    ) async {
      await _pump(tester, levers: _levers(resting: _falling));

      final yours = await _yours(tester, RingLever.restingHeartRate);

      expect(
        yours,
        endsWith(
          'The interval leaves out zero and the change passes the minimum.',
        ),
      );
    });

    testWidgets('a lever without a trend explains the missing days', (
      tester,
    ) async {
      await _pump(tester);

      final yours = await _yours(tester, RingLever.restingHeartRate);

      expect(yours, '30 of 90 valid days so far; it needs 54.');
    });

    testWidgets('each lever has its own source and limits', (tester) async {
      await _pump(tester);
      final copies = <String>{};
      for (final lever in RingLever.values) {
        await _yours(tester, lever);
        final sheet = find.byKey(GoalEvidenceKeys.sheet);
        copies.add(
          tester
              .widgetList<Text>(
                find.descendant(of: sheet, matching: find.byType(Text)),
              )
              .map((text) => text.data ?? '')
              .join('|'),
        );
        Navigator.of(tester.element(sheet)).pop();
        await tester.pumpAndSettle();
      }

      expect(copies, hasLength(RingLever.values.length));
    });
  });

  group('layout', () {
    for (final locale in AppLocales.supported) {
      testWidgets('no overflow at 2.0 in $locale', (tester) async {
        await _pump(
          tester,
          levers: _levers(resting: _falling),
          scale: 2,
          locale: locale,
          brightness: Brightness.dark,
        );

        expect(find.byKey(TrajectoryLeversKeys.card), findsOneWidget);
        await _yours(tester, RingLever.steps);
        expect(find.byKey(GoalEvidenceKeys.sheet), findsOneWidget);
      });
    }
  });
}
