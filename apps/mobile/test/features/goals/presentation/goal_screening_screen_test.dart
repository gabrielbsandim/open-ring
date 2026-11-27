import 'dart:async';
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/food/application/food_energy.dart';
import 'package:open_ring/features/food/application/food_energy_gate.dart';
import 'package:open_ring/features/food/presentation/food_energy_screen.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/goals/presentation/goal_pick_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_refusal_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_screening_screen.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

import '../../../helpers/layout_harness.dart';
import '../goal_fixtures.dart';
import '../goal_picker_harness.dart';

const _title = 'Before you start';
const _lead =
    'Five quick questions. Tracking weight helps many people and gets in the way for some. The answers only tell the app which group you are in.';
const _notDiagnosis = 'This is not a diagnosis.';
const _staysTitle = 'Stays on this phone.';
const _stays =
    'The app stores only the overall result and the date, not each answer. Nothing is sent.';
const _skip =
    'If you would rather not answer, go back and choose a goal without weight.';
const _failed = 'The answers could not be saved. Try again.';
const _q3Hidden = 'Have you lost a lot of weight in the last 3 months?';
const _softTitle = 'The app goes on without a weight goal';

const _questions = [
  'Do you make yourself vomit because you feel uncomfortably full?',
  'Do you worry that you have lost control over how much you eat?',
  'Have you lost more than 6 kg in the last 3 months?',
  'Do you see yourself as overweight even when other people say your weight is low?',
  'Would you say that food dominates your life?',
];

const _twoYes = [true, true, false, false, false];
const _oneYes = [true, false, false, false, false];
const _mixed = [true, false, true, false, true];

String _answered(int n) => 'Answered: $n of 5.';

Key _option(int i, {required bool yes}) =>
    yes ? GoalScreeningKeys.yes(i) : GoalScreeningKeys.no(i);

// A tall view builds every question, so the tests need no scrolling.
Future<GoRouter> _open(
  WidgetTester tester,
  GoalSetup setup, {
  double scale = 1,
  Brightness brightness = Brightness.dark,
  bool tall = true,
}) async {
  final router = await pumpGoals(
    tester,
    setup,
    at: AppPaths.goalsScreening,
    scale: scale,
    brightness: brightness,
  );
  if (!tall) return router;
  tester.view.physicalSize = const Size(360, 6000) * 3;
  await tester.pumpAndSettle();
  return router;
}

