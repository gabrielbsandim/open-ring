import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/goals/application/goal_intake_providers.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/goals/application/goals_data.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/goals/presentation/goal_screen.dart';
import 'package:open_ring/features/goals/presentation/goals_module_screen.dart';
import 'package:open_ring/features/goals/presentation/soft_mode_exit_card.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/settings_fakes.dart';
import '../goal_fixtures.dart';
import '../goal_picker_harness.dart';
import '../goals_data_harness.dart';

const _tall = Size(360, 3200);
const _todayStub = 'today stub';

class _World {
  new(this.setup, this.memory, this.spy);

  final GoalSetup setup;
  final InMemoryGoalStore memory;
  final SpyGoalStore spy;

  ProviderContainer get container => setup.container;
}

Future<_World> _world({
  bool on = true,
  bool goal = true,
  int weeks = 3,
  int screenings = 1,
  bool soft = true,
  bool demo = false,
}) async {
  final memory = InMemoryGoalStore();
  final spy = SpyGoalStore(memory);
  await seedGoalsData(
    memory,
    goal: goal,
    weeks: weeks,
    screenings: screenings,
    soft: soft,
  );
  final setup = await setupPicker(
    modules: on ? goalModules : const {ModuleId.body},
    store: memory,
    readStoreOf: (_) => spy,
    demo: demo,
  );
  return _World(setup, memory, spy);
}

Future<GoRouter> _pump(
  WidgetTester tester,
  _World world, {
  Locale locale = const Locale('en'),
  double scale = 1,
  Brightness brightness = Brightness.dark,
  Size size = _tall,
}) async {
  final router = GoRouter(
    initialLocation: AppPaths.settingsModuleGoals,
    routes: [
      GoRoute(
        path: AppPaths.settingsModuleGoals,
        builder: (_, _) => const GoalsModuleScreen(),
      ),
      GoRoute(path: AppPaths.goals, builder: (_, _) => const GoalScreen()),
      GoRoute(
        path: AppTab.today.path,
        builder: (_, _) => const Scaffold(body: Text(_todayStub)),
      ),
    ],
  );
  addTearDown(router.dispose);
  await pumpScaled(
    tester,
    UncontrolledProviderScope(
      container: world.container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        localeListResolutionCallback: AppLocales.resolve,
        supportedLocales: AppLocales.supported,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
      ),
    ),
    textScaler: TextScaler.linear(scale),
    brightness: brightness,
    locale: locale,
    size: size,
    overrides: const [],
  );
  return router;
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(GoalsModuleScreen)));

String _storedLine(WidgetTester tester) =>
    switch (tester.widget(find.byKey(GoalsModuleKeys.stored))) {
      Text(:final data) => data ?? '',
      BodyText(:final text) => text,
      _ => throw StateError('the stored line is neither a Text nor a BodyText'),
    };

String _snackText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
    )
    .map((text) => text.data ?? '')
    .join(' ');

Future<void> _tap(WidgetTester tester, Key key) async {
  await tapKey(tester, key);
}

Future<void> _openDialog(WidgetTester tester) =>
    _tap(tester, GoalsModuleKeys.delete);

Future<void> _confirm(WidgetTester tester) =>
    _tap(tester, GoalsModuleKeys.deleteConfirm);

Future<GoalsDataCount> _count(_World world) =>
    world.container.read(goalsDataCountProvider.future);

