import 'dart:async';
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/goals/presentation/goal_pick_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_screening_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_setup_screen.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

import '../../../helpers/layout_harness.dart';
import '../goal_fixtures.dart';
import '../goal_picker_harness.dart';
import '../goal_setup_harness.dart';

const _question = 'Are you pregnant or breastfeeding?';
const _answerFirst = 'Answer the question above to go on.';
const _paceTitle = 'Pace';
const _gentle = 'Gentle';
const _steady = 'Steady';
const _blockTitle = 'The block';
const _foodTitle = 'What this plan can do';
const _referenceTitle = 'Reference weight, optional';
const _noRoom = 'Your trend is too close to BMI 18.5 for a reference weight.';
const _weighFirst =
    'The plan starts from your weight trend, and there is none yet. Add a weigh-in in Body, then come back here.';
const _start = 'Start the plan';
const _demo = 'A goal cannot be started in demo mode.';
const _failed = 'The goal could not be started. Try again.';
const _active = 'You already have a goal. End it before you choose another.';
const _continue = 'Continue';
const _pregnancyTitle =
    'During pregnancy and breastfeeding, the app builds no weight goal';

final _kg = RegExp(r'\bkg\b');

Future<GoalSetup> _ready({
  UserProfile? profile = okProfile,
  double? trendKg = 78.4,
  bool stored = true,
  bool hidden = false,
  UnitSystem units = UnitSystem.metric,
  bool demo = false,
  Set<ModuleId> modules = goalModules,
  GoalDraft? draft,
  GoalStore Function(InMemoryGoalStore memory)? readStoreOf,
}) async {
  final setup = await setupPicker(
    profile: profile,
    trendKg: trendKg,
    hidden: hidden,
    units: units,
    demo: demo,
    modules: modules,
    draft: draft,
    readStoreOf: readStoreOf,
  );
  if (stored) await storeScreening(setup, soft: false);
  return setup;
}

String _valueText(WidgetTester tester) {
  final texts = find.descendant(
    of: find.byKey(GoalSetupKeys.referenceValue),
    matching: find.byType(Text),
    matchRoot: true,
  );
  return tester.widgetList<Text>(texts).map((t) => t.data ?? '').join(' ');
}

bool _enabled(WidgetTester tester, Key key) =>
    buttonOf(tester, key).onPressed != null;

Future<void> _tapFrame(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pump();
  await tester.tap(find.byKey(key));
}

Future<void> _stepDown(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tapKey(tester, GoalSetupKeys.referenceDown);
  }
}

Future<void> _answerFive(WidgetTester tester, {required bool yes}) async {
  for (var i = 0; i < goalScreeningQuestions; i++) {
    final key = yes ? GoalScreeningKeys.yes(i) : GoalScreeningKeys.no(i);
    await tester.ensureVisible(find.byKey(key));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }
}

GoalStore Function(InMemoryGoalStore) _counting(
  void Function(CountingGoalStore store) sink, {
  Completer<void>? startGate,
  Completer<void>? screeningGate,
  Completer<void>? readGate,
  Error? startError,
  bool startsNull = false,
}) => (memory) {
  final store = CountingGoalStore(
    memory,
    startGate: startGate,
    screeningGate: screeningGate,
    readAfterWriteGate: readGate,
    startError: startError,
    startsNull: startsNull,
  );
  sink(store);
  return store;
};

