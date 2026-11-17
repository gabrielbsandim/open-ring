import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';
import 'package:open_ring/features/goals/presentation/goal_pick_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_refusal_screen.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

import '../../../helpers/layout_harness.dart';
import '../goal_fixtures.dart';
import '../goal_picker_harness.dart';

const _minor = UserProfile(birthYear: 2008, heightCentimeters: 178);

Future<GoRouter> _open(
  WidgetTester tester,
  GoalSetup setup,
  IntakeBlock block, {
  double scale = 1,
  Brightness brightness = Brightness.dark,
}) => pumpGoals(
  tester,
  setup,
  at: AppPaths.goalsRefusedFor(block),
  scale: scale,
  brightness: brightness,
);

const _softTitle = 'The app goes on without a weight goal';
const _softBody1 =
    'From your answers, the app will not build a weight goal. This is not a diagnosis.';
const _softBody2 =
    'If food or weight is taking up too much of your thoughts, help exists. A health professional is the place to start.';
const _softRule =
    'Two or more yes answers to the five questions turn the soft mode on.';
const _softFactsTitle = 'What changes in soft mode';
const _softFact1 = 'No goal to lose, gain or keep weight.';
const _softFact2 = 'No pace, no target and no estimated arrival.';
const _softFact3 = 'Get fitter and Sleep better stay available.';

Future<void> _store(GoalSetup setup, {required bool soft}) =>
    setup.store.addScreening(
      GoalScreening(
        on: goalDay(12, 1),
        softMode: soft,
        pregnantOrBreastfeeding: null,
      ),
    );

Future<GoalSetup> _softSetup() async {
  final setup = await setupPicker();
  await _store(setup, soft: true);
  return setup;
}