Future<void> _answer(WidgetTester tester, int i, {required bool yes}) async {
  final key = _option(i, yes: yes);
  await tester.scrollUntilVisible(find.byKey(key), 200, maxScrolls: 200);
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> _answerAll(WidgetTester tester, List<bool> answers) async {
  for (final (i, yes) in answers.indexed) {
    await _answer(tester, i, yes: yes);
  }
}

bool _continueEnabled(WidgetTester tester) =>
    buttonOf(tester, GoalScreeningKeys.continueButton).onPressed != null;

CheckedState _checked(WidgetTester tester, int i, {required bool yes}) => tester
    .getSemantics(find.byKey(_option(i, yes: yes)))
    .flagsCollection
    .isChecked;

bool _before(Offset a, Offset b) =>
    a.dy < b.dy || (a.dy == b.dy && a.dx < b.dx);

final class _GatedHideStore implements HideNumbersStore {
  final gate = Completer<void>();

  @override
  Future<bool> read() async {
    await gate.future;
    return false;
  }

  @override
  Future<void> write({required bool hidden}) async {}
}

void main() {
  group('4. the screen', () {
    testWidgets('shows the title, lead, note and the five questions', (
      tester,
    ) async {
      final setup = await setupPicker();
      await _open(tester, setup);

      for (final text in [
        _title,
        _lead,
        _notDiagnosis,
        _staysTitle,
        _stays,
        _skip,
        ..._questions,
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.byKey(GoalScreeningKeys.back), findsOneWidget);
    });

    testWidgets('lists Q1 to Q5 in order, each with No before Yes', (
      tester,
    ) async {
      final setup = await setupPicker();
      await _open(tester, setup);

      final spots = <Offset>[];
      for (final (i, question) in _questions.indexed) {
        spots
          ..add(tester.getTopLeft(find.text(question)))
          ..add(tester.getTopLeft(find.byKey(GoalScreeningKeys.no(i))))
          ..add(tester.getTopLeft(find.byKey(GoalScreeningKeys.yes(i))));
        expect(
          find.descendant(
            of: find.byKey(GoalScreeningKeys.no(i)),
            matching: find.text('No'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(GoalScreeningKeys.yes(i)),
            matching: find.text('Yes'),
          ),
          findsOneWidget,
        );
      }
      for (var i = 1; i < spots.length; i++) {
        expect(_before(spots[i - 1], spots[i]), isTrue, reason: 'spot $i');
      }
    });

    testWidgets('Continue stays disabled from 0 to 4 answers, enabled at 5', (
      tester,
    ) async {
      final setup = await setupPicker();
      await _open(tester, setup);

      expect(_continueEnabled(tester), isFalse);
      expect(find.byKey(GoalScreeningKeys.answered), findsOneWidget);
      expect(find.text(_answered(0)), findsOneWidget);
      for (var n = 1; n <= 5; n++) {
        await _answer(tester, n - 1, yes: n.isEven);
        expect(find.text(_answered(n)), findsOneWidget, reason: 'n=$n');
        expect(_continueEnabled(tester), n == 5, reason: 'n=$n');
      }
    });

    testWidgets('tapping the other option replaces the answer', (tester) async {
      final handle = tester.ensureSemantics();
      final setup = await setupPicker();
      await _open(tester, setup);
      expect(_checked(tester, 0, yes: true), CheckedState.isFalse);
      expect(_checked(tester, 0, yes: false), CheckedState.isFalse);

      await _answer(tester, 0, yes: true);
      expect(_checked(tester, 0, yes: true), CheckedState.isTrue);
      expect(_checked(tester, 0, yes: false), CheckedState.isFalse);

      await _answer(tester, 0, yes: false);
      expect(_checked(tester, 0, yes: true), CheckedState.isFalse);
      expect(_checked(tester, 0, yes: false), CheckedState.isTrue);
      expect(find.text(_answered(1)), findsOneWidget);
      handle.dispose();
    });

    testWidgets('opening the screen writes nothing', (tester) async {
      final setup = await setupPicker();
      await _open(tester, setup);

      expect(await setup.store.screenings(), isEmpty);
      expect(setup.revision, 0);
    });
  });

  group('5. the weight in the third question', () {
    testWidgets('metric reads 6 kg', (tester) async {
      final setup = await setupPicker();
      await _open(tester, setup);

      expect(find.text(_questions[2]), findsOneWidget);
    });

    testWidgets('imperial reads 13 lb', (tester) async {
      final setup = await setupPicker(units: UnitSystem.imperial);
      await _open(tester, setup);

      expect(
        find.text('Have you lost more than 13 lb in the last 3 months?'),
        findsOneWidget,
      );
      expect(find.textContaining('kg'), findsNothing);
    });

    testWidgets('hidden numbers read the hidden text and show no unit', (
      tester,
    ) async {
      final setup = await setupPicker(hidden: true);
      await _open(tester, setup);

      expect(find.text(_q3Hidden), findsOneWidget);
      expect(find.text(_questions[2]), findsNothing);
      expect(RegExp(r'\b(kg|lb)\b').hasMatch(allText(tester)), isFalse);
    });

    testWidgets('hidden numbers in imperial show no unit either', (
      tester,
    ) async {
      final setup = await setupPicker(hidden: true, units: UnitSystem.imperial);
      await _open(tester, setup);

      expect(find.text(_q3Hidden), findsOneWidget);
      expect(RegExp(r'\b(kg|lb)\b').hasMatch(allText(tester)), isFalse);
    });

    testWidgets('the weight never shows before the choice is read', (
      tester,
    ) async {
      final store = _GatedHideStore();
      final setup = await setupPicker(hideStore: store);
      await _open(tester, setup);

      expect(RegExp(r'\b(kg|lb)\b').hasMatch(allText(tester)), isFalse);

      store.gate.complete();
      await tester.pumpAndSettle();

      expect(find.text(_questions[2]), findsOneWidget);
    });
  });

  group('6. two yes answers', () {
    testWidgets('write one row and open the soft screen', (tester) async {
      final setup = await setupPicker();
      final router = await _open(tester, setup);
      await _answerAll(tester, _twoYes);

      await tapKey(tester, GoalScreeningKeys.continueButton);

      final rows = await setup.store.screenings();
      expect(rows, hasLength(1));
      expect(rows.single.on, goalDay(12, 7));
      expect(rows.single.softMode, isTrue);
      expect(rows.single.pregnantOrBreastfeeding, isNull);
      expect(whereIs(router), AppPaths.goalsRefusedFor(IntakeBlock.softMode));
      expect(find.byType(GoalRefusalScreen), findsOneWidget);
      expect(find.text(_softTitle), findsOneWidget);
      expect(await setup.store.goals(), isEmpty);
      expect(setup.revision, 1);
    });
  });

  group('7. one yes answer', () {
    testWidgets('writes one row with soft mode false and opens the setup', (
      tester,
    ) async {
      final setup = await setupPicker();
      final router = await _open(tester, setup);
      await _answerAll(tester, _oneYes);

      await tapKey(tester, GoalScreeningKeys.continueButton);

      final rows = await setup.store.screenings();
      expect(rows, hasLength(1));
      expect(rows.single.softMode, isFalse);
      expect(rows.single.pregnantOrBreastfeeding, isNull);
      expect(whereIs(router), '/today/goals/setup');
      expect(await setup.store.goals(), isEmpty);
    });
  });

  group('8. a second tap before the rebuild', () {
    testWidgets('two taps on Continue write one row', (tester) async {
      final gate = Completer<void>();
      final setup = await setupPicker(
        readStoreOf: (memory) => ProbeGoalStore(memory, screeningGate: gate),
      );
      final router = await _open(tester, setup);
      await _answerAll(tester, _twoYes);

      await tester.tap(find.byKey(GoalScreeningKeys.continueButton));
      await tester.tap(
        find.byKey(GoalScreeningKeys.continueButton),
        warnIfMissed: false,
      );
      gate.complete();
      await tester.pumpAndSettle();

      expect((await setup.store.screenings()).length, 1);
      expect(setup.revision, 1);
      expect(whereIs(router), AppPaths.goalsRefusedFor(IntakeBlock.softMode));
    });

    testWidgets('the screen is kept until the write has been awaited', (
      tester,
    ) async {
      final gate = Completer<void>();
      final setup = await setupPicker(
        readStoreOf: (memory) => ProbeGoalStore(memory, screeningGate: gate),
      );
      final router = await _open(tester, setup);
      await _answerAll(tester, _twoYes);

      await tester.tap(find.byKey(GoalScreeningKeys.continueButton));
      await tester.pump();

      expect(whereIs(router), AppPaths.goalsScreening);
      expect(find.byKey(GoalScreeningKeys.continueButton), findsOneWidget);
      expect(setup.revision, 0);

      gate.complete();
      await tester.pumpAndSettle();

      expect(whereIs(router), AppPaths.goalsRefusedFor(IntakeBlock.softMode));
    });

    testWidgets('the revision bump does not swap the screen for the picker', (
      tester,
    ) async {
      final setup = await setupPicker();
      final router = await _open(tester, setup);
      await _answerAll(tester, _oneYes);

      // The leaving screen stays on stage through the transition, after the
      // new answer is read.
      await tester.tap(find.byKey(GoalScreeningKeys.continueButton));
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(find.byType(GoalPickScreen, skipOffstage: false), findsNothing);
      }
      await tester.pumpAndSettle();

      expect(whereIs(router), '/today/goals/setup');
    });

    testWidgets('the soft screen does not show the picker while it reads', (
      tester,
    ) async {
      final read = Completer<void>();
      final setup = await setupPicker(
        readStoreOf: (memory) =>
            ProbeGoalStore(memory, readAfterWriteGate: read),
      );
      final router = await _open(tester, setup);
      await _answerAll(tester, _twoYes);

      await tester.tap(find.byKey(GoalScreeningKeys.continueButton));
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(find.byType(GoalPickScreen), findsNothing);
      }
      expect(whereIs(router), AppPaths.goalsRefusedFor(IntakeBlock.softMode));

      read.complete();
      await tester.pumpAndSettle();

      expect(find.text(_softTitle), findsOneWidget);
      expect(find.byType(GoalPickScreen), findsNothing);
    });
  });

  group('9. the store throws', () {
    testWidgets('keeps the screen and the answers and says so', (tester) async {
      final handle = tester.ensureSemantics();
      final setup = await setupPicker(
        readStoreOf: (memory) => ProbeGoalStore(memory, screeningFailures: 1),
      );
      final router = await _open(tester, setup);
      await _answerAll(tester, _twoYes);

      await tapKey(tester, GoalScreeningKeys.continueButton);

      expect(whereIs(router), AppPaths.goalsScreening);
      expect(find.byKey(GoalScreeningKeys.failed), findsOneWidget);
      expect(find.text(_failed), findsOneWidget);
      expect(find.text(_answered(5)), findsOneWidget);
      expect(_checked(tester, 0, yes: true), CheckedState.isTrue);
      expect(_checked(tester, 2, yes: false), CheckedState.isTrue);
      expect(_continueEnabled(tester), isTrue);
      expect(await setup.store.screenings(), isEmpty);
      expect(setup.revision, 0);
      handle.dispose();
    });

    testWidgets('a retry writes one row and opens the soft screen', (
      tester,
    ) async {
      final setup = await setupPicker(
        readStoreOf: (memory) => ProbeGoalStore(memory, screeningFailures: 1),
      );
      final router = await _open(tester, setup);
      await _answerAll(tester, _twoYes);
      await tapKey(tester, GoalScreeningKeys.continueButton);

      await tapKey(tester, GoalScreeningKeys.continueButton);

      final rows = await setup.store.screenings();
      expect(rows, hasLength(1));
      expect(rows.single.softMode, isTrue);
      expect(whereIs(router), AppPaths.goalsRefusedFor(IntakeBlock.softMode));
      expect(find.byKey(GoalScreeningKeys.failed), findsNothing);
    });
  });

  group('10. the questions are not asked', () {
    Future<void> expectPicker(WidgetTester tester, GoalSetup setup) async {
      await _open(tester, setup);

      expect(find.byKey(GoalScreeningKeys.continueButton), findsNothing);
      expect(find.byKey(GoalScreeningKeys.yes(0)), findsNothing);
      expect(find.byKey(GoalPickKeys.continueButton), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(GoalPickKeys.continueButton),
          matching: find.text(l10nOf(tester, GoalPickScreen).goalsPickContinue),
        ),
        findsOneWidget,
      );
    }

    for (final soft in [true, false]) {
      testWidgets('a stored ${soft ? 'yes' : 'no'} shows the picker', (
        tester,
      ) async {
        final setup = await setupPicker();
        await setup.store.addScreening(
          GoalScreening(
            on: goalDay(12, 1),
            softMode: soft,
            pregnantOrBreastfeeding: null,
          ),
        );

        await expectPicker(tester, setup);

        expect(await setup.store.screenings(), hasLength(1));
      });
    }

    testWidgets('ageMissing shows the picker and writes nothing', (
      tester,
    ) async {
      final setup = await setupPicker(
        profile: const UserProfile(heightCentimeters: 178),
      );

      await expectPicker(tester, setup);

      expect(await setup.store.screenings(), isEmpty);
    });

    testWidgets('Body off shows the picker', (tester) async {
      final setup = await setupPicker(modules: const {ModuleId.goals});

      await _open(tester, setup);

      expect(find.byKey(GoalScreeningKeys.continueButton), findsNothing);
      expect(find.byKey(GoalPickKeys.continueButton), findsOneWidget);
    });

    testWidgets('the gate off is an empty page', (tester) async {
      final setup = await setupPicker(modules: const {ModuleId.body});

      await _open(tester, setup);

      expect(find.byKey(GoalScreeningKeys.continueButton), findsNothing);
      expect(find.byKey(GoalPickKeys.continueButton), findsNothing);
      expect(find.text(_lead), findsNothing);
    });
  });

  group('11. Back', () {
    testWidgets('opens the picker on Get fitter and writes nothing', (
      tester,
    ) async {
      final setup = await setupPicker();
      final router = await _open(tester, setup);
      await _answerAll(tester, _twoYes);

      await tapKey(tester, GoalScreeningKeys.back);

      expect(whereIs(router), AppPaths.goalsPickWith(GoalKind.getFitter));
      expect(await setup.store.screenings(), isEmpty);
      expect(setup.revision, 0);
    });
  });

  group('14. semantics', () {
    testWidgets('each question is a group labelled Question n of 5', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final setup = await setupPicker();
      await _open(tester, setup);

      for (var n = 1; n <= 5; n++) {
        expect(
          find.bySemanticsLabel('Question $n of 5'),
          findsOneWidget,
          reason: 'Question $n of 5',
        );
      }
      handle.dispose();
    });

    testWidgets('the options are in a mutually exclusive group', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final setup = await setupPicker();
      await _open(tester, setup);

      for (var i = 0; i < 5; i++) {
        for (final yes in [false, true]) {
          final flags = tester
              .getSemantics(find.byKey(_option(i, yes: yes)))
              .flagsCollection;
          expect(flags.isInMutuallyExclusiveGroup, isTrue, reason: '$i $yes');
          expect(flags.isChecked, CheckedState.isFalse, reason: '$i $yes');
        }
      }
      handle.dispose();
    });

    testWidgets('the title is a header', (tester) async {
      final handle = tester.ensureSemantics();
      final setup = await setupPicker();
      await _open(tester, setup);

      expect(
        tester.getSemantics(find.text(_title)).flagsCollection.isHeader,
        isTrue,
      );
      handle.dispose();
    });
  });

  group('15. layout', () {
    for (final scale in layoutScales) {
      for (final brightness in layoutBrightnesses) {
        testWidgets('empty at ${scale}x ${brightness.name}', (tester) async {
          final setup = await setupPicker();
          await _open(
            tester,
            setup,
            scale: scale,
            brightness: brightness,
            tall: false,
          );

          await expectNoLayoutOverflow(() async {
            await tester.scrollUntilVisible(
              find.byKey(GoalScreeningKeys.continueButton),
              200,
              maxScrolls: 200,
            );
          });

          expect(_continueEnabled(tester), isFalse);
        });

        testWidgets('complete at ${scale}x ${brightness.name}', (tester) async {
          final setup = await setupPicker();
          await _open(
            tester,
            setup,
            scale: scale,
            brightness: brightness,
            tall: false,
          );

          await expectNoLayoutOverflow(() async {
            await _answerAll(tester, _mixed);
            await tester.scrollUntilVisible(
              find.byKey(GoalScreeningKeys.continueButton),
              200,
              maxScrolls: 200,
            );
          });

          expect(_continueEnabled(tester), isTrue);
          expect(find.text(_answered(5)), findsOneWidget);
        });
      }
    }
  });

  group('energy mode', () {
    const energyModules = {ModuleId.ai, ModuleId.food, ModuleId.body};
    const sexed = UserProfile(
      birthYear: 1990,
      heightCentimeters: 178,
      sex: Sex.female,
    );

    Future<(GoalSetup, GoRouter)> openForEnergy(WidgetTester tester) async {
      final setup = await setupPicker(modules: energyModules, profile: sexed);
      final router = await pumpGoals(
        tester,
        setup,
        at: AppPaths.goalsScreeningForEnergy,
      );
      tester.view.physicalSize = const Size(360, 6000) * 3;
      await tester.pumpAndSettle();
      return (setup, router);
    }

    testWidgets('asks the five questions with Goals off, without the '
        'goals way out', (tester) async {
      await openForEnergy(tester);

      for (final text in _questions) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.byKey(GoalScreeningKeys.back), findsNothing);
      expect(find.text(_skip), findsNothing);
    });

    testWidgets('five no answers store one result and offer Weekly energy', (
      tester,
    ) async {
      final (setup, router) = await openForEnergy(tester);

      await _answerAll(tester, List.filled(5, false));
      await tapKey(tester, GoalScreeningKeys.continueButton);

      expect(whereIs(router), AppPaths.foodEnergy);
      final rows = await setup.store.screenings();
      expect(rows, hasLength(1));
      expect(rows.single.softMode, isFalse);
      expect(rows.single.pregnantOrBreastfeeding, isNull);
      expect(
        await setup.container.read(foodEnergyGateProvider.future),
        isA<FoodEnergyOffered>(),
      );
    });

    testWidgets('two yes answers block it for soft mode', (tester) async {
      final (setup, router) = await openForEnergy(tester);

      await _answerAll(tester, _twoYes);
      await tapKey(tester, GoalScreeningKeys.continueButton);

      expect(whereIs(router), AppPaths.foodEnergy);
      expect(
        await setup.container.read(foodEnergyGateProvider.future),
        isA<FoodEnergyBlocked>().having(
          (gate) => gate.block,
          'block',
          FoodEnergyBlock.softMode,
        ),
      );
    });

    testWidgets('once answered it shows the energy screen instead', (
      tester,
    ) async {
      final store = InMemoryGoalStore();
      await store.addScreening(
        const GoalScreening(
          on: LocalDate(2026, 12, 1),
          softMode: false,
          pregnantOrBreastfeeding: null,
        ),
      );
      final setup = await setupPicker(
        modules: energyModules,
        profile: sexed,
        store: store,
        extraOverrides: [
          foodEnergyProvider.overrideWith(
            (ref) async => FoodEnergyView(
              gate: await ref.watch(foodEnergyGateProvider.future),
            ),
          ),
        ],
      );
      await pumpGoals(tester, setup, at: AppPaths.goalsScreeningForEnergy);
      await tester.pumpAndSettle();

      expect(find.byType(FoodEnergyScreen), findsOneWidget);
      expect(find.byKey(GoalScreeningKeys.continueButton), findsNothing);
    });

    testWidgets('without the energy flag Goals off still shows nothing', (
      tester,
    ) async {
      final setup = await setupPicker(modules: energyModules, profile: sexed);
      await pumpGoals(tester, setup, at: AppPaths.goalsScreening);
      await tester.pumpAndSettle();

      expect(find.text(_title), findsOneWidget);
      expect(find.byKey(GoalScreeningKeys.continueButton), findsNothing);
    });
  });
}
