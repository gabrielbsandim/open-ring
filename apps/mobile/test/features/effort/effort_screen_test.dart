import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/features/effort/domain/effort_day.dart';
import 'package:open_ring/features/effort/presentation/effort_coach_card.dart';
import 'package:open_ring/features/effort/presentation/effort_evidence_sheet.dart';
import 'package:open_ring/features/effort/presentation/effort_load_card.dart';
import 'package:open_ring/features/effort/presentation/effort_screen.dart';
import 'package:open_ring/features/energy/presentation/energy_evidence_sheet.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/workout_entry_button.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../helpers/ble_fakes.dart';
import '../../helpers/layout_harness.dart';
import '../../helpers/ring_fakes.dart';

const LocalDate _monday = LocalDate(2026, 11, 9);

EffortSession _session(
  LocalDate date,
  WorkoutType type,
  int minutes, {
  bool heartRate = false,
}) {
  final start = DateTime.utc(date.year, date.month, date.day, 7);
  final elapsed = Duration(minutes: minutes);
  return (
    date: date,
    start: start,
    end: start.add(elapsed),
    elapsed: elapsed,
    type: type,
    points: metIntensity(type.met, elapsed),
    load: sessionLoad(
      elapsed: elapsed,
      typeDefault: effortTypeDefault(type),
      timeInZones: heartRate ? {4: elapsed} : const <int, Duration>{},
    ),
    strength: type == WorkoutType.strength,
  );
}

final EffortSession _run = _session(_monday, WorkoutType.running, 40);
final EffortSession _strength = _session(
  _monday.addDays(1),
  WorkoutType.strength,
  45,
  heartRate: true,
);
final EffortSession _lastWeek = _session(
  _monday.addDays(-2),
  WorkoutType.cycling,
  60,
);

const EffortCoachCard _coach = (
  advice: CoachAdvice(
    rule: CoachRule.goodReadiness,
    acute: 60,
    chronic: 50,
    chronicWeekAgo: 48,
    yesterdayLoad: 23,
    hardFrom: 120,
    hardDays: 0,
    daysSinceEasy: 1,
  ),
  readiness: 78,
  covered: false,
);

final List<EffortWeekDay> _days = [
  (date: _monday, points: 80, strength: false),
  (date: _monday.addDays(1), points: 60.4, strength: true),
  (date: _monday.addDays(2), points: 0, strength: false),
  for (var i = 3; i < 7; i++)
    (date: _monday.addDays(i), points: null, strength: false),
];

final List<EffortWalk> _walks = [
  (date: _monday.addDays(1), minutes: 12.4),
  (date: _monday, minutes: 20),
];

// 30 days at 40, then yesterday at 100: both lines exist and differ.
final List<double> _steady = [...List.filled(30, 40), 100];

EffortWeek _week(double points, int strengthDays) =>
    EffortWeek(monday: _monday, points: points, strengthDays: strengthDays);

List<Override> _overrides({
  Set<ModuleId> modules = const {ModuleId.effort},
  EffortWeek? week,
  List<EffortSession>? sessions,
  double? lastSeven = 185,
  List<double>? dailyLoad,
  List<EffortWalk> walks = const [],
  bool fail = false,
}) => [
  ...bleOverrides(),
  ...ringOverrides(),
  moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
  effortCoachCardProvider.overrideWith((ref) async => _coach),
  effortWeekProvider.overrideWith((ref) async {
    if (fail) throw StateError('week');
    return week ?? _week(140, 1);
  }),
  effortSessionsProvider.overrideWith(
    (ref) async => sessions ?? [_lastWeek, _run, _strength],
  ),
  effortLastSevenProvider.overrideWith((ref) async => lastSeven),
  effortDailyLoadProvider.overrideWith((ref) async => dailyLoad ?? _steady),
  effortWeekDaysProvider.overrideWith((ref) async => _days),
  effortWeekWalksProvider.overrideWith((ref) async => walks),
];

Future<void> _pump(
  WidgetTester tester, {
  Set<ModuleId> modules = const {ModuleId.effort},
  EffortWeek? week,
  List<EffortSession>? sessions,
  double? lastSeven = 185,
  List<double>? dailyLoad,
  List<EffortWalk> walks = const [],
  bool fail = false,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Brightness brightness = Brightness.dark,
}) => pumpScaled(
  tester,
  screenHost(const EffortScreen()),
  textScaler: textScaler,
  brightness: brightness,
  locale: locale,
  overrides: _overrides(
    modules: modules,
    week: week,
    sessions: sessions,
    lastSeven: lastSeven,
    dailyLoad: dailyLoad,
    walks: walks,
    fail: fail,
  ),
);

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(EffortScreen)));

