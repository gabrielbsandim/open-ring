import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/features/effort/domain/effort_day.dart';
import 'package:open_ring/features/effort/presentation/effort_coach_card.dart';
import 'package:open_ring/features/effort/presentation/effort_screen.dart';
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

EffortWeek _week(double points, int strengthDays) =>
    EffortWeek(monday: _monday, points: points, strengthDays: strengthDays);

List<Override> _overrides({
  Set<ModuleId> modules = const {ModuleId.effort},
  EffortWeek? week,
  List<EffortSession>? sessions,
  double? lastSeven = 185,
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
];

Future<void> _pump(
  WidgetTester tester, {
  Set<ModuleId> modules = const {ModuleId.effort},
  EffortWeek? week,
  List<EffortSession>? sessions,
  double? lastSeven = 185,
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

Future<void> _toFoot(WidgetTester tester) =>
    tester.scrollUntilVisible(find.byKey(EffortKeys.foot), 300);

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

  group('the sessions', () {
    testWidgets('lists the sessions of this week, newest first', (
      tester,
    ) async {
      await _pump(tester);
      await _toFoot(tester);
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
      await _toFoot(tester);
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
      await _toFoot(tester);
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
      await _toFoot(tester);
      expect(find.byKey(EffortKeys.sessionsEmpty), findsOneWidget);
      expect(find.byKey(WorkoutEntryButton.startKey), findsOneWidget);
      expect(
        _text(tester, EffortKeys.weekMessage),
        _l10n(tester).effortWeekOpen('138'),
      );
    });
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
    final states = <String, (EffortWeek, List<EffortSession>)>{
      'a full week': (_week(140, 1), [_lastWeek, _run, _strength]),
      'an empty week': (_week(0, 0), const []),
    };
    for (final locale in AppLocales.supported) {
      for (final MapEntry(key: name, value: (week, sessions))
          in states.entries) {
        testWidgets('fits 2x in $locale with $name', (tester) async {
          await _pump(
            tester,
            week: week,
            sessions: sessions,
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