void main() {
  group('6. under18', () {
    testWidgets('a birth year of 2008 shows 18 and the year 2027', (
      tester,
    ) async {
      final setup = await setupPicker(profile: _minor);
      await _open(tester, setup, IntakeBlock.under18);

      final l10n = l10nOf(tester, GoalRefusalScreen);
      expect(find.text(l10n.goalsUnder18Title), findsOneWidget);
      expect(find.textContaining('you turn 18 this year'), findsOneWidget);
      expect(find.textContaining('1 January 2027'), findsOneWidget);
      expect(find.text(l10n.goalsUnder18Body2), findsOneWidget);
      expect(find.textContaining(l10n.goalsRefusalRule), findsWidgets);
      expect(find.text(l10n.goalsRefusalFoot), findsOneWidget);
    });

    testWidgets('a birth year of 2009 shows 17 and the year 2028', (
      tester,
    ) async {
      final setup = await setupPicker(
        profile: const UserProfile(birthYear: 2009, heightCentimeters: 178),
      );
      await _open(tester, setup, IntakeBlock.under18);

      expect(find.textContaining('you turn 17 this year'), findsOneWidget);
      expect(find.textContaining('1 January 2028'), findsOneWidget);
    });

    testWidgets('See the goals without weight opens the picker on Get fitter', (
      tester,
    ) async {
      final setup = await setupPicker(profile: _minor);
      final router = await _open(tester, setup, IntakeBlock.under18);
      final l10n = l10nOf(tester, GoalRefusalScreen);

      await tapKey(tester, GoalRefusalKeys.primary);

      expect(l10n.goalsRefusalSeeNoWeight, isNotEmpty);
      expect(whereIs(router), AppPaths.goalsPickWith(GoalKind.getFitter));
    });

    testWidgets('Continue without a goal goes to Today', (tester) async {
      final setup = await setupPicker(profile: _minor);
      final router = await _open(tester, setup, IntakeBlock.under18);

      await tapKey(tester, GoalRefusalKeys.secondary);

      expect(whereIs(router), '/today');
      expect(await setup.store.goals(), isEmpty);
    });

    testWidgets('the buttons carry their labels', (tester) async {
      final setup = await setupPicker(profile: _minor);
      await _open(tester, setup, IntakeBlock.under18);

      final l10n = l10nOf(tester, GoalRefusalScreen);
      expect(
        find.descendant(
          of: find.byKey(GoalRefusalKeys.primary),
          matching: find.text(l10n.goalsRefusalSeeNoWeight),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(GoalRefusalKeys.secondary),
          matching: find.text(l10n.goalsPickContinueNone),
        ),
        findsOneWidget,
      );
    });
  });

  group('7. the profile is missing something', () {
    final cases = <String, UserProfile?>{
      'age 30 with the height null': const UserProfile(birthYear: 1996),
      'the age null': const UserProfile(heightCentimeters: 178),
      'both null': null,
    };
    for (final MapEntry(key: name, value: profile) in cases.entries) {
      testWidgets('$name shows the profile state', (tester) async {
        final setup = await setupPicker(profile: profile);
        final block = profile?.birthYear == null
            ? IntakeBlock.ageMissing
            : IntakeBlock.heightMissing;
        await _open(tester, setup, block);

        final l10n = l10nOf(tester, GoalRefusalScreen);
        expect(find.text(l10n.goalsProfileTitle), findsOneWidget);
        expect(find.text(l10n.goalsProfileBody), findsOneWidget);
        expect(find.text(l10n.goalsRefusalFoot), findsOneWidget);
      });
    }

    testWidgets('both blocks show the same state', (tester) async {
      final setup = await setupPicker(profile: const UserProfile());
      await _open(tester, setup, IntakeBlock.ageMissing);
      final first = allText(tester);

      await _open(tester, setup, IntakeBlock.heightMissing);

      expect(allText(tester), first);
    });

    testWidgets('Open Settings goes to /ring/settings', (tester) async {
      final setup = await setupPicker(
        profile: const UserProfile(birthYear: 1996),
      );
      final router = await _open(tester, setup, IntakeBlock.heightMissing);

      await tapKey(tester, GoalRefusalKeys.primary);

      expect(whereIs(router), '/ring/settings');
      expect(find.text(settingsStub), findsOneWidget);
    });

    testWidgets('the second button goes to the picker', (tester) async {
      final setup = await setupPicker(
        profile: const UserProfile(birthYear: 1996),
      );
      final router = await _open(tester, setup, IntakeBlock.heightMissing);

      await tapKey(tester, GoalRefusalKeys.secondary);

      expect(Uri.parse(whereIs(router)).path, AppPaths.goalsPick);
    });
  });

  group('8. the BMI is under the floor', () {
    testWidgets('57.9 kg at 178 cm shows the trend, height, BMI and floor', (
      tester,
    ) async {
      final setup = await setupPicker(trendKg: 57.9);
      await _open(tester, setup, IntakeBlock.bmiUnderFloor);

      final l10n = l10nOf(tester, GoalRefusalScreen);
      expect(find.text(l10n.goalsBmiTitle), findsOneWidget);
      expect(find.textContaining('57.9 kg'), findsOneWidget);
      expect(find.textContaining('178 cm'), findsOneWidget);
      expect(find.textContaining('BMI 18.3'), findsOneWidget);
      expect(find.textContaining('58.7 kg'), findsOneWidget);
      expect(find.text(l10n.goalsBmiBody2), findsOneWidget);
    });

    testWidgets('a 58.6 kg trend is not read as 58.5 and shows BMI 18.4', (
      tester,
    ) async {
      final setup = await setupPicker(trendKg: 58.6);
      await _open(tester, setup, IntakeBlock.bmiUnderFloor);

      expect(find.textContaining('58.6 kg'), findsOneWidget);
      expect(find.textContaining('BMI 18.4'), findsOneWidget);
      expect(find.textContaining('58.7 kg'), findsOneWidget);
    });

    testWidgets('a floor that is exact, 74.0 kg at 200 cm, stays 74.0', (
      tester,
    ) async {
      final setup = await setupPicker(
        profile: const UserProfile(birthYear: 1990, heightCentimeters: 200),
        trendKg: 73.9,
      );
      await _open(tester, setup, IntakeBlock.bmiUnderFloor);

      expect(find.textContaining('73.9 kg'), findsOneWidget);
      expect(find.textContaining('200 cm'), findsOneWidget);
      expect(find.textContaining('74.0 kg'), findsOneWidget);
      expect(find.textContaining('BMI 18.4'), findsOneWidget);
    });

    testWidgets('imperial shows pounds, feet and inches', (tester) async {
      final setup = await setupPicker(
        trendKg: 57.9,
        units: UnitSystem.imperial,
      );
      await _open(tester, setup, IntakeBlock.bmiUnderFloor);

      expect(find.textContaining('127.6 lb'), findsOneWidget);
      expect(find.textContaining('5 ft 10 in'), findsOneWidget);
      expect(find.textContaining('129.3 lb'), findsOneWidget);
      expect(find.textContaining('BMI 18.3'), findsOneWidget);
      expect(find.textContaining(' kg'), findsNothing);
      expect(find.textContaining(' cm'), findsNothing);
    });

    testWidgets('103.5 lb back from kilograms is not read as 103.4 lb', (
      tester,
    ) async {
      final setup = await setupPicker(
        trendKg: ImperialUnits.kilograms(103.5),
        units: UnitSystem.imperial,
      );
      await _open(tester, setup, IntakeBlock.bmiUnderFloor);

      expect(find.textContaining('103.5 lb'), findsOneWidget);
      expect(find.textContaining('103.4 lb'), findsNothing);
    });

    testWidgets('hidden numbers show no digit except 18.5', (tester) async {
      final setup = await setupPicker(trendKg: 57.9, hidden: true);
      await _open(tester, setup, IntakeBlock.bmiUnderFloor);

      final l10n = l10nOf(tester, GoalRefusalScreen);
      expect(find.text(l10n.goalsBmiBody1Hidden), findsOneWidget);
      expect(find.text(l10n.goalsBmiRuleHidden), findsOneWidget);
      final digits = allText(tester).replaceAll('18.5', '');
      expect(RegExp(r'\d').hasMatch(digits), isFalse, reason: digits);
    });

    testWidgets('See the other goals opens the picker on Get fitter', (
      tester,
    ) async {
      final setup = await setupPicker(trendKg: 57.9);
      final router = await _open(tester, setup, IntakeBlock.bmiUnderFloor);

      await tapKey(tester, GoalRefusalKeys.primary);

      expect(whereIs(router), AppPaths.goalsPickWith(GoalKind.getFitter));
    });

    testWidgets('Continue without a goal goes to Today', (tester) async {
      final setup = await setupPicker(trendKg: 57.9);
      final router = await _open(tester, setup, IntakeBlock.bmiUnderFloor);

      await tapKey(tester, GoalRefusalKeys.secondary);

      expect(whereIs(router), '/today');
    });

    testWidgets('the buttons carry their labels', (tester) async {
      final setup = await setupPicker(trendKg: 57.9);
      await _open(tester, setup, IntakeBlock.bmiUnderFloor);

      final l10n = l10nOf(tester, GoalRefusalScreen);
      expect(
        find.descendant(
          of: find.byKey(GoalRefusalKeys.primary),
          matching: find.text(l10n.goalsRefusalSeeOthers),
        ),
        findsOneWidget,
      );
    });
  });

  group('12. the soft screen', () {
    testWidgets('shows every soft string, the rule and the foot', (
      tester,
    ) async {
      final setup = await _softSetup();
      await _open(tester, setup, IntakeBlock.softMode);

      final l10n = l10nOf(tester, GoalRefusalScreen);
      for (final text in [
        _softTitle,
        _softBody1,
        _softBody2,
        _softFactsTitle,
        _softFact1,
        _softFact2,
        _softFact3,
        l10n.goalsRefusalFoot,
      ]) {
        await tester.scrollUntilVisible(find.text(text), 200);
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.textContaining(l10n.goalsRefusalRule), findsWidgets);
      expect(find.textContaining(_softRule), findsOneWidget);
    });

    testWidgets('never says direction, Settings or hidden', (tester) async {
      final setup = await _softSetup();
      await _open(tester, setup, IntakeBlock.softMode);

      final text = allText(tester).toLowerCase();
      for (final word in ['direction', 'settings', 'hidden']) {
        expect(text.contains(word), isFalse, reason: word);
      }
    });

    testWidgets('the buttons carry their labels', (tester) async {
      final setup = await _softSetup();
      await _open(tester, setup, IntakeBlock.softMode);

      final l10n = l10nOf(tester, GoalRefusalScreen);
      expect(
        find.descendant(
          of: find.byKey(GoalRefusalKeys.primary),
          matching: find.text(l10n.goalsRefusalSeeNoWeight),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(GoalRefusalKeys.secondary),
          matching: find.text(l10n.goalsPickContinueNone),
        ),
        findsOneWidget,
      );
    });

    testWidgets('See the goals without weight opens the picker on Get fitter', (
      tester,
    ) async {
      final setup = await _softSetup();
      final router = await _open(tester, setup, IntakeBlock.softMode);

      await tapKey(tester, GoalRefusalKeys.primary);

      expect(whereIs(router), AppPaths.goalsPickWith(GoalKind.getFitter));
    });

    testWidgets('Continue without a goal goes to Today and starts nothing', (
      tester,
    ) async {
      final setup = await _softSetup();
      final router = await _open(tester, setup, IntakeBlock.softMode);

      await tapKey(tester, GoalRefusalKeys.secondary);

      expect(whereIs(router), '/today');
      expect(await setup.store.goals(), isEmpty);
    });
  });

  group('13. the soft route when the soft mode does not hold', () {
    final screenings = <String, bool?>{
      'softMode false': false,
      'softMode never asked': null,
    };
    for (final MapEntry(key: name, value: soft) in screenings.entries) {
      testWidgets('$name shows the picker', (tester) async {
        final setup = await setupPicker();
        if (soft != null) await _store(setup, soft: soft);
        await _open(tester, setup, IntakeBlock.softMode);

        expect(find.byKey(GoalRefusalKeys.primary), findsNothing);
        expect(find.text(_softTitle), findsNothing);
        expect(find.byKey(GoalPickKeys.continueButton), findsOneWidget);
      });
    }

    testWidgets('Body off with a stored soft yes shows the picker', (
      tester,
    ) async {
      final setup = await setupPicker(modules: const {ModuleId.goals});
      await _store(setup, soft: true);
      await _open(tester, setup, IntakeBlock.softMode);

      expect(find.byKey(GoalRefusalKeys.primary), findsNothing);
      expect(find.text(_softTitle), findsNothing);
      expect(find.byKey(GoalPickKeys.continueButton), findsOneWidget);
    });

    testWidgets('the gate off is an empty page', (tester) async {
      final setup = await setupPicker(modules: const {ModuleId.body});
      await _store(setup, soft: true);
      await _open(tester, setup, IntakeBlock.softMode);

      expect(find.byKey(GoalRefusalKeys.primary), findsNothing);
      expect(find.text(_softTitle), findsNothing);
      expect(find.byKey(GoalPickKeys.continueButton), findsNothing);
    });
  });

  group('a block with no refusal is an empty page', () {
    final blocks = [IntakeBlock.bodyOff];
    for (final block in blocks) {
      testWidgets('${block.name} shows no card and no buttons', (tester) async {
        final setup = await setupPicker();
        await _open(tester, setup, block);

        final l10n = l10nOf(tester, GoalRefusalScreen);
        expect(find.byKey(GoalRefusalKeys.primary), findsNothing);
        expect(find.byKey(GoalRefusalKeys.secondary), findsNothing);
        expect(find.text(l10n.goalsRefusalFoot), findsNothing);
      });
    }

    testWidgets('an unknown name shows no card and no buttons', (tester) async {
      final setup = await setupPicker();
      await pumpGoals(tester, setup, at: '${AppPaths.goalsRefused}/nonsense');

      final l10n = l10nOf(tester, GoalRefusalScreen);
      expect(find.byKey(GoalRefusalKeys.primary), findsNothing);
      expect(find.text(l10n.goalsRefusalFoot), findsNothing);
    });
  });

  group('a block that no longer holds shows the picker', () {
    final blocks = [
      IntakeBlock.under18,
      IntakeBlock.ageMissing,
      IntakeBlock.heightMissing,
      IntakeBlock.bmiUnderFloor,
    ];
    for (final block in blocks) {
      testWidgets('${block.name} with an adult at 70 kg and 178 cm', (
        tester,
      ) async {
        final setup = await setupPicker();
        await _open(tester, setup, block);

        expect(find.byKey(GoalRefusalKeys.primary), findsNothing);
        expect(find.byKey(GoalPickKeys.continueButton), findsOneWidget);
        expect(find.textContaining('BMI'), findsNothing);
      });
    }

    final cleared = <IntakeBlock, UserProfile>{
      IntakeBlock.under18: const UserProfile(heightCentimeters: 178),
      IntakeBlock.bmiUnderFloor: const UserProfile(birthYear: 1990),
    };
    for (final MapEntry(key: block, value: profile) in cleared.entries) {
      testWidgets('${block.name} after the value it names was cleared', (
        tester,
      ) async {
        final setup = await setupPicker(profile: profile, trendKg: 57.9);
        await _open(tester, setup, block);

        expect(find.byKey(GoalRefusalKeys.primary), findsNothing);
        expect(find.byKey(GoalPickKeys.continueButton), findsOneWidget);
      });
    }

    testWidgets('a failed read shows the load error', (tester) async {
      final setup = await setupPicker(trendFails: true);
      await _open(tester, setup, IntakeBlock.bmiUnderFloor);

      final l10n = l10nOf(tester, GoalRefusalScreen);
      expect(find.text(l10n.metricLoadError), findsOneWidget);
      expect(find.byKey(GoalRefusalKeys.primary), findsNothing);
    });
  });

  group('10. the gate is off', () {
    final blocks = [
      IntakeBlock.under18,
      IntakeBlock.bmiUnderFloor,
      IntakeBlock.heightMissing,
    ];
    for (final block in blocks) {
      testWidgets('${block.name} is an empty page', (tester) async {
        final setup = await setupPicker(
          modules: const {ModuleId.body},
          profile: _minor,
          trendKg: 57.9,
        );
        await _open(tester, setup, block);

        final l10n = l10nOf(tester, GoalRefusalScreen);
        expect(find.byKey(GoalRefusalKeys.primary), findsNothing);
        expect(find.byKey(GoalRefusalKeys.secondary), findsNothing);
        expect(find.text(l10n.goalsRefusalFoot), findsNothing);
        expect(find.textContaining('18'), findsNothing);
      });
    }
  });

  group('11. layout', () {
    final states = <String, ({IntakeBlock block, UserProfile? profile})>{
      'under18': (block: IntakeBlock.under18, profile: _minor),
      'bmi': (block: IntakeBlock.bmiUnderFloor, profile: okProfile),
      'profile': (
        block: IntakeBlock.heightMissing,
        profile: const UserProfile(birthYear: 1996),
      ),
    };
    for (final scale in layoutScales) {
      for (final brightness in layoutBrightnesses) {
        for (final MapEntry(key: name, value: state) in states.entries) {
          testWidgets('$name at ${scale}x ${brightness.name}', (tester) async {
            final setup = await setupPicker(
              profile: state.profile,
              trendKg: 57.9,
            );
            await _open(
              tester,
              setup,
              state.block,
              scale: scale,
              brightness: brightness,
            );
            await tester.scrollUntilVisible(
              find.byKey(GoalRefusalKeys.primary),
              200,
            );

            expect(find.byKey(GoalRefusalKeys.primary), findsOneWidget);
          });
        }

        testWidgets('15. soft at ${scale}x ${brightness.name}', (tester) async {
          final setup = await _softSetup();
          await _open(
            tester,
            setup,
            IntakeBlock.softMode,
            scale: scale,
            brightness: brightness,
          );
          await tester.scrollUntilVisible(
            find.byKey(GoalRefusalKeys.primary),
            200,
          );

          expect(find.byKey(GoalRefusalKeys.primary), findsOneWidget);
          expect(find.text(_softTitle), findsOneWidget);
        });
      }
    }
  });
}
