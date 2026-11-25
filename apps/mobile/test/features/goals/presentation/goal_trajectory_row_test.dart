import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/goals/application/goal_path_providers.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_path.dart';
import 'package:open_ring/features/goals/presentation/goal_screen.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_entry_row.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../../trajectory/presentation/trajectory_screen_fixtures.dart';

const _en = Locale('en');
const _tall = Size(360, 2600);
const _today = LocalDate(2026, 12, 10);
const _start = LocalDate(2026, 11, 16);
const Set<ModuleId> _on = {ModuleId.body, ModuleId.goals, ModuleId.trajectory};

Goal _goal({
  GoalKind kind = GoalKind.loseFat,
  GoalPhase phase = GoalPhase.block,
  LocalDate? until,
}) {
  final weighed = kind == GoalKind.loseFat;
  return Goal(
    id: 1,
    kind: kind,
    pace: weighed ? GoalPace.standard : null,
    startedOn: _start,
    anchorKg: weighed ? 78.4 : null,
    referenceKg: weighed ? 74.0 : null,
    blockStartedOn: _start,
    blockAnchorKg: weighed ? 78.4 : null,
    phase: phase,
    phaseSince: _start,
    phaseUntil: until,
    levers: const [],
    endedOn: null,
    endReason: null,
  );
}

GoalWeekView _running(Goal goal) => GoalWeekRunning(
  goal: goal,
  monday: const LocalDate(2026, 12, 7),
  week: 4,
  levers: const [],
  review: null,
);

GoalWeekView _base(Goal goal) => GoalWeekBase(
  goal: goal,
  rate: const WeightRateBuilding(daysMissing: 3, spanMissing: 0),
);

GoalWeekView _paused(Goal goal) => GoalWeekPaused(
  goal: goal,
  until: const LocalDate(2027, 1, 3),
  rule: null,
  over: false,
);

GoalWeekView _recovery(Goal goal) =>
    GoalWeekRecovery(goal: goal, monday: const LocalDate(2026, 12, 7), week: 4);

GoalPathView _path(Goal goal) {
  final daily = [
    for (var d = 0; d <= 20; d += 2)
      (date: _start.addDays(d), value: 78.4 - d * 0.03),
  ];
  return (
    path: goalPath(
      goal: goal,
      snapshot: (
        rate: const WeightRateReady(
          perWeek: -0.2958,
          low: -0.3881,
          high: -0.2034,
        ),
        trendKg: 77.782,
      ),
      heightCm: 178,
      on: const LocalDate(2026, 12, 6),
    ),
    daily: daily,
    line: weightTrend(daily),
  );
}

class _Reads {
  int views = 0;
}

Future<GoRouter> _pump(
  WidgetTester tester, {
  required GoalWeekView week,
  Set<ModuleId> modules = _on,
  _Reads? reads,
  bool hidden = false,
  double scale = 1,
  Brightness brightness = Brightness.light,
  Locale locale = _en,
}) async {
  final router = stubRouter(const GoalScreen());
  await pumpScaled(
    tester,
    routerHost(router),
    textScaler: TextScaler.linear(scale),
    brightness: brightness,
    locale: locale,
    size: _tall,
    overrides: <Override>[
      goalWeekProvider.overrideWith((ref) async => week),
      goalPathProvider.overrideWith((ref) async => _path(_goal())),
      currentDateProvider.overrideWithValue(_today),
      moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
      hideNumbersStoreProvider.overrideWithValue(
        InMemoryHideNumbersStore(hidden: hidden),
      ),
      unitSystemStoreProvider.overrideWithValue(
        InMemoryUnitSystemStore(UnitSystem.metric),
      ),
      trajectoryViewProvider.overrideWith((ref) {
        reads?.views++;
        return Future.value(readyView());
      }),
    ],
  );
  return router;
}