// A lazy list that lost rows above the viewport corrects its offset on the
// next layout, so one jump may not land on the top.
Future<void> _toTop(WidgetTester tester) async {
  final position = tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position;
  for (var step = 0; step < 40 && position.pixels > 0; step++) {
    position.jumpTo(0);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  group('3. switching Goals on and off', () {
    testWidgets('the pill reads Off, then On after switching on', (
      tester,
    ) async {
      final world = await _world(on: false, goal: false, screenings: 0);
      await _pump(tester, world);
      final l10n = _l10n(tester);

      var pill = tester.widget<ModuleStatePill>(
        find.byKey(GoalsModuleKeys.state),
      );
      expect(pill.on, isFalse);
      expect(pill.label, l10n.modulesOff);

      await _tap(tester, GoalsModuleKeys.toggle);

      pill = tester.widget<ModuleStatePill>(find.byKey(GoalsModuleKeys.state));
      expect(pill.on, isTrue);
      expect(pill.label, l10n.modulesOn);
      expect(await world.container.read(enabledModulesProvider.future), {
        ModuleId.body,
        ModuleId.goals,
      });
    });

    testWidgets('switching on changes the caption and the action', (
      tester,
    ) async {
      final world = await _world(on: false, goal: false, screenings: 0);
      await _pump(tester, world);
      final before = allText(tester).split('\n').toSet();

      await _tap(tester, GoalsModuleKeys.toggle);
      final after = allText(tester).split('\n').toSet();

      expect(before.difference(after).length, greaterThanOrEqualTo(3));
    });

    testWidgets('switching off changes the pill and deletes nothing', (
      tester,
    ) async {
      final world = await _world();
      await _pump(tester, world);
      final before = world.setup.revision;
      final l10n = _l10n(tester);
      expect(
        tester.widget<ModuleStatePill>(find.byKey(GoalsModuleKeys.state)).on,
        isTrue,
      );

      await _tap(tester, GoalsModuleKeys.toggle);

      final pill = tester.widget<ModuleStatePill>(
        find.byKey(GoalsModuleKeys.state),
      );
      expect(pill.on, isFalse);
      expect(pill.label, l10n.modulesOff);
      expect(await world.container.read(enabledModulesProvider.future), {
        ModuleId.body,
      });
      expect(world.spy.clearCalls, 0);
      expect(await world.memory.count(), 5);
      expect(world.setup.revision, before);
    });

    testWidgets('switching off and on again keeps every row', (tester) async {
      final world = await _world();
      await _pump(tester, world);

      await _tap(tester, GoalsModuleKeys.toggle);
      await _tap(tester, GoalsModuleKeys.toggle);

      expect(await world.memory.count(), 5);
      expect(world.spy.clearCalls, 0);
    });

    testWidgets('with Goals off and rows kept the kept card shows', (
      tester,
    ) async {
      final world = await _world(on: false);
      await _pump(tester, world);

      expect(find.byKey(GoalsModuleKeys.kept), findsOneWidget);
    });

    testWidgets('with Goals on there is no kept card', (tester) async {
      final world = await _world();
      await _pump(tester, world);

      expect(find.byKey(GoalsModuleKeys.kept), findsNothing);
    });
  });

  group('4. the way to the goal', () {
    testWidgets('with Goals on the Your goal tile opens the no-goal screen', (
      tester,
    ) async {
      final world = await _world(goal: false, screenings: 0);
      await _pump(tester, world);

      await _tap(tester, GoalsModuleKeys.goal);

      expect(find.byType(GoalScreen), findsOneWidget);
      expect(find.byKey(GoalScreenKeys.noGoal), findsOneWidget);
    });

    testWidgets('with Goals off there is no Your goal tile', (tester) async {
      final world = await _world(on: false, goal: false, screenings: 0);
      await _pump(tester, world);

      expect(find.byKey(GoalsModuleKeys.goal), findsNothing);
    });

    testWidgets('the turned on message offers View, which opens the goal', (
      tester,
    ) async {
      final world = await _world(on: false, goal: false, screenings: 0);
      final router = await _pump(tester, world);

      await _tap(tester, GoalsModuleKeys.toggle);
      await tester.tap(find.text(_l10n(tester).modulesView));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, AppPaths.goals);
      expect(find.byKey(GoalScreenKeys.noGoal), findsOneWidget);
    });

    testWidgets('nothing navigates by itself on switching on', (tester) async {
      final world = await _world(on: false, goal: false, screenings: 0);
      final router = await _pump(tester, world);

      await _tap(tester, GoalsModuleKeys.toggle);

      expect(
        router.routeInformationProvider.value.uri.path,
        AppPaths.settingsModuleGoals,
      );
      expect(find.byType(GoalScreen), findsNothing);
    });
  });

  group('5. the soft mode exit card', () {
    testWidgets('shows with Goals on and a yes, above the data section', (
      tester,
    ) async {
      final world = await _world();
      await _pump(tester, world);

      expect(find.byKey(SoftModeExitKeys.leave), findsOneWidget);
      final card = tester.getTopLeft(find.byKey(SoftModeExitKeys.leave));
      final data = tester.getTopLeft(find.byKey(GoalsModuleKeys.stored));
      expect(card.dy, lessThan(data.dy));
    });

    testWidgets('hides with Goals off, whatever the stored answer', (
      tester,
    ) async {
      final world = await _world(on: false);
      await _pump(tester, world);

      expect(find.byKey(SoftModeExitKeys.leave), findsNothing);
    });

    testWidgets('hides when the newest answer is a no', (tester) async {
      final world = await _world(goal: false, soft: false);
      await _pump(tester, world);

      expect(find.byKey(SoftModeExitKeys.leave), findsNothing);
    });

    testWidgets('hides when the newest answer is a no after an older yes', (
      tester,
    ) async {
      final world = await _world(goal: false);
      await world.memory.addScreening(
        GoalScreening(
          on: goalDay(12, 5),
          softMode: false,
          pregnantOrBreastfeeding: null,
        ),
      );
      await _pump(tester, world);

      expect(find.byKey(SoftModeExitKeys.leave), findsNothing);
    });

    testWidgets('hides with no answer stored', (tester) async {
      final world = await _world(goal: false, screenings: 0);
      await _pump(tester, world);

      expect(find.byKey(SoftModeExitKeys.leave), findsNothing);
    });

    testWidgets('shows when an older no is followed by a yes', (tester) async {
      final world = await _world(goal: false, soft: false);
      await world.memory.addScreening(
        GoalScreening(
          on: goalDay(12, 5),
          softMode: true,
          pregnantOrBreastfeeding: null,
        ),
      );
      await _pump(tester, world);

      expect(find.byKey(SoftModeExitKeys.leave), findsOneWidget);
    });
  });

  group('6. the count line', () {
    testWidgets('0 rows shows the empty line and no button', (tester) async {
      final world = await _world(goal: false, screenings: 0);
      await _pump(tester, world);
      final l10n = _l10n(tester);

      expect(_storedLine(tester), l10n.moduleGoalsDataEmpty);
      expect(find.byKey(GoalsModuleKeys.delete), findsNothing);
    });

    testWidgets('1 goal, 3 weeks and 1 screening show counts and sentence', (
      tester,
    ) async {
      final world = await _world();
      await _pump(tester, world);
      final l10n = _l10n(tester);

      final line = _storedLine(tester);
      expect(line, contains(l10n.moduleGoalsDataCount(1, 3)));
      expect(line, contains(l10n.moduleGoalsDataScreening));
      expect(
        line,
        goalsDataLine(
          l10n,
          const GoalsDataCount(goals: 1, reviews: 3, screenings: 1),
        ),
      );
      expect(find.byKey(GoalsModuleKeys.delete), findsOneWidget);
    });

    testWidgets('screenings only show the screening sentence alone', (
      tester,
    ) async {
      final world = await _world(goal: false);
      await _pump(tester, world);
      final l10n = _l10n(tester);

      expect(_storedLine(tester), l10n.moduleGoalsDataScreening);
      expect(find.byKey(GoalsModuleKeys.delete), findsOneWidget);
    });

    testWidgets('a goal with no review shows 0 reviews and no sentence', (
      tester,
    ) async {
      final world = await _world(weeks: 0, screenings: 0);
      await _pump(tester, world);
      final l10n = _l10n(tester);

      expect(_storedLine(tester), l10n.moduleGoalsDataCount(1, 0));
      expect(find.byKey(GoalsModuleKeys.delete), findsOneWidget);
    });

    testWidgets('a count that cannot be read is not shown as empty', (
      tester,
    ) async {
      final world = await _world();
      final failing = _FailingReads(world.memory);
      final setup = await setupPicker(
        store: world.memory,
        readStoreOf: (_) => failing,
      );
      await _pump(tester, _World(setup, world.memory, world.spy));
      final l10n = _l10n(tester);

      expect(find.byKey(GoalsModuleKeys.delete), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(GoalsModuleKeys.stored),
          matching: find.text(l10n.moduleGoalsDataEmpty),
        ),
        findsNothing,
      );
    });
  });

  group('7. cancel and confirm', () {
    testWidgets('the dialog opens with a cancel and a confirm', (tester) async {
      final world = await _world();
      await _pump(tester, world);

      await _openDialog(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(GoalsModuleKeys.deleteCancel), findsOneWidget);
      expect(find.byKey(GoalsModuleKeys.deleteConfirm), findsOneWidget);
    });

    testWidgets('cancel deletes nothing and writes nothing', (tester) async {
      final world = await _world();
      await _pump(tester, world);
      await _openDialog(tester);
      final before = world.setup.revision;

      await _tap(tester, GoalsModuleKeys.deleteCancel);

      expect(find.byType(AlertDialog), findsNothing);
      expect(world.spy.clearCalls, 0);
      expect(await world.memory.count(), 5);
      expect(world.setup.revision, before);
      expect(find.byKey(GoalsModuleKeys.delete), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('confirm empties the three tables and bumps the revision', (
      tester,
    ) async {
      final world = await _world();
      await _pump(tester, world);
      await _openDialog(tester);
      final before = world.setup.revision;

      await _confirm(tester);

      expect(world.spy.clearCalls, 1);
      expect(await world.memory.goals(), isEmpty);
      expect(await world.memory.weeks(1), isEmpty);
      expect(await world.memory.screenings(), isEmpty);
      expect(world.setup.revision, before + 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('afterwards the line is empty and the button is gone', (
      tester,
    ) async {
      final world = await _world();
      await _pump(tester, world);
      await _openDialog(tester);

      await _confirm(tester);

      expect(_storedLine(tester), _l10n(tester).moduleGoalsDataEmpty);
      expect(find.byKey(GoalsModuleKeys.delete), findsNothing);
    });

    testWidgets('the Today card hides and soft mode resets', (tester) async {
      final world = await _world();
      await _pump(tester, world);
      expect(await world.container.read(softModeProvider.future), isTrue);
      expect(
        await world.container.read(goalWeekProvider.future),
        isNot(isA<GoalWeekNoGoal>()),
      );
      await _openDialog(tester);

      await _confirm(tester);

      expect(
        await world.container.read(goalWeekProvider.future),
        isA<GoalWeekNoGoal>(),
      );
      expect(await world.container.read(activeGoalProvider.future), isNull);
      expect(await world.container.read(softModeProvider.future), isNull);
      expect(find.byKey(SoftModeExitKeys.leave), findsNothing);
    });

    testWidgets('deleting a stored yes ends soft mode', (tester) async {
      final world = await _world(goal: false);
      await _pump(tester, world);
      expect(find.byKey(SoftModeExitKeys.leave), findsOneWidget);
      await _openDialog(tester);

      await _confirm(tester);

      expect(await world.container.read(softModeProvider.future), isNull);
      expect(find.byKey(SoftModeExitKeys.leave), findsNothing);
    });

    testWidgets('a goal whose plan raised the step goal leaves it raised', (
      tester,
    ) async {
      final memory = InMemoryGoalStore();
      await seedGoalsData(memory);
      final setup = await setupPicker(
        store: memory,
        profile: const UserProfile(
          heightCentimeters: 178,
          dailyStepGoal: 10000,
        ),
      );
      await _pump(tester, _World(setup, memory, SpyGoalStore(memory)));

      await _openDialog(tester);
      await _confirm(tester);

      expect(await memory.count(), 0);
      final profile = await setup.container.read(userProfileProvider.future);
      expect(profile?.dailyStepGoal, 10000);
    });
  });

  group('8. delete with Goals off and in demo mode', () {
    testWidgets('works with Goals off and leaves it off', (tester) async {
      final world = await _world(on: false);
      await _pump(tester, world);

      await _openDialog(tester);
      await _confirm(tester);

      expect(await world.memory.count(), 0);
      expect(await world.container.read(enabledModulesProvider.future), {
        ModuleId.body,
      });
      expect(
        tester.widget<ModuleStatePill>(find.byKey(GoalsModuleKeys.state)).on,
        isFalse,
      );
      expect(find.byKey(GoalsModuleKeys.kept), findsNothing);
    });

    testWidgets('with Goals on it leaves Goals on', (tester) async {
      final world = await _world();
      await _pump(tester, world);

      await _openDialog(tester);
      await _confirm(tester);

      expect(await world.container.read(enabledModulesProvider.future), {
        ModuleId.body,
        ModuleId.goals,
      });
      expect(
        tester.widget<ModuleStatePill>(find.byKey(GoalsModuleKeys.state)).on,
        isTrue,
      );
    });

    testWidgets('is allowed in demo mode', (tester) async {
      final world = await _world(demo: true);
      await _pump(tester, world);

      await _openDialog(tester);
      await _confirm(tester);

      expect(world.spy.clearCalls, 1);
      expect(await world.memory.count(), 0);
    });
  });

  group('9. a store that throws, and two taps', () {
    testWidgets('keeps every row, says it failed and logs it', (tester) async {
      final world = await _world();
      world.spy.clearFailure = StateError('disk');
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      addTearDown(() => debugPrint = original);
      await _pump(tester, world);
      await _openDialog(tester);

      await _confirm(tester);

      expect(world.spy.clearCalls, 1);
      expect(await world.memory.count(), 5);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(logs.join('\n'), contains('disk'));
      expect(find.byKey(GoalsModuleKeys.delete), findsOneWidget);
      final line = _storedLine(tester);
      expect(line, isNot(_l10n(tester).moduleGoalsDataEmpty));
    });

    testWidgets('the failure message differs from the success message', (
      tester,
    ) async {
      final world = await _world();
      world.spy.clearFailure = StateError('disk');
      await _pump(tester, world);
      await _openDialog(tester);
      await _confirm(tester);
      final failed = _snackText(tester);
      expect(failed, isNotEmpty);
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
          .clearSnackBars();
      await tester.pumpAndSettle();

      world.spy.clearFailure = null;
      await _openDialog(tester);
      await _confirm(tester);

      expect(await world.memory.count(), 0);
      expect(_snackText(tester), isNotEmpty);
      expect(_snackText(tester), isNot(failed));
    });

    testWidgets('two taps on confirm cause one clear', (tester) async {
      final world = await _world();
      final gate = Completer<void>();
      world.spy.clearGate = gate;
      await _pump(tester, world);
      await _openDialog(tester);

      await tester.tap(find.byKey(GoalsModuleKeys.deleteConfirm));
      await tester.tap(
        find.byKey(GoalsModuleKeys.deleteConfirm),
        warnIfMissed: false,
      );
      gate.complete();
      await tester.pumpAndSettle();

      expect(world.spy.clearCalls, 1);
      expect(await world.memory.count(), 0);
    });
  });

  group('12. layout', () {
    for (final locale in AppLocales.supported) {
      for (final scale in layoutScales) {
        for (final brightness in Brightness.values) {
          final name = '$locale ${scale}x ${brightness.name}';

          testWidgets('fits on, with the card: $name', (tester) async {
            final world = await _world();
            await _pump(
              tester,
              world,
              locale: locale,
              scale: scale,
              brightness: brightness,
              size: phoneSize,
            );
            await scrollThrough(tester);

            expect(find.byType(GoalsModuleScreen), findsOneWidget);
          });

          testWidgets('fits off, with the data kept: $name', (tester) async {
            final world = await _world(on: false);
            await _pump(
              tester,
              world,
              locale: locale,
              scale: scale,
              brightness: brightness,
              size: phoneSize,
            );
            await scrollThrough(tester);

            expect(find.byType(GoalsModuleScreen), findsOneWidget);
          });

          testWidgets('fits the delete dialog: $name', (tester) async {
            final world = await _world();
            await _pump(
              tester,
              world,
              locale: locale,
              scale: scale,
              brightness: brightness,
              size: phoneSize,
            );
            await scrollThrough(tester);
            await _toTop(tester);
            await tester.scrollUntilVisible(
              find.byKey(GoalsModuleKeys.delete),
              400,
              scrollable: find.byType(Scrollable).first,
              maxScrolls: 200,
            );
            await tester.ensureVisible(find.byKey(GoalsModuleKeys.delete));
            await tester.pumpAndSettle();
            await expectNoLayoutOverflow(() async {
              await tester.tap(find.byKey(GoalsModuleKeys.delete));
              await tester.pumpAndSettle();
            });

            expect(find.byKey(GoalsModuleKeys.deleteConfirm), findsOneWidget);
          });
        }
      }
    }
  });
}

/// A store whose reads fail, as a disk that cannot be read does.
final class _FailingReads implements GoalStore {
  new(this.inner);

  final InMemoryGoalStore inner;

  @override
  Future<List<Goal>> goals() async => throw StateError('disk');

  @override
  Future<Goal?> active() async => throw StateError('disk');

  @override
  Future<List<GoalScreening>> screenings() async => throw StateError('disk');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected: ${invocation.memberName}');
}