String _text(WidgetTester tester, Key key) =>
    switch (tester.widget(find.byKey(key))) {
      final Text text => text.data!,
      final CaptionText text => text.text,
      final BodyText text => text.text,
      final other => throw StateError('no text in ${other.runtimeType}'),
    };

Future<void> _show(WidgetTester tester, Key key) =>
    tester.scrollUntilVisible(find.byKey(key), 200);

Future<void> _open(WidgetTester tester, Key key) async {
  await _show(tester, key);
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

GoRouter _router() => GoRouter(
  initialLocation: AppPaths.effort,
  routes: [
    GoRoute(
      path: AppPaths.effort,
      builder: (_, _) => const EffortScreen(),
      routes: [
        GoRoute(
          path: 'formula',
          builder: (_, _) => const Scaffold(body: Text('formula screen')),
        ),
      ],
    ),
  ],
);

Future<void> _pumpRouter(WidgetTester tester, GoRouter router) => pumpScaled(
  tester,
  MaterialApp.router(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    localeListResolutionCallback: AppLocales.resolve,
    supportedLocales: AppLocales.supported,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    routerConfig: router,
  ),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: const Locale('en'),
  overrides: _overrides(),
);

void main() {
  group('the gate', () {
    testWidgets('shows only the title without the Effort module', (
      tester,
    ) async {
      await _pump(tester, modules: const {ModuleId.openScore});
      expect(find.text(_l10n(tester).effortTitle), findsOneWidget);
      expect(find.byKey(EffortKeys.week), findsNothing);
      expect(find.byKey(EffortCoachKeys.card), findsNothing);
    });

    testWidgets('a week that fails shows the load error', (tester) async {
      await _pump(tester, fail: true);
      expect(find.text(_l10n(tester).metricLoadError), findsOneWidget);
      expect(find.byKey(EffortKeys.week), findsNothing);
    });
  });

  group('the week', () {
    testWidgets('shows the points, the strength days and the range', (
      tester,
    ) async {
      await _pump(tester);
      final l10n = _l10n(tester);
      expect(find.byKey(EffortCoachKeys.card), findsOneWidget);
      expect(_text(tester, EffortKeys.weekPoints), '140');
      expect(_text(tester, EffortKeys.weekStrength), '1');
      expect(
        _text(tester, EffortKeys.weekRange),
        l10n.effortWeekRange('Nov 9', 'Nov 15'),
      );
      expect(_text(tester, EffortKeys.weekMessage), l10n.effortWeekOpen('10'));
    });

    final messages = <String, (EffortWeek, String Function(AppLocalizations))>{
      'both covered': (_week(150, 2), (l10n) => l10n.effortWeekBothCovered),
      'points covered': (
        _week(163.4, 1),
        (l10n) => l10n.effortWeekPointsCovered('150'),
      ),
      'strength covered': (
        _week(108.6, 2),
        (l10n) => l10n.effortWeekStrengthCovered('41'),
      ),
    };
    for (final MapEntry(key: name, value: (week, expected))
        in messages.entries) {
      testWidgets('the message for $name', (tester) async {
        await _pump(tester, week: week);
        expect(_text(tester, EffortKeys.weekMessage), expected(_l10n(tester)));
      });
    }

    testWidgets('an empty week asks for nothing', (tester) async {
      await _pump(tester, week: _week(0, 0), sessions: [_lastWeek]);
      expect(
        _text(tester, EffortKeys.weekMessage),
        _l10n(tester).effortWeekEmpty,
      );
    });

    testWidgets('the last 7 days line names the Day Score with Open Score on', (
      tester,
    ) async {
      await _pump(tester, modules: const {ModuleId.effort, ModuleId.openScore});
      final l10n = _l10n(tester);
      expect(
        _text(tester, EffortKeys.lastSeven),
        '${l10n.effortLastSeven('185')} ${l10n.effortLastSevenDayScore}',
      );
    });

    testWidgets('with Open Score off the line is the plain sum', (
      tester,
    ) async {
      await _pump(tester);
      expect(
        _text(tester, EffortKeys.lastSeven),
        _l10n(tester).effortLastSeven('185'),
      );
    });

    testWidgets('without a last 7 days figure there is no line', (
      tester,
    ) async {
      await _pump(tester, lastSeven: null);
      expect(find.byKey(EffortKeys.lastSeven), findsNothing);
    });
  });

  group('the days of the week', () {
    String figure(WidgetTester tester, int index) => tester
        .widget<Text>(
          find
              .descendant(
                of: find.byKey(EffortKeys.weekDay(index)),
                matching: find.byType(Text),
              )
              .last,
        )
        .data!;

    testWidgets('each day shows its points, a zero or nothing', (tester) async {
      await _pump(tester);
      await _show(tester, EffortKeys.weekDays);
      expect(
        [for (var i = 0; i < 7; i++) figure(tester, i)],
        ['80', '60', '·', ' ', ' ', ' ', ' '],
      );
    });

    testWidgets('the strip reads each day, its strength mark and what is to '
        'come', (tester) async {
      await _pump(tester);
      await _show(tester, EffortKeys.weekDays);
      final l10n = _l10n(tester);
      final label = tester
          .widget<Semantics>(find.byKey(EffortKeys.weekDays))
          .properties
          .label;
      expect(
        label,
        [
          l10n.effortWeekDayPoints('Mon', '80'),
          l10n.effortWeekDayStrength('Tue', '60'),
          l10n.effortWeekDayPoints('Wed', '0'),
          l10n.effortWeekDayFuture('Thu'),
          l10n.effortWeekDayFuture('Fri'),
          l10n.effortWeekDayFuture('Sat'),
          l10n.effortWeekDayFuture('Sun'),
        ].join('. '),
      );
    });

    testWidgets('the sources name each type and brisk walking', (tester) async {
      await _pump(tester, walks: _walks);
      await _show(tester, EffortKeys.weekSources);
      final l10n = _l10n(tester);
      final run = _run.points.equivalent.round();
      final strength = _strength.points.equivalent.round();
      expect(
        find.descendant(
          of: find.byKey(EffortKeys.weekSources),
          matching: find.text(
            '${WorkoutType.running.label(l10n)} $run · '
            '${WorkoutType.strength.label(l10n)} $strength · '
            '${l10n.effortBriskWalking} 32',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a week with no points has no sources', (tester) async {
      await _pump(tester, week: _week(0, 0), sessions: const []);
      await _show(tester, EffortKeys.weekMessage);
      expect(find.byKey(EffortKeys.weekSources), findsNothing);
    });
  });

  group('the sessions', () {
    testWidgets('lists the sessions of this week, newest first', (
      tester,
    ) async {
      await _pump(tester);
      await _show(tester, EffortKeys.sessions);
      final l10n = _l10n(tester);
      expect(find.byKey(EffortKeys.session(0)), findsOneWidget);
      expect(find.byKey(EffortKeys.session(1)), findsOneWidget);
      expect(find.byKey(EffortKeys.session(2)), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(EffortKeys.session(0)),
          matching: find.text(WorkoutType.strength.label(l10n)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(EffortKeys.session(1)),
          matching: find.text(WorkoutType.running.label(l10n)),
        ),
        findsOneWidget,
      );
      expect(find.byKey(EffortKeys.sessionsEmpty), findsNothing);
    });

    testWidgets('a session prints its points and its load', (tester) async {
      await _pump(tester);
      await _show(tester, EffortKeys.sessions);
      final l10n = _l10n(tester);
      final points = _run.points.equivalent.round();
      expect(
        find.descendant(
          of: find.byKey(EffortKeys.session(1)),
          matching: find.text(l10n.effortSessionPoints('$points')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(EffortKeys.session(1)),
          matching: find.text(l10n.effortSessionLoad('${_run.load.value}')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('only a session without heart rate says so', (tester) async {
      await _pump(tester);
      await _show(tester, EffortKeys.sessions);
      final l10n = _l10n(tester);
      expect(_run.load.source, LoadSource.typeDefault);
      expect(_strength.load.source, LoadSource.heartRate);
      expect(
        find.text(l10n.effortSessionDetailNoHeartRate('Mon', '40')),
        findsOneWidget,
      );
      expect(find.text(l10n.effortSessionDetail('Tue', '45')), findsOneWidget);
    });

    testWidgets('no session this week offers to start a workout', (
      tester,
    ) async {
      await _pump(tester, week: _week(12, 0), sessions: [_lastWeek]);
      await _show(tester, EffortKeys.sessions);
      expect(find.byKey(EffortKeys.sessionsEmpty), findsOneWidget);
      expect(find.byKey(WorkoutEntryButton.startKey), findsOneWidget);
      expect(
        _text(tester, EffortKeys.weekMessage),
        _l10n(tester).effortWeekOpen('138'),
      );
    });
  });

  group('brisk walking', () {
    testWidgets('one row per day with its minutes, points and load', (
      tester,
    ) async {
      await _pump(tester, walks: _walks);
      await _show(tester, EffortKeys.walk(1));
      final l10n = _l10n(tester);
      Finder inRow(int index, String text) => find.descendant(
        of: find.byKey(EffortKeys.walk(index)),
        matching: find.text(text),
      );
      expect(inRow(0, l10n.effortBriskWalking), findsOneWidget);
      expect(inRow(0, l10n.effortWalkDetail('Tue', '12')), findsOneWidget);
      expect(inRow(0, l10n.effortSessionPoints('12')), findsOneWidget);
      expect(inRow(0, l10n.effortSessionLoad('19')), findsOneWidget);
      expect(inRow(1, l10n.effortWalkDetail('Mon', '20')), findsOneWidget);
      expect(inRow(1, l10n.effortSessionLoad('30')), findsOneWidget);
    });

    testWidgets('walking alone does not show the empty text', (tester) async {
      await _pump(tester, sessions: const [], walks: _walks);
      await _show(tester, EffortKeys.walk(0));
      expect(find.byKey(EffortKeys.sessionsEmpty), findsNothing);
      expect(find.byKey(WorkoutEntryButton.startKey), findsNothing);
    });
  });

  group('the training load', () {
    testWidgets('under 14 days it says how many it has', (tester) async {
      await _pump(tester, dailyLoad: List.filled(9, 30));
      await _show(tester, EffortLoadKeys.card);
      final l10n = _l10n(tester);
      expect(find.byKey(EffortLoadKeys.building), findsOneWidget);
      expect(
        _text(tester, EffortLoadKeys.buildingDays),
        l10n.effortLoadBuildingDays('9', '14'),
      );
      expect(find.byKey(EffortLoadKeys.chart), findsNothing);
      expect(find.byKey(EffortLoadKeys.acute), findsNothing);
    });

    testWidgets('with history it shows the two lines as two numbers', (
      tester,
    ) async {
      await _pump(tester);
      await _show(tester, EffortLoadKeys.card);
      final l10n = _l10n(tester);
      final acute = loadLine(_steady, days: effortAcuteDays)!.round();
      final chronic = loadLine(_steady, days: effortChronicDays)!.round();
      expect(acute, isNot(chronic));
      expect(find.byKey(EffortLoadKeys.building), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(EffortLoadKeys.acute),
          matching: find.text(l10n.effortLoadPerDay('$acute')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(EffortLoadKeys.chronic),
          matching: find.text(l10n.effortLoadPerDay('$chronic')),
        ),
        findsOneWidget,
      );
      expect(_text(tester, EffortLoadKeys.noRatio), l10n.effortLoadNoRatio);
    });

    testWidgets('the chart draws the last 28 days only', (tester) async {
      await _pump(tester);
      await _show(tester, EffortLoadKeys.card);
      final chart = tester.widget<HourlyBars>(find.byKey(EffortLoadKeys.chart));
      expect(chart.values, _steady.sublist(3));
      expect(
        chart.semanticsLabel,
        _l10n(tester).effortLoadChartSemantics('28'),
      );
    });

    testWidgets('the list of what Effort never does has five lines', (
      tester,
    ) async {
      await _pump(tester);
      await _show(tester, EffortKeys.foot);
      final l10n = _l10n(tester);
      expect(find.byKey(EffortKeys.never), findsOneWidget);
      for (final fact in [
        l10n.effortNever1,
        l10n.effortNever2,
        l10n.effortNever3,
        l10n.effortNever4,
        l10n.effortNever5,
      ]) {
        expect(find.text(fact), findsOneWidget);
      }
    });
  });

  group('the evidence sheets', () {
    String body(WidgetTester tester, Key key) =>
        tester.widget<EnergyEvidenceSection>(find.byKey(key)).body;

    testWidgets('the points open theirs with the week and the last 7 days', (
      tester,
    ) async {
      await _pump(tester);
      await _open(tester, EffortKeys.pointsSheet);
      final l10n = _l10n(tester);

      expect(
        _text(tester, EffortEvidenceKeys.title),
        l10n.effortFormulaPointsTitle,
      );
      expect(
        body(tester, EffortEvidenceKeys.yours),
        '${l10n.effortSheetPointsYours('140')} ${l10n.effortLastSeven('185')}',
      );
      expect(body(tester, EffortEvidenceKeys.rule), l10n.effortSheetPointsRule);
    });

    testWidgets('without a last 7 days figure the points say the week only', (
      tester,
    ) async {
      await _pump(tester, lastSeven: null);
      await _open(tester, EffortKeys.pointsSheet);

      expect(
        body(tester, EffortEvidenceKeys.yours),
        _l10n(tester).effortSheetPointsYours('140'),
      );
    });

    testWidgets('the strength days open theirs', (tester) async {
      await _pump(tester);
      await _open(tester, EffortKeys.strengthSheet);
      final l10n = _l10n(tester);

      expect(
        _text(tester, EffortEvidenceKeys.title),
        l10n.effortSheetStrengthTitle,
      );
      expect(
        body(tester, EffortEvidenceKeys.yours),
        l10n.effortSheetStrengthYours('1', '2'),
      );
    });

    testWidgets('the two lines open theirs with both numbers', (tester) async {
      await _pump(tester);
      await _open(tester, EffortLoadKeys.lines);
      final l10n = _l10n(tester);
      final acute = loadLine(_steady, days: effortAcuteDays)!.round();
      final chronic = loadLine(_steady, days: effortChronicDays)!.round();

      expect(
        _text(tester, EffortEvidenceKeys.title),
        l10n.effortSheetLinesTitle,
      );
      expect(
        body(tester, EffortEvidenceKeys.yours),
        l10n.effortSheetLinesYours('7', '$acute', '28', '$chronic'),
      );
    });

    testWidgets('a brisk walking row opens its sheet with the day', (
      tester,
    ) async {
      await _pump(tester, walks: _walks);
      await _open(tester, EffortKeys.walk(0));
      final l10n = _l10n(tester);

      expect(_text(tester, EffortEvidenceKeys.title), l10n.effortBriskWalking);
      expect(
        body(tester, EffortEvidenceKeys.yours),
        l10n.effortSheetWalkYours('Tue', '12', '12', '19'),
      );
    });

    testWidgets('a session row opens nothing', (tester) async {
      await _pump(tester);
      await _open(tester, EffortKeys.session(0));

      expect(find.byKey(EffortEvidenceKeys.sheet), findsNothing);
    });
  });

  testWidgets('the link on a sheet closes it and opens the formula screen', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    await _pumpRouter(tester, router);
    await _open(tester, EffortKeys.pointsSheet);
    await tester.ensureVisible(find.byKey(EffortEvidenceKeys.formula));
    await tester.tap(find.byKey(EffortEvidenceKeys.formula));
    await tester.pumpAndSettle();

    expect(find.byKey(EffortEvidenceKeys.sheet), findsNothing);
    expect(find.text('formula screen'), findsOneWidget);
  });

  testWidgets('the link opens the formula screen', (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    await _pumpRouter(tester, router);
    await _show(tester, EffortKeys.formula);
    await tester.tap(find.byKey(EffortKeys.formula));
    await tester.pumpAndSettle();

    expect(find.text('formula screen'), findsOneWidget);
  });

  testWidgets('the coach card on Today opens the Effort screen', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        GoRoute(
          path: '/today',
          builder: (_, _) => const Scaffold(body: EffortCoachSlot()),
          routes: [
            GoRoute(
              path: 'effort',
              builder: (_, _) => const Scaffold(body: Text('effort screen')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
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
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      overrides: _overrides(),
    );
    await tester.tap(find.byKey(EffortCoachKeys.card));
    await tester.pumpAndSettle();
    expect(AppPaths.effort, '/today/effort');
    expect(find.text('effort screen'), findsOneWidget);
  });

  group('layout', () {
    final states = <String, (EffortWeek, List<EffortSession>, List<double>)>{
      'a full week': (_week(140, 1), [_lastWeek, _run, _strength], _steady),
      'an empty week': (_week(0, 0), const [], const [0, 0, 12]),
    };
    for (final locale in AppLocales.supported) {
      for (final MapEntry(key: name, value: (week, sessions, dailyLoad))
          in states.entries) {
        testWidgets('fits 2x in $locale with $name', (tester) async {
          await _pump(
            tester,
            week: week,
            sessions: sessions,
            dailyLoad: dailyLoad,
            walks: sessions.isEmpty ? const [] : _walks,
            modules: const {ModuleId.effort, ModuleId.openScore},
            locale: locale,
            textScaler: const TextScaler.linear(2),
            brightness: Brightness.light,
          );
          await expectNoLayoutOverflow(
            () => tester.scrollUntilVisible(find.byKey(EffortKeys.foot), 300),
          );
          expect(find.byKey(EffortKeys.foot), findsOneWidget);
        });
      }
    }
  });
}
