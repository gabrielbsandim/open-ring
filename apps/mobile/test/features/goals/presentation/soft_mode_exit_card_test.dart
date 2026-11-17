import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/presentation/soft_mode_exit_card.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';

import '../../../helpers/layout_harness.dart';
import '../goal_fixtures.dart';
import '../goal_picker_harness.dart';

const _title = 'Soft mode';
const _body = 'Soft mode is on, so the app builds no weight goal.';
const _leave = 'Leave soft mode';
const _confirmTitle = 'Leave soft mode?';
const _confirmBody =
    'Weight goals become available again. The five questions are not asked again, and the earlier answer stays in the history.';
const _confirm = 'Leave';
const _cancel = 'Cancel';
const _failed = 'Soft mode could not be turned off. Try again.';

GoalScreening _row(int day, {bool? softMode, bool? pregnant}) => GoalScreening(
  on: goalDay(12, day),
  softMode: softMode,
  pregnantOrBreastfeeding: pregnant,
);

Future<GoalSetup> _setup({
  bool? soft = true,
  Set<ModuleId> modules = goalModules,
  Completer<void>? gate,
  int failures = 0,
}) async {
  final memory = InMemoryGoalStore();
  if (soft != null) await memory.addScreening(_row(1, softMode: soft));
  return setupPicker(
    modules: modules,
    store: memory,
    readStoreOf: (inner) =>
        ProbeGoalStore(inner, screeningGate: gate, screeningFailures: failures),
  );
}

Future<void> _pump(
  WidgetTester tester,
  GoalSetup setup, {
  double scale = 1,
  Brightness brightness = Brightness.dark,
}) => pumpScaled(
  tester,
  UncontrolledProviderScope(
    container: setup.container,
    child: screenHost(
      const Scaffold(body: SingleChildScrollView(child: SoftModeExitCard())),
    ),
  ),
  textScaler: TextScaler.linear(scale),
  brightness: brightness,
  locale: const Locale('en'),
  overrides: const [],
);

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pump();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<int> _rows(GoalSetup setup) async =>
    (await setup.store.screenings()).length;

