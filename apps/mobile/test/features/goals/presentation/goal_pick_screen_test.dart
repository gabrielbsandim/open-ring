import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';
import 'package:open_ring/features/goals/presentation/goal_pick_screen.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

import '../../../helpers/layout_harness.dart';
import '../goal_draft_fixture.dart';
import '../goal_fixtures.dart';
import '../goal_picker_harness.dart';

const Set<ModuleId> _bodyOff = {ModuleId.goals};
const Set<ModuleId> _goalsOff = {ModuleId.body};
const _today = '/today';

String get _pick => AppPaths.goalsPick;

Future<void> _continue(WidgetTester tester) =>
    tapKey(tester, GoalPickKeys.continueButton);

void main() {
  group('the rows', () {
    testWidgets('list the four choices and the lead', (tester) async {
      final setup = await setupPicker();
      await pumpGoals(tester, setup, at: _pick);

      final l10n = l10nOf(tester, GoalPickScreen);
      for (final text in [
        l10n.goalsPickTitle,
        l10n.goalsPickLead,
        l10n.goalsPickNone,
        l10n.goalsPickNoneDetail,
        l10n.goalsPickLoseFat,
        l10n.goalsPickLoseFatDetail,
        l10n.goalsPickGetFitter,
        l10n.goalsPickGetFitterDetail,
        l10n.goalsPickSleepBetter,
        l10n.goalsPickSleepBetterDetail,
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
    });

    testWidgets('Lose fat says it uses the weigh-ins with Body on', (
      tester,
    ) async {
      final setup = await setupPicker();
      await pumpGoals(tester, setup, at: _pick);

      final l10n = l10nOf(tester, GoalPickScreen);
      expect(find.text(l10n.goalsPickUsesBody), findsOneWidget);
      expect(find.text(l10n.goalsPickNeedsBody), findsNothing);
    });

    testWidgets('the notes follow the selection', (tester) async {
      final setup = await setupPicker();
      await pumpGoals(tester, setup, at: _pick);
      final l10n = l10nOf(tester, GoalPickScreen);

      expect(find.text(l10n.goalsPickNoteNone), findsOneWidget);

      await tapKey(tester, GoalPickKeys.getFitter);
      expect(find.text(l10n.goalsPickNoteOther), findsOneWidget);
      expect(find.text(l10n.goalsPickNoteNone), findsNothing);
    });
  });

  group('Continue with No goal', () {
    testWidgets('writes nothing and goes to Today', (tester) async {
      final setup = await setupPicker();
      final router = await pumpGoals(tester, setup, at: _pick);

      await _continue(tester);

      expect(whereIs(router), _today);
      expect(find.text(todayStub), findsOneWidget);
      expect(await setup.store.goals(), isEmpty);
      expect(setup.revision, 0);
    });

    testWidgets('is the default, also when the screen is asked for none', (
      tester,
    ) async {
      final setup = await setupPicker();
      await pumpGoals(tester, setup, at: AppPaths.goalsPickWith(null));

      final l10n = l10nOf(tester, GoalPickScreen);
      expect(find.text(l10n.goalsPickNoteNone), findsOneWidget);
      expect(
        buttonOf(tester, GoalPickKeys.continueButton).onPressed,
        isNotNull,
      );
    });
  });

  group('Continue with Get fitter or Sleep better', () {
    testWidgets('Get fitter starts one goal and goes to Today', (tester) async {
      final setup = await setupPicker();
      final router = await pumpGoals(tester, setup, at: _pick);

      await tapKey(tester, GoalPickKeys.getFitter);
      await _continue(tester);

      final goals = await setup.store.goals();
      expect(goals, hasLength(1));
      expect(goals.single.kind, GoalKind.getFitter);
      expect(goals.single.levers, isEmpty);
      expect(whereIs(router), _today);
    });

    testWidgets('Sleep better starts one goal and goes to Today', (
      tester,
    ) async {
      final setup = await setupPicker();
      final router = await pumpGoals(tester, setup, at: _pick);

      await tapKey(tester, GoalPickKeys.sleepBetter);
      await _continue(tester);

      final goals = await setup.store.goals();
      expect(goals.single.kind, GoalKind.sleepBetter);
      expect(whereIs(router), _today);
    });

    testWidgets('an initial kind is the selection', (tester) async {
      final setup = await setupPicker();
      final router = await pumpGoals(
        tester,
        setup,
        at: AppPaths.goalsPickWith(GoalKind.sleepBetter),
      );

      await _continue(tester);

      final goals = await setup.store.goals();
      expect(goals.single.kind, GoalKind.sleepBetter);
      expect(whereIs(router), _today);
    });

    testWidgets('Today is not reached before the start has been awaited', (
      tester,
    ) async {
      final gate = Completer<void>();
      final setup = await setupPicker(
        readStoreOf: (memory) => ProbeGoalStore(memory, gate: gate),
      );
      final router = await pumpGoals(tester, setup, at: _pick);
      await tapKey(tester, GoalPickKeys.getFitter);

      await tester.tap(find.byKey(GoalPickKeys.continueButton));
      await tester.pump();

      expect(whereIs(router), _pick);
      expect(setup.revision, 0);

      gate.complete();
      await tester.pumpAndSettle();

      expect(whereIs(router), _today);
      expect(setup.revision, 1);
    });

    testWidgets('4. two taps on Continue leave one goal', (tester) async {
      final gate = Completer<void>();
      final setup = await setupPicker(
        readStoreOf: (memory) => ProbeGoalStore(memory, gate: gate),
      );
      await pumpGoals(tester, setup, at: _pick);
      await tapKey(tester, GoalPickKeys.getFitter);

      await tester.tap(find.byKey(GoalPickKeys.continueButton));
      await tester.pump();
      expect(buttonOf(tester, GoalPickKeys.continueButton).onPressed, isNull);
      await tester.tap(
        find.byKey(GoalPickKeys.continueButton),
        warnIfMissed: false,
      );
      gate.complete();
      await tester.pumpAndSettle();

      expect(await setup.store.goals(), hasLength(1));
      expect(setup.revision, 1);
    });

    testWidgets('a start that comes back null shows the active state', (
      tester,
    ) async {
      final setup = await setupPicker(
        readStoreOf: (memory) => ProbeGoalStore(memory, startsNull: true),
      );
      final router = await pumpGoals(tester, setup, at: _pick);
      await tapKey(tester, GoalPickKeys.getFitter);

      await _continue(tester);

      final l10n = l10nOf(tester, GoalPickScreen);
      expect(find.text(l10n.goalsPickActive), findsOneWidget);
      expect(find.byKey(GoalPickKeys.continueButton), findsNothing);
      expect(whereIs(router), _pick);
      expect(setup.revision, 0);
    });

    testWidgets('a store error says so, stays here and can be retried', (
      tester,
    ) async {
      final setup = await setupPicker(
        readStoreOf: (memory) =>
            ProbeGoalStore(memory, startError: StateError('disk full')),
      );
      final router = await pumpGoals(tester, setup, at: _pick);
      await tapKey(tester, GoalPickKeys.getFitter);

      await _continue(tester);

      final l10n = l10nOf(tester, GoalPickScreen);
      expect(find.text(l10n.goalsStartFailed), findsOneWidget);
      expect(whereIs(router), _pick);
      expect(
        buttonOf(tester, GoalPickKeys.continueButton).onPressed,
        isNotNull,
      );
    });
  });

  group('5. an active goal', () {
    testWidgets('shows only the active line, with no rows and no Continue', (
      tester,
    ) async {
      final setup = await setupPicker(draft: draftD);
      await pumpGoals(tester, setup, at: _pick);

      final l10n = l10nOf(tester, GoalPickScreen);
      expect(find.text(l10n.goalsPickActive), findsOneWidget);
      expect(find.byKey(GoalPickKeys.continueButton), findsNothing);
      for (final key in [
        GoalPickKeys.none,
        GoalPickKeys.loseFat,
        GoalPickKeys.getFitter,
        GoalPickKeys.sleepBetter,
      ]) {
        expect(find.byKey(key), findsNothing);
      }
    });

    testWidgets('a goal that cannot be read shows the load error', (
      tester,
    ) async {
      final setup = await setupPicker(
        readStoreOf: (memory) =>
            ProbeGoalStore(memory, activeError: StateError('read')),
      );
      await pumpGoals(tester, setup, at: _pick);

      final l10n = l10nOf(tester, GoalPickScreen);
      expect(find.text(l10n.metricLoadError), findsOneWidget);
      expect(find.byKey(GoalPickKeys.continueButton), findsNothing);
    });
  });

  group('Lose fat is blocked and the refusal is pushed', () {
    final cases =
        <String, ({UserProfile profile, double trend, IntakeBlock block})>{
          'under18 for a birth year of 2008': (
            profile: const UserProfile(birthYear: 2008, heightCentimeters: 178),
            trend: 70,
            block: IntakeBlock.under18,
          ),
          'ageMissing without a birth year': (
            profile: const UserProfile(heightCentimeters: 178),
            trend: 70,
            block: IntakeBlock.ageMissing,
          ),
          'heightMissing without a height': (
            profile: const UserProfile(birthYear: 1990),
            trend: 70,
            block: IntakeBlock.heightMissing,
          ),
          'bmiUnderFloor for a trend of 57.9 kg at 178 cm': (
            profile: okProfile,
            trend: 57.9,
            block: IntakeBlock.bmiUnderFloor,
          ),
        };
    for (final MapEntry(key: name, value: facts) in cases.entries) {
      testWidgets(name, (tester) async {
        final setup = await setupPicker(
          profile: facts.profile,
          trendKg: facts.trend,
        );
        final router = await pumpGoals(tester, setup, at: _pick);
        await tapKey(tester, GoalPickKeys.loseFat);

        await _continue(tester);

        expect(whereIs(router), AppPaths.goalsRefusedFor(facts.block));
        expect(await setup.store.goals(), isEmpty);
      });
    }

    testWidgets('a stored soft mode disables Continue', (tester) async {
      final setup = await setupPicker();
      await setup.store.addScreening(
        GoalScreening(
          on: goalDay(12, 1),
          softMode: true,
          pregnantOrBreastfeeding: null,
        ),
      );
      final router = await pumpGoals(tester, setup, at: _pick);

      await tapKey(tester, GoalPickKeys.loseFat);

      expect(buttonOf(tester, GoalPickKeys.continueButton).onPressed, isNull);
      expect(whereIs(router), _pick);
    });
  });

  group('Lose fat that passes waits for the weight steps', () {
    testWidgets('Continue is disabled and the five questions are announced', (
      tester,
    ) async {
      final setup = await setupPicker();
      final router = await pumpGoals(tester, setup, at: _pick);

      await tapKey(tester, GoalPickKeys.loseFat);

      final l10n = l10nOf(tester, GoalPickScreen);
      expect(buttonOf(tester, GoalPickKeys.continueButton).onPressed, isNull);
      expect(find.text(l10n.goalsPickNoteWeight), findsOneWidget);
      expect(whereIs(router), _pick);
    });

    testWidgets('a birth year of 2007 passes the age check', (tester) async {
      final setup = await setupPicker(
        profile: const UserProfile(birthYear: 2007, heightCentimeters: 178),
      );
      await pumpGoals(tester, setup, at: _pick);

      await tapKey(tester, GoalPickKeys.loseFat);

      final l10n = l10nOf(tester, GoalPickScreen);
      expect(find.text(l10n.goalsPickNoteWeight), findsOneWidget);
    });

    testWidgets('with the questions answered the note is gone', (tester) async {
      final setup = await setupPicker();
      await setup.store.addScreening(
        GoalScreening(
          on: goalDay(12, 1),
          softMode: false,
          pregnantOrBreastfeeding: null,
        ),
      );
      await pumpGoals(tester, setup, at: _pick);

      await tapKey(tester, GoalPickKeys.loseFat);

      final l10n = l10nOf(tester, GoalPickScreen);
      expect(buttonOf(tester, GoalPickKeys.continueButton).onPressed, isNull);
      expect(find.text(l10n.goalsPickNoteWeight), findsNothing);
    });
  });

  group('the facts of the intake are not ready', () {
    testWidgets('a trend that fails disables only the Lose fat Continue', (
      tester,
    ) async {
      final setup = await setupPicker(trendFails: true);
      await pumpGoals(tester, setup, at: _pick);

      await tapKey(tester, GoalPickKeys.getFitter);
      expect(
        buttonOf(tester, GoalPickKeys.continueButton).onPressed,
        isNotNull,
      );

      await tapKey(tester, GoalPickKeys.loseFat);
      expect(buttonOf(tester, GoalPickKeys.continueButton).onPressed, isNull);
    });
  });

  group('9. Body off', () {
    testWidgets('Lose fat is dimmed but still selectable', (tester) async {
      final setup = await setupPicker(modules: _bodyOff);
      await pumpGoals(tester, setup, at: _pick);

      final l10n = l10nOf(tester, GoalPickScreen);
      expect(find.text(l10n.goalsPickNeedsBody), findsOneWidget);
      expect(find.text(l10n.goalsPickUsesBody), findsNothing);

      await tapKey(tester, GoalPickKeys.loseFat);
      expect(
        find.descendant(
          of: find.byKey(GoalPickKeys.continueButton),
          matching: find.text(l10n.goalsPickOpenBody),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Open the Body module goes to the Body module settings', (
      tester,
    ) async {
      final setup = await setupPicker(modules: _bodyOff);
      final router = await pumpGoals(tester, setup, at: _pick);
      await tapKey(tester, GoalPickKeys.loseFat);

      await _continue(tester);

      expect(whereIs(router), AppPaths.settingsModuleBody);
      expect(whereIs(router), '/ring/settings/modules/body');
      expect(find.text(bodyModuleStub), findsOneWidget);
    });

    testWidgets('Get fitter still starts with Body off', (tester) async {
      final setup = await setupPicker(modules: _bodyOff);
      final router = await pumpGoals(tester, setup, at: _pick);
      await tapKey(tester, GoalPickKeys.getFitter);

      await _continue(tester);

      expect(await setup.store.goals(), hasLength(1));
      expect(whereIs(router), _today);
    });
  });

  group('10. the gate is off', () {
    testWidgets('the picker is an empty page with the title only', (
      tester,
    ) async {
      final setup = await setupPicker(modules: _goalsOff);
      await pumpGoals(tester, setup, at: _pick);

      final l10n = l10nOf(tester, GoalPickScreen);
      expect(find.text(l10n.goalsPickTitle), findsOneWidget);
      expect(find.text(l10n.goalsPickLead), findsNothing);
      expect(find.byKey(GoalPickKeys.continueButton), findsNothing);
      expect(find.byKey(GoalPickKeys.getFitter), findsNothing);
      expect(find.byKey(GoalPickKeys.none), findsNothing);
    });
  });

  group('11. layout', () {
    final states = <String, Future<GoalSetup> Function()>{
      'No goal selected': setupPicker,
      'Body off': () => setupPicker(modules: _bodyOff),
      'an active goal': () => setupPicker(draft: draftD),
    };
    for (final scale in layoutScales) {
      for (final brightness in layoutBrightnesses) {
        for (final MapEntry(key: name, value: build) in states.entries) {
          testWidgets('$name at ${scale}x ${brightness.name}', (tester) async {
            final setup = await build();
            await pumpGoals(
              tester,
              setup,
              at: _pick,
              scale: scale,
              brightness: brightness,
            );

            expect(find.byType(GoalPickScreen), findsOneWidget);
          });
        }

        testWidgets('Lose fat selected at ${scale}x ${brightness.name}', (
          tester,
        ) async {
          final setup = await setupPicker(modules: _bodyOff);
          await pumpGoals(
            tester,
            setup,
            at: AppPaths.goalsPickWith(GoalKind.loseFat),
            scale: scale,
            brightness: brightness,
          );
          await tester.scrollUntilVisible(
            find.byKey(GoalPickKeys.continueButton),
            200,
          );

          expect(find.byKey(GoalPickKeys.continueButton), findsOneWidget);
        });
      }
    }
  });
}