void main() {
  group('1. the picker leads to the setup', () {
    testWidgets('Lose fat with a stored no goes to the setup', (tester) async {
      final setup = await _ready();
      final router = await pumpSetup(
        tester,
        setup,
        at: AppPaths.goalsPickWith(GoalKind.loseFat),
      );

      await tapKey(tester, GoalPickKeys.continueButton);

      expect(whereIs(router), AppPaths.goalsSetup);
      expect(find.byType(GoalSetupScreen), findsOneWidget);
      expect(find.byType(GoalPickScreen), findsNothing);
    });

    testWidgets('a stored no with no trend still opens the setup', (
      tester,
    ) async {
      final setup = await _ready(trendKg: null);
      final router = await pumpSetup(
        tester,
        setup,
        at: AppPaths.goalsPickWith(GoalKind.loseFat),
      );

      await tapKey(tester, GoalPickKeys.continueButton);

      expect(whereIs(router), AppPaths.goalsSetup);
    });
  });

  group('2. five No answers land on the setup', () {
    testWidgets('the setup shows, with no picker frame on the way', (
      tester,
    ) async {
      final read = Completer<void>();
      final setup = await _ready(
        stored: false,
        readStoreOf: _counting((_) {}, readGate: read),
      );
      final router = await pumpSetup(
        tester,
        setup,
        at: AppPaths.goalsScreening,
      );
      await _answerFive(tester, yes: false);

      await tester.tap(find.byKey(GoalScreeningKeys.continueButton));
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(find.byType(GoalPickScreen, skipOffstage: false), findsNothing);
      }
      read.complete();
      await tester.pumpAndSettle();

      expect(whereIs(router), AppPaths.goalsSetup);
      expect(find.byType(GoalSetupScreen), findsOneWidget);
      expect(find.byType(GoalPickScreen), findsNothing);
      final rows = await setup.store.screenings();
      expect(rows, hasLength(1));
      expect(rows.single.softMode, isFalse);
    });
  });

  group('3. the pregnancy question comes first', () {
    testWidgets('with sex unknown only the question shows before an answer', (
      tester,
    ) async {
      final setup = await _ready();
      await pumpSetup(tester, setup);

      expect(find.text(_question), findsOneWidget);
      expect(find.byKey(GoalSetupKeys.pregnancyNo), findsOneWidget);
      expect(find.byKey(GoalSetupKeys.pregnancyYes), findsOneWidget);
      expect(find.byKey(GoalSetupKeys.start), findsNothing);
      expect(find.text(_start), findsNothing);
      expect(find.text(_paceTitle), findsNothing);
      expect(find.text(_blockTitle), findsNothing);
      expect(find.text(_foodTitle), findsNothing);
      expect(find.text(_answerFirst), findsOneWidget);
      expect(find.textContaining('78'), findsNothing);
      expect(allText(tester), isNot(contains('kg')));
    });

    testWidgets('after No the start, pace, block and food cards appear', (
      tester,
    ) async {
      final setup = await _ready();
      await pumpSetup(tester, setup);

      await tapKey(tester, GoalSetupKeys.pregnancyNo);

      expect(find.byKey(GoalSetupKeys.start), findsOneWidget);
      expect(find.text(_start), findsOneWidget);
      expect(find.text(_paceTitle), findsOneWidget);
      expect(find.text(_gentle), findsOneWidget);
      expect(find.text(_steady), findsOneWidget);
      expect(find.text(_blockTitle), findsOneWidget);
      expect(find.text(_foodTitle), findsOneWidget);
      expect(find.text(_answerFirst), findsNothing);
      expect(await setup.store.goals(), isEmpty);
    });
  });

  group('4. a male with no stored yes is not asked', () {
    testWidgets('no question card and the plan shows at once', (tester) async {
      final setup = await _ready(profile: maleProfile);
      await pumpSetup(tester, setup);

      expect(find.text(_question), findsNothing);
      expect(find.byKey(GoalSetupKeys.pregnancyNo), findsNothing);
      expect(find.byKey(GoalSetupKeys.pregnancyYes), findsNothing);
      expect(find.byKey(GoalSetupKeys.start), findsOneWidget);
      expect(find.text(_paceTitle), findsOneWidget);
    });
  });

  group('5. a yes to pregnancy', () {
    testWidgets('Yes then Continue stores one row and opens the refusal', (
      tester,
    ) async {
      final setup = await _ready();
      final router = await pumpSetup(tester, setup);

      await tapKey(tester, GoalSetupKeys.pregnancyYes);

      expect(find.text(_continue), findsOneWidget);
      expect(find.byKey(GoalSetupKeys.start), findsNothing);
      expect(find.text(_paceTitle), findsNothing);

      await tester.tap(find.text(_continue));
      await tester.pumpAndSettle();

      final rows = await setup.store.screenings();
      final answers = rows.where((r) => r.pregnantOrBreastfeeding != null);
      expect(answers, hasLength(1));
      expect(answers.single.pregnantOrBreastfeeding, isTrue);
      expect(answers.single.softMode, isNull);
      expect(await setup.store.goals(), isEmpty);
      expect(whereIs(router), AppPaths.goalsRefusedPregnancy);
      expect(find.text(_pregnancyTitle), findsOneWidget);
    });

    testWidgets('the refusal waits on the read with no picker frame', (
      tester,
    ) async {
      final read = Completer<void>();
      final setup = await _ready(
        readStoreOf: _counting((_) {}, readGate: read),
      );
      final router = await pumpSetup(tester, setup);
      await tapKey(tester, GoalSetupKeys.pregnancyYes);

      await tester.tap(find.text(_continue));
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(find.byType(GoalPickScreen, skipOffstage: false), findsNothing);
      }
      read.complete();
      await tester.pumpAndSettle();

      expect(whereIs(router), AppPaths.goalsRefusedPregnancy);
      expect(find.text(_pregnancyTitle), findsOneWidget);
      expect(find.byType(GoalPickScreen), findsNothing);
    });

    testWidgets('two taps on Continue write one row', (tester) async {
      final gate = Completer<void>();
      late CountingGoalStore probe;
      final setup = await _ready(
        readStoreOf: _counting((s) => probe = s, screeningGate: gate),
      );
      await pumpSetup(tester, setup);
      await tapKey(tester, GoalSetupKeys.pregnancyYes);

      await tester.tap(find.text(_continue));
      await tester.tap(find.text(_continue));
      gate.complete();
      await tester.pumpAndSettle();

      expect(probe.screeningWrites, 1);
      final rows = await setup.store.screenings();
      expect(
        rows.where((r) => r.pregnantOrBreastfeeding == true),
        hasLength(1),
      );
    });
  });

  group('6. No, gentle, Start', () {
    testWidgets('starts a gentle goal with no reference and opens Today', (
      tester,
    ) async {
      final setup = await _ready();
      final router = await pumpSetup(tester, setup);
      await tapKey(tester, GoalSetupKeys.pregnancyNo);
      await tapKey(tester, GoalSetupKeys.paceGentle);

      await tapKey(tester, GoalSetupKeys.start);

      final goals = await setup.store.goals();
      expect(goals, hasLength(1));
      expect(goals.single.kind, GoalKind.loseFat);
      expect(goals.single.pace, GoalPace.gentle);
      expect(goals.single.referenceKg, isNull);
      expect(goals.single.anchorKg, closeTo(78.4, 1e-9));
      expect(goals.single.startedOn, goalDay(12, 7));
      final rows = await setup.store.screenings();
      final answers = rows.where((r) => r.pregnantOrBreastfeeding != null);
      expect(answers, hasLength(1));
      expect(answers.single.pregnantOrBreastfeeding, isFalse);
      expect(whereIs(router), '/today');
      expect(find.text(todayStub), findsOneWidget);
    });

    testWidgets('the pace is Steady unless the person changes it', (
      tester,
    ) async {
      final setup = await _ready(profile: maleProfile);
      await pumpSetup(tester, setup);

      await tapKey(tester, GoalSetupKeys.start);

      final goals = await setup.store.goals();
      expect(goals.single.pace, GoalPace.standard);
    });

    testWidgets('the block card follows the pace and shows no date', (
      tester,
    ) async {
      final setup = await _ready(profile: maleProfile);
      await pumpSetup(tester, setup);

      expect(find.textContaining('Losing: 12 weeks'), findsOneWidget);
      expect(find.textContaining('Then holding: 4 weeks'), findsOneWidget);
      expect(find.textContaining('about 4.7 kg in the block'), findsOneWidget);
      expect(find.textContaining('2026'), findsNothing);

      await tapKey(tester, GoalSetupKeys.paceGentle);

      expect(find.textContaining('about 2.4 kg in the block'), findsOneWidget);
      expect(find.textContaining('about 4.7 kg in the block'), findsNothing);
    });
  });

  group('7. the reference weight stepper', () {
    testWidgets('metric: Add shows 78.0, bounds disable Up and Down', (
      tester,
    ) async {
      final setup = await _ready(profile: maleProfile);
      await pumpSetup(tester, setup);
      expect(find.byKey(GoalSetupKeys.referenceValue), findsNothing);
      expect(find.text(_referenceTitle), findsOneWidget);

      await tapKey(tester, GoalSetupKeys.referenceAdd);

      expect(_valueText(tester), contains('78.0'));
      expect(_enabled(tester, GoalSetupKeys.referenceUp), isFalse);
      expect(_enabled(tester, GoalSetupKeys.referenceDown), isTrue);

      await _stepDown(tester, 38);

      expect(_valueText(tester), contains('59.0'));
      expect(_enabled(tester, GoalSetupKeys.referenceDown), isFalse);
      expect(_enabled(tester, GoalSetupKeys.referenceUp), isTrue);
    });

    testWidgets('metric: two Downs then Start store 77.0', (tester) async {
      final setup = await _ready(profile: maleProfile);
      await pumpSetup(tester, setup);
      await tapKey(tester, GoalSetupKeys.referenceAdd);

      await _stepDown(tester, 2);
      expect(_valueText(tester), contains('77.0'));
      await tapKey(tester, GoalSetupKeys.start);

      final goals = await setup.store.goals();
      expect(goals.single.referenceKg, closeTo(77.0, 1e-9));
    });

    testWidgets('metric: the lower bound is stored as 59.0', (tester) async {
      final setup = await _ready(profile: maleProfile);
      await pumpSetup(tester, setup);
      await tapKey(tester, GoalSetupKeys.referenceAdd);
      await _stepDown(tester, 38);

      await tapKey(tester, GoalSetupKeys.start);

      final goals = await setup.store.goals();
      expect(goals.single.referenceKg, closeTo(59.0, 1e-9));
    });

    testWidgets('imperial: Add shows 171 and 171 lb stores 77.5643 kg', (
      tester,
    ) async {
      final setup = await _ready(
        profile: maleProfile,
        units: UnitSystem.imperial,
      );
      await pumpSetup(tester, setup);

      await tapKey(tester, GoalSetupKeys.referenceAdd);

      expect(_valueText(tester), contains('171'));
      expect(_enabled(tester, GoalSetupKeys.referenceUp), isFalse);
      await tapKey(tester, GoalSetupKeys.start);

      final goals = await setup.store.goals();
      expect(goals.single.referenceKg, closeTo(77.5643, 1e-4));
    });

    testWidgets('imperial: the lower bound is 131 lb and lands inside', (
      tester,
    ) async {
      final setup = await _ready(
        profile: maleProfile,
        units: UnitSystem.imperial,
      );
      await pumpSetup(tester, setup);
      await tapKey(tester, GoalSetupKeys.referenceAdd);

      await _stepDown(tester, 40);

      expect(_valueText(tester), contains('131'));
      expect(_enabled(tester, GoalSetupKeys.referenceDown), isFalse);
      await tapKey(tester, GoalSetupKeys.start);
      final goals = await setup.store.goals();
      expect(goals, hasLength(1));
      final kg = goals.single.referenceKg!;
      expect(kg, greaterThanOrEqualTo(59.0));
      expect(kg, lessThanOrEqualTo(78.0));
    });
  });

  group('8. Remove', () {
    testWidgets('Add then Remove stores a null reference', (tester) async {
      final setup = await _ready(profile: maleProfile);
      await pumpSetup(tester, setup);
      await tapKey(tester, GoalSetupKeys.referenceAdd);
      expect(find.byKey(GoalSetupKeys.referenceValue), findsOneWidget);

      await tapKey(tester, GoalSetupKeys.referenceRemove);

      expect(find.byKey(GoalSetupKeys.referenceValue), findsNothing);
      expect(find.byKey(GoalSetupKeys.referenceAdd), findsOneWidget);
      await tapKey(tester, GoalSetupKeys.start);
      final goals = await setup.store.goals();
      expect(goals.single.referenceKg, isNull);
    });
  });

  group('9. no room for a reference', () {
    testWidgets('a trend of 59.2 shows the note and no Add', (tester) async {
      final setup = await _ready(profile: maleProfile, trendKg: 59.2);
      await pumpSetup(tester, setup);

      expect(find.text(_noRoom), findsOneWidget);
      expect(find.byKey(GoalSetupKeys.referenceAdd), findsNothing);
      expect(find.byKey(GoalSetupKeys.referenceValue), findsNothing);
      expect(_enabled(tester, GoalSetupKeys.start), isTrue);

      await tapKey(tester, GoalSetupKeys.start);

      final goals = await setup.store.goals();
      expect(goals.single.referenceKg, isNull);
    });

    testWidgets('a trend of 78.4 shows no such note', (tester) async {
      final setup = await _ready(profile: maleProfile);
      await pumpSetup(tester, setup);

      expect(find.text(_noRoom), findsNothing);
      expect(find.byKey(GoalSetupKeys.referenceAdd), findsOneWidget);
    });
  });

  group('10. hidden numbers', () {
    testWidgets('no kg text, no reference card and a null reference', (
      tester,
    ) async {
      final setup = await _ready(profile: maleProfile, hidden: true);
      await pumpSetup(tester, setup);

      expect(allText(tester), isNot(matches(_kg)));
      expect(find.byKey(GoalSetupKeys.referenceAdd), findsNothing);
      expect(find.byKey(GoalSetupKeys.referenceValue), findsNothing);
      expect(find.text(_referenceTitle), findsNothing);
      expect(find.textContaining('78'), findsNothing);

      await tapKey(tester, GoalSetupKeys.start);

      final goals = await setup.store.goals();
      expect(goals, hasLength(1));
      expect(goals.single.referenceKg, isNull);
    });

    testWidgets('hidden imperial numbers show no lb either', (tester) async {
      final setup = await _ready(
        profile: maleProfile,
        hidden: true,
        units: UnitSystem.imperial,
      );
      await pumpSetup(tester, setup);

      expect(allText(tester), isNot(matches(RegExp(r'\blb\b'))));
    });

    testWidgets('a reference added before hiding is not sent', (tester) async {
      final setup = await _ready(profile: maleProfile);
      await pumpSetup(tester, setup);
      await tapKey(tester, GoalSetupKeys.referenceAdd);
      expect(find.byKey(GoalSetupKeys.referenceValue), findsOneWidget);

      await setup.container
          .read(hideNumbersProvider.notifier)
          .set(hidden: true);
      await tester.pumpAndSettle();
      expect(find.byKey(GoalSetupKeys.referenceValue), findsNothing);
      await tapKey(tester, GoalSetupKeys.start);

      final goals = await setup.store.goals();
      expect(goals, hasLength(1));
      expect(goals.single.referenceKg, isNull);
    });
  });

  group('11. no trend yet', () {
    testWidgets('shows the weigh-in state and Open Body goes to Body', (
      tester,
    ) async {
      final setup = await _ready(profile: maleProfile, trendKg: null);
      final router = await pumpSetup(tester, setup);

      expect(find.text(_weighFirst), findsOneWidget);
      expect(find.byKey(GoalSetupKeys.start), findsNothing);
      expect(find.byKey(GoalSetupKeys.openBody), findsOneWidget);

      await tapKey(tester, GoalSetupKeys.openBody);

      expect(whereIs(router), AppPaths.body);
      expect(find.text(bodyStub), findsOneWidget);
      expect(await setup.store.goals(), isEmpty);
    });
  });

  group('12. a double tap on Start', () {
    testWidgets('two taps on a gated store make one start', (tester) async {
      final gate = Completer<void>();
      late CountingGoalStore probe;
      final setup = await _ready(
        profile: maleProfile,
        readStoreOf: _counting((s) => probe = s, startGate: gate),
      );
      await pumpSetup(tester, setup);
      await tester.ensureVisible(find.byKey(GoalSetupKeys.start));
      await tester.pump();

      await tester.tap(find.byKey(GoalSetupKeys.start));
      await tester.tap(find.byKey(GoalSetupKeys.start));
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();

      expect(probe.starts, 1);
      expect(await setup.store.goals(), hasLength(1));
    });

    testWidgets('the setup never shows the picker while it saves', (
      tester,
    ) async {
      final read = Completer<void>();
      final setup = await _ready(
        readStoreOf: _counting((_) {}, readGate: read),
      );
      final router = await pumpSetup(tester, setup);
      await tapKey(tester, GoalSetupKeys.pregnancyNo);

      await _tapFrame(tester, GoalSetupKeys.start);
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(find.byType(GoalPickScreen, skipOffstage: false), findsNothing);
      }
      read.complete();
      await tester.pumpAndSettle();

      expect(whereIs(router), '/today');
      expect(find.byType(GoalPickScreen), findsNothing);
    });
  });

  group('13. the start fails', () {
    testWidgets('a throwing store shows the failure and keeps the choices', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final setup = await _ready(
        profile: maleProfile,
        readStoreOf: _counting((_) {}, startError: StateError('disk')),
      );
      final router = await pumpSetup(tester, setup);
      await tapKey(tester, GoalSetupKeys.paceGentle);
      await tapKey(tester, GoalSetupKeys.referenceAdd);

      await tapKey(tester, GoalSetupKeys.start);

      expect(whereIs(router), AppPaths.goalsSetup);
      expect(find.byKey(GoalSetupKeys.failed), findsOneWidget);
      expect(find.text(_failed), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(GoalSetupKeys.failed)),
        isSemantics(isLiveRegion: true),
      );
      expect(
        tester
            .getSemantics(find.byKey(GoalSetupKeys.paceGentle))
            .flagsCollection
            .isChecked,
        CheckedState.isTrue,
      );
      expect(find.byKey(GoalSetupKeys.referenceValue), findsOneWidget);
      expect(_enabled(tester, GoalSetupKeys.start), isTrue);
      expect(await setup.store.goals(), isEmpty);
      handle.dispose();
    });

    testWidgets('a retry after the failure goes through', (tester) async {
      var failures = 1;
      final setup = await _ready(
        profile: maleProfile,
        readStoreOf: (memory) => _FlakyStore(memory, () => failures-- > 0),
      );
      final router = await pumpSetup(tester, setup);
      await tapKey(tester, GoalSetupKeys.start);
      expect(find.byKey(GoalSetupKeys.failed), findsOneWidget);

      await tapKey(tester, GoalSetupKeys.start);

      expect(whereIs(router), '/today');
      expect(await setup.store.goals(), hasLength(1));
    });

    testWidgets('a store answering null shows the active line', (tester) async {
      final setup = await _ready(
        profile: maleProfile,
        readStoreOf: _counting((_) {}, startsNull: true),
      );
      final router = await pumpSetup(tester, setup);

      await tapKey(tester, GoalSetupKeys.start);

      expect(whereIs(router), AppPaths.goalsSetup);
      expect(find.text(_active), findsOneWidget);
      expect(find.text(_failed), findsNothing);
    });
  });

  group('14. demo mode', () {
    testWidgets('Start is disabled, the note shows and nothing is written', (
      tester,
    ) async {
      final setup = await _ready(profile: maleProfile, demo: true);
      await pumpSetup(tester, setup);

      expect(find.text(_demo), findsOneWidget);
      expect(find.byKey(GoalSetupKeys.start), findsOneWidget);
      expect(_enabled(tester, GoalSetupKeys.start), isFalse);
      await tester.tap(find.byKey(GoalSetupKeys.start), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(await setup.store.goals(), isEmpty);
      expect(await setup.store.screenings(), hasLength(1));
    });

    testWidgets('outside demo the note is absent', (tester) async {
      final setup = await _ready(profile: maleProfile);
      await pumpSetup(tester, setup);

      expect(find.text(_demo), findsNothing);
    });
  });

  group('15. the route shows the picker unless the setup applies', () {
    testWidgets('soft mode never asked shows the picker', (tester) async {
      final setup = await _ready(stored: false);
      await pumpSetup(tester, setup);

      expect(find.byType(GoalPickScreen), findsOneWidget);
      expect(find.byKey(GoalSetupKeys.start), findsNothing);
    });

    testWidgets('a stored soft mode yes shows the picker', (tester) async {
      final setup = await _ready(stored: false);
      await storeScreening(setup, soft: true);
      await pumpSetup(tester, setup);

      expect(find.byType(GoalPickScreen), findsOneWidget);
      expect(find.byKey(GoalSetupKeys.start), findsNothing);
    });

    testWidgets('a BMI under the floor shows the picker', (tester) async {
      final setup = await _ready(trendKg: 57.9);
      await pumpSetup(tester, setup);

      expect(find.byType(GoalPickScreen), findsOneWidget);
      expect(find.byKey(GoalSetupKeys.start), findsNothing);
    });

    testWidgets('Body off shows the picker', (tester) async {
      final setup = await _ready(modules: const {ModuleId.goals});
      await pumpSetup(tester, setup);

      expect(find.byType(GoalPickScreen), findsOneWidget);
    });

    testWidgets('an active goal shows the picker with the active line', (
      tester,
    ) async {
      final setup = await _ready(
        profile: maleProfile,
        draft: goalDraft(kind: GoalKind.getFitter, levers: const []),
      );
      await pumpSetup(tester, setup);

      expect(find.byType(GoalPickScreen), findsOneWidget);
      expect(find.text(_active), findsOneWidget);
      expect(find.byKey(GoalSetupKeys.start), findsNothing);
    });

    testWidgets('Goals off is an empty page', (tester) async {
      final setup = await _ready(modules: const {ModuleId.body});
      await pumpSetup(tester, setup);

      expect(find.byType(GoalPickScreen), findsNothing);
      expect(find.byKey(GoalSetupKeys.start), findsNothing);
      expect(find.byKey(GoalSetupKeys.pregnancyNo), findsNothing);
      expect(find.text(_paceTitle), findsNothing);
    });
  });

  group('semantics', () {
    testWidgets('the pace options are an exclusive group, Steady checked', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final setup = await _ready(profile: maleProfile);
      await pumpSetup(tester, setup);

      final steady = tester
          .getSemantics(find.byKey(GoalSetupKeys.paceStandard))
          .flagsCollection;
      final gentle = tester
          .getSemantics(find.byKey(GoalSetupKeys.paceGentle))
          .flagsCollection;
      expect(steady.isInMutuallyExclusiveGroup, isTrue);
      expect(steady.isChecked, CheckedState.isTrue);
      expect(gentle.isInMutuallyExclusiveGroup, isTrue);
      expect(gentle.isChecked, CheckedState.isFalse);
      handle.dispose();
    });

    testWidgets('the pregnancy answers are an exclusive group', (tester) async {
      final handle = tester.ensureSemantics();
      final setup = await _ready();
      await pumpSetup(tester, setup);

      for (final key in [
        GoalSetupKeys.pregnancyNo,
        GoalSetupKeys.pregnancyYes,
      ]) {
        final flags = tester.getSemantics(find.byKey(key)).flagsCollection;
        expect(flags.isInMutuallyExclusiveGroup, isTrue);
        expect(flags.isChecked, CheckedState.isFalse);
      }
      handle.dispose();
    });
  });

  group('17. layout', () {
    final states = <String, Future<GoalSetup> Function()>{
      'question': _ready,
      'plan': () => _ready(profile: maleProfile),
      'no trend': () => _ready(profile: maleProfile, trendKg: null),
      'no room': () => _ready(profile: maleProfile, trendKg: 59.2),
      'hidden': () => _ready(profile: maleProfile, hidden: true),
    };
    for (final scale in layoutScales) {
      for (final brightness in layoutBrightnesses) {
        for (final MapEntry(key: name, value: build) in states.entries) {
          testWidgets('$name at ${scale}x ${brightness.name}', (tester) async {
            final setup = await build();
            await pumpSetup(
              tester,
              setup,
              scale: scale,
              brightness: brightness,
              tall: false,
            );

            await expectNoLayoutOverflow(() async {
              await tester.drag(
                find.byType(Scrollable).first,
                const Offset(0, -4000),
              );
              await tester.pumpAndSettle();
            });

            expect(find.byType(GoalSetupScreen), findsOneWidget);
          });
        }

        testWidgets('reference stepper at ${scale}x ${brightness.name}', (
          tester,
        ) async {
          final setup = await _ready(profile: maleProfile);
          await pumpSetup(
            tester,
            setup,
            scale: scale,
            brightness: brightness,
            tall: false,
          );

          await expectNoLayoutOverflow(() async {
            await tapKey(tester, GoalSetupKeys.referenceAdd);
            await tester.ensureVisible(find.byKey(GoalSetupKeys.start));
            await tester.pumpAndSettle();
          });

          for (final key in [
            GoalSetupKeys.referenceDown,
            GoalSetupKeys.referenceUp,
            GoalSetupKeys.referenceRemove,
            GoalSetupKeys.start,
          ]) {
            await tester.ensureVisible(find.byKey(key));
            await tester.pump();
            expect(
              tester.getSize(find.byKey(key)).height,
              greaterThanOrEqualTo(48),
            );
            expect(
              tester.getSize(find.byKey(key)).width,
              greaterThanOrEqualTo(48),
            );
          }
        });
      }
    }
  });
}

final class _FlakyStore extends CountingGoalStore {
  new(super.inner, this.shouldFail);

  final bool Function() shouldFail;

  @override
  Future<Goal?> start(GoalDraft draft) async {
    if (shouldFail()) throw StateError('disk');
    return await inner.start(draft);
  }
}