void main() {
  group('4. when the card shows', () {
    testWidgets('Goals on and a soft yes show title, body and the button', (
      tester,
    ) async {
      final setup = await _setup();
      await _pump(tester, setup);

      expect(find.text(_title), findsOneWidget);
      expect(find.text(_body), findsOneWidget);
      expect(find.byKey(SoftModeExitKeys.leave), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(SoftModeExitKeys.leave),
          matching: find.text(_leave),
        ),
        findsOneWidget,
      );
    });

    final hidden = <String, ({bool? soft, Set<ModuleId> modules})>{
      'a soft false': (soft: false, modules: goalModules),
      'no soft answer': (soft: null, modules: goalModules),
      'Goals off with a yes': (soft: true, modules: const {ModuleId.body}),
    };
    for (final MapEntry(key: name, value: state) in hidden.entries) {
      testWidgets('$name shows nothing', (tester) async {
        final setup = await _setup(soft: state.soft, modules: state.modules);
        await _pump(tester, setup);

        expect(find.text(_title), findsNothing);
        expect(find.byKey(SoftModeExitKeys.leave), findsNothing);
      });
    }

    testWidgets('the copy states the state and never advises leaving', (
      tester,
    ) async {
      final setup = await _setup();
      await _pump(tester, setup);

      final text = allText(tester).toLowerCase();
      for (final word in ['should', 'recommend', 'we suggest', 'try ']) {
        expect(text.contains(word), isFalse, reason: word);
      }
    });
  });

  group('5. leave then cancel', () {
    testWidgets('closes the dialog, writes nothing and keeps the card', (
      tester,
    ) async {
      final setup = await _setup();
      await _pump(tester, setup);

      await _tap(tester, SoftModeExitKeys.leave);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(_confirmTitle), findsOneWidget);
      expect(find.text(_confirmBody), findsOneWidget);
      await _tap(tester, SoftModeExitKeys.cancel);

      expect(find.byType(AlertDialog), findsNothing);
      expect(await _rows(setup), 1);
      expect(find.text(_title), findsOneWidget);
      expect(find.byKey(SoftModeExitKeys.leave), findsOneWidget);
    });

    testWidgets('the dialog buttons carry their labels', (tester) async {
      final setup = await _setup();
      await _pump(tester, setup);

      await _tap(tester, SoftModeExitKeys.leave);

      expect(
        find.descendant(
          of: find.byKey(SoftModeExitKeys.confirm),
          matching: find.text(_confirm),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(SoftModeExitKeys.cancel),
          matching: find.text(_cancel),
        ),
        findsOneWidget,
      );
    });
  });

  group('6. leave then confirm', () {
    testWidgets('writes one row with soft mode false and hides the card', (
      tester,
    ) async {
      final setup = await _setup();
      await _pump(tester, setup);

      await _tap(tester, SoftModeExitKeys.leave);
      await _tap(tester, SoftModeExitKeys.confirm);

      final rows = await setup.store.screenings();
      expect(rows, hasLength(2));
      expect(rows.first.softMode, isFalse);
      expect(rows.first.on, goalDay(12, 7));
      expect(setup.revision, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(_title), findsNothing);
      expect(find.byKey(SoftModeExitKeys.leave), findsNothing);
    });
  });

  group('7. a double tap on confirm', () {
    testWidgets('two taps before a pump write one row', (tester) async {
      final gate = Completer<void>();
      final setup = await _setup(gate: gate);
      await _pump(tester, setup);
      await _tap(tester, SoftModeExitKeys.leave);

      await tester.tap(find.byKey(SoftModeExitKeys.confirm));
      await tester.tap(
        find.byKey(SoftModeExitKeys.confirm),
        warnIfMissed: false,
      );
      gate.complete();
      await tester.pumpAndSettle();

      expect(await _rows(setup), 2);
      expect(setup.revision, 1);
    });
  });

  group('8. a store that throws', () {
    testWidgets('keeps the card, shows the failure and writes nothing', (
      tester,
    ) async {
      final setup = await _setup(failures: 1);
      await _pump(tester, setup);

      await _tap(tester, SoftModeExitKeys.leave);
      await _tap(tester, SoftModeExitKeys.confirm);

      expect(find.text(_title), findsOneWidget);
      expect(find.byKey(SoftModeExitKeys.leave), findsOneWidget);
      expect(find.byKey(SoftModeExitKeys.failed), findsOneWidget);
      expect(find.text(_failed), findsOneWidget);
      expect(await _rows(setup), 1);
      expect(setup.revision, 0);
    });

    testWidgets('a retry writes one row and clears the failure', (
      tester,
    ) async {
      final setup = await _setup(failures: 1);
      await _pump(tester, setup);
      await _tap(tester, SoftModeExitKeys.leave);
      await _tap(tester, SoftModeExitKeys.confirm);

      await _tap(tester, SoftModeExitKeys.leave);
      await _tap(tester, SoftModeExitKeys.confirm);

      final rows = await setup.store.screenings();
      expect(rows, hasLength(2));
      expect(rows.first.softMode, isFalse);
      expect(find.text(_failed), findsNothing);
      expect(find.text(_title), findsNothing);
    });

    testWidgets('the failure is a live region', (tester) async {
      final handle = tester.ensureSemantics();
      final setup = await _setup(failures: 1);
      await _pump(tester, setup);
      await _tap(tester, SoftModeExitKeys.leave);
      await _tap(tester, SoftModeExitKeys.confirm);

      expect(
        tester.getSemantics(find.byKey(SoftModeExitKeys.failed)),
        isSemantics(isLiveRegion: true),
      );
      handle.dispose();
    });
  });

  group('9. semantics', () {
    testWidgets('the title is a header', (tester) async {
      final handle = tester.ensureSemantics();
      final setup = await _setup();
      await _pump(tester, setup);

      expect(
        tester.getSemantics(find.text(_title)),
        isSemantics(label: _title, isHeader: true),
      );
      handle.dispose();
    });

    testWidgets('the leave button has its label', (tester) async {
      final handle = tester.ensureSemantics();
      final setup = await _setup();
      await _pump(tester, setup);

      expect(
        tester.getSemantics(find.byKey(SoftModeExitKeys.leave)),
        isSemantics(label: _leave, isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });
  });

  group('10. layout', () {
    for (final scale in layoutScales) {
      for (final brightness in layoutBrightnesses) {
        testWidgets('the card at ${scale}x ${brightness.name}', (tester) async {
          final setup = await _setup();
          await _pump(tester, setup, scale: scale, brightness: brightness);

          expect(find.byKey(SoftModeExitKeys.leave), findsOneWidget);
        });

        testWidgets('the dialog at ${scale}x ${brightness.name}', (
          tester,
        ) async {
          final setup = await _setup();
          await _pump(tester, setup, scale: scale, brightness: brightness);

          await expectNoLayoutOverflow(
            () => _tap(tester, SoftModeExitKeys.leave),
          );

          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.byKey(SoftModeExitKeys.confirm), findsOneWidget);
        });
      }
    }
  });
}
