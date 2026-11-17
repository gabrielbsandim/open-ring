import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/features/goals/application/goal_path_providers.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_path.dart';
import 'package:open_ring/features/goals/presentation/goal_week_card.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';

const _start = LocalDate(2026, 11, 16);
const _monday = LocalDate(2027, 2, 22);
const _until = LocalDate(2027, 3, 7);
const _steps = Lever(kind: LeverKind.steps, target: 9000);

Goal _goal({GoalPhase phase = GoalPhase.block}) => Goal(
  id: 1,
  kind: GoalKind.loseFat,
  pace: GoalPace.standard,
  startedOn: _start,
  anchorKg: 78.4,
  referenceKg: 74.0,
  blockStartedOn: _start,
  blockAnchorKg: 78.4,
  phase: phase,
  phaseSince: _monday.addDays(-7),
  phaseUntil: phase == GoalPhase.maintenance ? _until : null,
  levers: const [_steps],
  endedOn: null,
  endReason: null,
);

GoalWeekView _keeping({required bool over}) => GoalWeekRunning(
  goal: _goal(phase: GoalPhase.maintenance),
  monday: _monday,
  week: 15,
  levers: const [LeverProgress(lever: _steps, achieved: 2, days: null)],
  review: null,
  maintenance: GoalMaintenance(until: _until, over: over),
);

GoalPathView _path() => (
  path: goalPath(
    goal: _goal(),
    snapshot: (
      rate: const WeightRateReady(
        perWeek: -0.2958,
        low: -0.3881,
        high: -0.2034,
      ),
      trendKg: 77.782,
    ),
    heightCm: 178,
    on: const LocalDate(2027, 2, 21),
  ),
  daily: const [],
  line: const [],
);

Future<void> _pump(
  WidgetTester tester, {
  required GoalWeekView week,
  double scale = 1,
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
}) async {
  final router = GoRouter(
    initialLocation: '/today',
    routes: [
      GoRoute(
        path: '/today',
        builder: (_, _) => Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: const [GoalWeekCardSlot()],
          ),
        ),
      ),
    ],
  );
  await pumpScaled(
    tester,
    MaterialApp.router(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      localeListResolutionCallback: AppLocales.resolve,
      supportedLocales: AppLocales.supported,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
    ),
    textScaler: TextScaler.linear(scale),
    brightness: brightness,
    locale: locale,
    overrides: [
      goalWeekProvider.overrideWith((ref) async => week),
      goalPathProvider.overrideWith((ref) async => _path()),
    ],
  );
}

String _text(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join('\n');

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byKey(GoalWeekCardKeys.card)));

void main() {
  group('G11b2 criterion 6: the card in maintenance', () {
    testWidgets('the tag says it is keeping', (tester) async {
      await _pump(tester, week: _keeping(over: false));

      expect(find.text(_l10n(tester).goalsWeekTagMaintenance), findsOneWidget);
    });

    testWidgets('the tag never reads week 15 of 12', (tester) async {
      await _pump(tester, week: _keeping(over: false));

      final text = _text(tester).toLowerCase();
      expect(text, isNot(contains('week 15')));
      expect(text, isNot(contains('of 12')));
    });

    testWidgets('shows the keeping line with the day of until', (tester) async {
      await _pump(tester, week: _keeping(over: false));

      expect(find.byKey(GoalWeekCardKeys.maintenance), findsOneWidget);
      final line = _l10n(tester).goalsWeekKeepingUntil('Mar 7');
      expect(find.text(line), findsOneWidget);
    });

    testWidgets('over shows the over line and no keeping line', (tester) async {
      await _pump(tester, week: _keeping(over: true));

      final l10n = _l10n(tester);
      expect(find.byKey(GoalWeekCardKeys.maintenance), findsOneWidget);
      expect(find.text(l10n.goalsWeekMaintenanceOver), findsOneWidget);
      expect(find.text(l10n.goalsWeekKeepingUntil('Mar 7')), findsNothing);
    });

    testWidgets('has no review button', (tester) async {
      await _pump(tester, week: _keeping(over: false));

      expect(find.byKey(GoalWeekCardKeys.openReview), findsNothing);
      expect(find.byKey(GoalWeekCardKeys.review), findsNothing);
    });

    testWidgets('a running block has no maintenance line or tag', (
      tester,
    ) async {
      await _pump(
        tester,
        week: GoalWeekRunning(
          goal: _goal(),
          monday: _monday,
          week: 4,
          levers: const [LeverProgress(lever: _steps, achieved: 2, days: null)],
          review: null,
        ),
      );

      expect(find.byKey(GoalWeekCardKeys.maintenance), findsNothing);
      expect(find.text(_l10n(tester).goalsWeekTagMaintenance), findsNothing);
    });
  });

  group('G11b2 criterion 9: the card lays out in maintenance', () {
    for (final layout in layoutMatrix()) {
      for (final over in [false, true]) {
        testWidgets('${over ? 'over' : 'keeping'} at $layout', (tester) async {
          await _pump(
            tester,
            week: _keeping(over: over),
            scale: layout.scale,
            locale: layout.locale,
            brightness: layout.brightness,
          );

          expect(find.byKey(GoalWeekCardKeys.maintenance), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