void main() {
  final stages = <String, GoalWeekView Function(Goal)>{
    'base': _base,
    'running': _running,
    'paused': _paused,
    'recovery': _recovery,
  };

  for (final MapEntry(:key, :value) in stages.entries) {
    testWidgets('acceptance 7: a lose fat goal in $key shows the row', (
      tester,
    ) async {
      await _pump(tester, week: value(_goal()));

      expect(find.byKey(TrajectoryEntryRow.rowKey), findsOneWidget);
    });
  }

  testWidgets('acceptance 7: the row reads the 12 week low to high', (
    tester,
  ) async {
    final view = readyView();
    final units = UnitFormat(
      MetricFormat(lookupAppLocalizations(_en), _en.toString()),
      UnitSystem.metric,
    );
    await _pump(tester, week: _running(_goal()));

    final text = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(TrajectoryEntryRow.rowKey),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data ?? '')
        .join('|');
    expect(text, contains(lookupAppLocalizations(_en).trajectoryTitle));
    expect(text, contains(units.bodyWeightNumber(view.band.low)));
    expect(text, contains(units.bodyWeightNumber(view.band.high)));
  });

  testWidgets('acceptance 7: hidden numbers give a generic subtitle', (
    tester,
  ) async {
    final view = readyView();
    final units = UnitFormat(
      MetricFormat(lookupAppLocalizations(_en), _en.toString()),
      UnitSystem.metric,
    );
    await _pump(tester, week: _running(_goal()), hidden: true);

    final row = find.byKey(TrajectoryEntryRow.rowKey);
    expect(row, findsOneWidget);
    expect(
      find.descendant(
        of: row,
        matching: find.textContaining(units.bodyWeightNumber(view.band.low)),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: row, matching: find.textContaining('kg')),
      findsNothing,
    );
  });

  testWidgets('acceptance 7: a tap pushes the trajectory screen', (
    tester,
  ) async {
    final router = await _pump(tester, week: _running(_goal()));

    await tester.ensureVisible(find.byKey(TrajectoryEntryRow.rowKey));
    await tester.tap(find.byKey(TrajectoryEntryRow.rowKey));
    await tester.pumpAndSettle();

    expect(find.text(trajectoryStub), findsOneWidget);
    expect(router.canPop(), isTrue);
  });

  testWidgets('a goal that is not lose fat shows no row and no read', (
    tester,
  ) async {
    final reads = _Reads();
    await _pump(
      tester,
      week: _running(_goal(kind: GoalKind.getFitter)),
      reads: reads,
    );

    expect(find.byKey(GoalScreenKeys.noWeight), findsOneWidget);
    expect(find.byKey(TrajectoryEntryRow.rowKey), findsNothing);
    expect(reads.views, 0);
  });

  testWidgets('no goal shows no row', (tester) async {
    await _pump(tester, week: const GoalWeekNoGoal());

    expect(find.byKey(GoalScreenKeys.noGoal), findsOneWidget);
    expect(find.byKey(TrajectoryEntryRow.rowKey), findsNothing);
  });

  testWidgets('the Goals module off shows no row', (tester) async {
    await _pump(tester, week: const GoalWeekOff());

    expect(find.byKey(GoalScreenKeys.off), findsOneWidget);
    expect(find.byKey(TrajectoryEntryRow.rowKey), findsNothing);
  });

  testWidgets('acceptance 8: module off shows no row and never reads the '
      'view', (tester) async {
    final reads = _Reads();
    await _pump(
      tester,
      week: _running(_goal()),
      modules: const {ModuleId.body, ModuleId.goals},
      reads: reads,
    );

    expect(find.byKey(GoalScreenKeys.formula), findsOneWidget);
    expect(find.byKey(TrajectoryEntryRow.rowKey), findsNothing);
    expect(reads.views, 0);
  });

  group('acceptance 9: no overflow', () {
    for (final layout in layoutMatrix()) {
      for (final MapEntry(:key, :value) in stages.entries) {
        testWidgets('$key with the row at $layout', (tester) async {
          await _pump(
            tester,
            week: value(_goal()),
            scale: layout.scale,
            brightness: layout.brightness,
            locale: layout.locale,
          );

          expect(find.byKey(TrajectoryEntryRow.rowKey), findsOneWidget);
        });
      }

      testWidgets('hidden numbers with the row at $layout', (tester) async {
        await _pump(
          tester,
          week: _running(_goal()),
          hidden: true,
          scale: layout.scale,
          brightness: layout.brightness,
          locale: layout.locale,
        );

        expect(find.byKey(TrajectoryEntryRow.rowKey), findsOneWidget);
      });
    }
  });
}
