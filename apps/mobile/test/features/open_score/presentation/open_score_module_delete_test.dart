import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';
import 'package:open_ring/features/open_score/application/celebration_providers.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/application/week_goal_providers.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';
import 'package:open_ring/features/open_score/presentation/open_score_module_screen.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/open_score_fakes.dart';
import '../../../helpers/settings_fakes.dart';

const _monday = LocalDate(2026, 11, 9);
const _tuesday = LocalDate(2026, 11, 10);
const _closed = LocalDate(2026, 11, 15);

const _emptyText = 'No day tags stored on this phone.';
const _deleteTitle = 'Delete the Open Score data?';
const _deleteBody =
    'Day tags to delete: 2. The weekly goal goes back to 4 of 7. This cannot '
    'be undone. A tag older than 6 days cannot be set again, and the Level, '
    'the bests and the averages count those days again.';
const _deleted = 'Open Score data deleted.';
const _failed = 'The Open Score data could not be deleted. Try again.';

class _World {
  new({
    Map<LocalDate, DayTag> tags = const {},
    int? goal,
    String? closed,
    bool on = false,
  }) : tagStore = SpyDayTagStore(tags),
       goalStore = SpyWeekGoalStore(goal),
       celebrationStore = SpyCelebrationStore(closed),
       modules = InMemoryModuleStore({if (on) ModuleId.openScore});

  final SpyDayTagStore tagStore;
  final SpyWeekGoalStore goalStore;
  final SpyCelebrationStore celebrationStore;
  final InMemoryModuleStore modules;
}

_World _stored({bool on = false}) => _World(
  tags: {_monday: DayTag.sick, _tuesday: DayTag.rest},
  goal: 6,
  closed: _closed.iso,
  on: on,
);

Future<void> _pump(
  WidgetTester tester,
  _World world, {
  Locale locale = const Locale('en'),
  double scale = 1,
  Brightness brightness = Brightness.dark,
}) => pumpScaled(
  tester,
  screenHost(const OpenScoreModuleScreen()),
  textScaler: TextScaler.linear(scale),
  brightness: brightness,
  locale: locale,
  overrides: [
    moduleStoreProvider.overrideWithValue(world.modules),
    dayTagStoreProvider.overrideWithValue(world.tagStore),
    weekGoalStoreProvider.overrideWithValue(world.goalStore),
    celebrationStoreProvider.overrideWithValue(world.celebrationStore),
  ],
);

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(OpenScoreModuleScreen)),
);

int _revision(WidgetTester tester) =>
    _container(tester).read(dataRevisionProvider);

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

Future<void> _tap(WidgetTester tester, Key key) async {
  await reveal(tester, find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> _openDialog(WidgetTester tester) =>
    _tap(tester, OpenScoreModuleKeys.delete);

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.byKey(OpenScoreModuleKeys.deleteConfirm));
  await tester.pumpAndSettle();
}

void main() {
  for (final on in [false, true]) {
    final state = on ? 'module on' : 'module off';

    group('criterion 1: nothing stored, $state', () {
      testWidgets('shows the empty text and no delete action', (tester) async {
        await _pump(tester, _World(on: on));

        expect(find.byKey(OpenScoreModuleKeys.kept), findsNothing);
        await reveal(tester, find.byKey(OpenScoreModuleKeys.toggle));
        await reveal(tester, find.byKey(OpenScoreModuleKeys.stored));
        expect(find.text('Open Score data'), findsOneWidget);
        expect(find.text(_emptyText), findsOneWidget);
        expect(find.byKey(OpenScoreModuleKeys.delete), findsNothing);
        expect(find.byKey(OpenScoreModuleKeys.goal), findsNothing);
      });

      testWidgets('an explicit goal of 4 counts as the default', (
        tester,
      ) async {
        await _pump(tester, _World(goal: 4, on: on));

        await reveal(tester, find.byKey(OpenScoreModuleKeys.toggle));
        await reveal(tester, find.byKey(OpenScoreModuleKeys.stored));
        expect(find.text(_emptyText), findsOneWidget);
        expect(find.byKey(OpenScoreModuleKeys.delete), findsNothing);
        expect(find.byKey(OpenScoreModuleKeys.goal), findsNothing);
      });

      testWidgets('a count that cannot be read is not shown as empty', (
        tester,
      ) async {
        final world = _World(tags: {_monday: DayTag.sick}, on: on);
        world.tagStore.countFailure = StateError('disk');
        await _pump(tester, world);

        expect(find.byKey(OpenScoreModuleKeys.kept), findsNothing);
        await reveal(tester, find.byKey(OpenScoreModuleKeys.toggle));
        await reveal(tester, find.byKey(OpenScoreModuleKeys.stored));
        expect(find.text(_emptyText), findsNothing);
        expect(
          find.text(
            'The Open Score data could not be read. Close the app and open '
            'it again.',
          ),
          findsOneWidget,
        );
        expect(find.byKey(OpenScoreModuleKeys.delete), findsNothing);
      });
    });
  }

  group('criterion 2: something stored', () {
    testWidgets('tags only, module on: the count line and the delete', (
      tester,
    ) async {
      await _pump(
        tester,
        _World(tags: {_monday: DayTag.sick, _tuesday: DayTag.rest}, on: true),
      );

      await reveal(tester, find.byKey(OpenScoreModuleKeys.stored));
      expect(find.text('Day tags stored on this phone: 2.'), findsOneWidget);
      expect(find.text(_emptyText), findsNothing);
      expect(find.byKey(OpenScoreModuleKeys.goal), findsNothing);
      expect(find.byKey(OpenScoreModuleKeys.kept), findsNothing);
      await reveal(tester, find.byKey(OpenScoreModuleKeys.delete));
      expect(find.text('Delete Open Score data'), findsOneWidget);
    });

    testWidgets('one tag shows 1', (tester) async {
      await _pump(tester, _World(tags: {_monday: DayTag.sick}, on: true));

      await reveal(tester, find.byKey(OpenScoreModuleKeys.stored));
      expect(find.text('Day tags stored on this phone: 1.'), findsOneWidget);
    });

    testWidgets('a changed goal alone shows the goal line and the delete', (
      tester,
    ) async {
      await _pump(tester, _World(goal: 6, on: true));

      await reveal(tester, find.byKey(OpenScoreModuleKeys.stored));
      expect(find.text(_emptyText), findsOneWidget);
      await reveal(tester, find.byKey(OpenScoreModuleKeys.goal));
      expect(find.text('Weekly goal: 6 of 7 days.'), findsOneWidget);
      await reveal(tester, find.byKey(OpenScoreModuleKeys.delete));
      expect(find.byKey(OpenScoreModuleKeys.delete), findsOneWidget);
    });

    testWidgets('a goal below the default also counts as changed', (
      tester,
    ) async {
      await _pump(tester, _World(goal: 3, on: true));

      await reveal(tester, find.byKey(OpenScoreModuleKeys.goal));
      expect(find.text('Weekly goal: 3 of 7 days.'), findsOneWidget);
      await reveal(tester, find.byKey(OpenScoreModuleKeys.delete));
      expect(find.byKey(OpenScoreModuleKeys.delete), findsOneWidget);
    });

    testWidgets('tags with the default goal show no goal line', (tester) async {
      await _pump(tester, _World(tags: {_monday: DayTag.sick}, goal: 4));

      await reveal(tester, find.byKey(OpenScoreModuleKeys.delete));
      expect(find.byKey(OpenScoreModuleKeys.delete), findsOneWidget);
      expect(find.byKey(OpenScoreModuleKeys.stored), findsOneWidget);
      expect(find.byKey(OpenScoreModuleKeys.goal), findsNothing);
    });

    testWidgets('module off with tags: the kept card and the delete', (
      tester,
    ) async {
      await _pump(tester, _stored());

      expect(find.byKey(OpenScoreModuleKeys.kept), findsOneWidget);
      expect(
        find.text(
          'Open Score is off. Day tags kept on this phone: 2. They count '
          'again when you turn it on.',
        ),
        findsOneWidget,
      );
      await reveal(tester, find.byKey(OpenScoreModuleKeys.delete));
      expect(find.byKey(OpenScoreModuleKeys.delete), findsOneWidget);
    });

    testWidgets('module off with only a changed goal has no kept card', (
      tester,
    ) async {
      await _pump(tester, _World(goal: 6));

      expect(find.byKey(OpenScoreModuleKeys.kept), findsNothing);
      await reveal(tester, find.byKey(OpenScoreModuleKeys.delete));
      expect(find.byKey(OpenScoreModuleKeys.delete), findsOneWidget);
    });

    testWidgets('module on with tags has no kept card', (tester) async {
      await _pump(tester, _stored(on: true));

      expect(find.byKey(OpenScoreModuleKeys.kept), findsNothing);
    });

    testWidgets('the kept card sits above the facts cards', (tester) async {
      await _pump(tester, _stored());

      final kept = tester.getTopLeft(find.byKey(OpenScoreModuleKeys.kept));
      final facts = tester.getTopLeft(find.text('What it adds').first);
      expect(kept.dy, lessThan(facts.dy));
    });
  });

  group('criterion 3: the dialog', () {
    testWidgets('names the tags, the goal reset and the consequences', (
      tester,
    ) async {
      await _pump(tester, _stored(on: true));
      await _openDialog(tester);

      expect(find.text(_deleteTitle), findsOneWidget);
      expect(find.text(_deleteBody), findsOneWidget);
      expect(find.byKey(OpenScoreModuleKeys.deleteCancel), findsOneWidget);
      expect(find.byKey(OpenScoreModuleKeys.deleteConfirm), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('cancelling writes nothing', (tester) async {
      final world = _stored(on: true);
      await _pump(tester, world);
      await _openDialog(tester);
      final before = _revision(tester);
      await tester.tap(find.byKey(OpenScoreModuleKeys.deleteCancel));
      await tester.pumpAndSettle();

      expect(world.tagStore.clearCalls, 0);
      expect(world.goalStore.clearCalls, 0);
      expect(world.celebrationStore.clearCalls, 0);
      expect(await world.tagStore.count(), 2);
      expect(world.goalStore.goal, 6);
      expect(world.celebrationStore.closed, _closed.iso);
      expect(_revision(tester), before);
      expect(find.text(_deleted), findsNothing);
      expect(find.text(_failed), findsNothing);
      expect(find.byKey(OpenScoreModuleKeys.delete), findsOneWidget);
    });
  });

  group('criterion 4: confirming', () {
    testWidgets('clears the stores, says so, bumps once, keeps it on', (
      tester,
    ) async {
      final world = _stored(on: true);
      await _pump(tester, world);
      await _openDialog(tester);
      final before = _revision(tester);
      await _confirm(tester);

      expect(await world.tagStore.count(), 0);
      expect(world.goalStore.goal, isNull);
      expect(world.celebrationStore.closed, isNull);
      expect(world.tagStore.clearCalls, 1);
      expect(world.goalStore.clearCalls, 1);
      expect(world.celebrationStore.clearCalls, 1);
      expect(_revision(tester), before + 1);
      expect(await world.modules.read(), {ModuleId.openScore});
      expect(find.text(_deleted), findsOneWidget);
      await reveal(tester, find.byKey(OpenScoreModuleKeys.stored));
      expect(find.text(_emptyText), findsOneWidget);
      expect(find.byKey(OpenScoreModuleKeys.goal), findsNothing);
      expect(find.byKey(OpenScoreModuleKeys.delete), findsNothing);
    });

    testWidgets('with the module off it deletes, keeps it off, drops kept', (
      tester,
    ) async {
      final world = _stored();
      await _pump(tester, world);
      await _openDialog(tester);
      final before = _revision(tester);
      await _confirm(tester);

      expect(await world.tagStore.count(), 0);
      expect(world.goalStore.goal, isNull);
      expect(world.celebrationStore.closed, isNull);
      expect(_revision(tester), before + 1);
      expect(await world.modules.read(), isEmpty);
      expect(find.byKey(OpenScoreModuleKeys.stored), findsOneWidget);
      expect(find.byKey(OpenScoreModuleKeys.delete), findsNothing);
      expect(find.text(_deleted), findsOneWidget);
      await _toTop(tester);
      expect(find.byType(ModuleStatePill), findsOneWidget);
      expect(find.byKey(OpenScoreModuleKeys.kept), findsNothing);
    });

    testWidgets('a goal-only delete resets the goal and bumps once', (
      tester,
    ) async {
      final world = _World(goal: 6, on: true);
      await _pump(tester, world);
      await _openDialog(tester);
      final before = _revision(tester);
      await _confirm(tester);

      expect(world.goalStore.goal, isNull);
      expect(_revision(tester), before + 1);
      expect(find.byKey(OpenScoreModuleKeys.delete), findsNothing);
      expect(find.byKey(OpenScoreModuleKeys.goal), findsNothing);
    });
  });

  group('criterion 5: the providers after confirming', () {
    testWidgets('goal is 4, closed date null, tags empty', (tester) async {
      final world = _stored(on: true);
      await _pump(tester, world);
      final container = _container(tester);
      expect(await container.read(weekGoalProvider.future), 6);
      expect(await container.read(celebrationClosedProvider.future), _closed);
      expect(await container.read(dayTagsProvider.future), hasLength(2));

      await _openDialog(tester);
      await _confirm(tester);

      expect(await container.read(weekGoalProvider.future), weekGoalDefault);
      expect(await container.read(celebrationClosedProvider.future), isNull);
      expect(await container.read(dayTagsProvider.future), isEmpty);
    });
  });

  group('criterion 6: a store that throws', () {
    testWidgets('the tag store throwing says it failed and refreshes', (
      tester,
    ) async {
      final world = _stored(on: true);
      world.tagStore.clearFailure = StateError('disk');
      await _pump(tester, world);
      await _openDialog(tester);
      final before = _revision(tester);
      await _confirm(tester);

      expect(world.tagStore.clearCalls, 1);
      expect(find.text(_failed), findsOneWidget);
      expect(find.text(_deleted), findsNothing);
      expect(_revision(tester), before + 1);
      expect(await world.tagStore.count(), 2);
      await reveal(tester, find.byKey(OpenScoreModuleKeys.stored));
      expect(find.text('Day tags stored on this phone: 2.'), findsOneWidget);
      expect(find.byKey(OpenScoreModuleKeys.delete), findsOneWidget);
      expect(await world.modules.read(), {ModuleId.openScore});
    });

    testWidgets('the goal store throwing after the tags were cleared', (
      tester,
    ) async {
      final world = _stored(on: true);
      world.goalStore.clearFailure = StateError('disk');
      await _pump(tester, world);
      await _openDialog(tester);
      final before = _revision(tester);
      await _confirm(tester);

      expect(find.text(_failed), findsOneWidget);
      expect(find.text(_deleted), findsNothing);
      expect(await world.tagStore.count(), 0);
      expect(world.goalStore.goal, 6);
      expect(_revision(tester), before + 1);
      await reveal(tester, find.byKey(OpenScoreModuleKeys.stored));
      expect(find.text(_emptyText), findsOneWidget);
      await reveal(tester, find.byKey(OpenScoreModuleKeys.goal));
      expect(find.text('Weekly goal: 6 of 7 days.'), findsOneWidget);
      expect(find.byKey(OpenScoreModuleKeys.delete), findsOneWidget);
    });

    testWidgets('the celebration store throwing says it failed', (
      tester,
    ) async {
      final world = _stored(on: true);
      world.celebrationStore.clearFailure = StateError('disk');
      await _pump(tester, world);
      await _openDialog(tester);
      final before = _revision(tester);
      await _confirm(tester);

      expect(find.text(_failed), findsOneWidget);
      expect(find.text(_deleted), findsNothing);
      expect(await world.tagStore.count(), 0);
      expect(world.goalStore.goal, isNull);
      expect(_revision(tester), before + 1);
    });

    testWidgets('with the module off a failure keeps the kept card', (
      tester,
    ) async {
      final world = _stored();
      world.tagStore.clearFailure = StateError('disk');
      await _pump(tester, world);
      await _openDialog(tester);
      await _confirm(tester);

      expect(find.text(_failed), findsOneWidget);
      await _toTop(tester);
      expect(find.byKey(OpenScoreModuleKeys.kept), findsOneWidget);
      expect(await world.modules.read(), isEmpty);
    });
  });

  group('criterion 9: layout', () {
    for (final locale in AppLocales.supported) {
      for (final scale in layoutScales) {
        for (final brightness in Brightness.values) {
          final name = '$locale ${scale}x ${brightness.name}';

          testWidgets('fits with data, module off: $name', (tester) async {
            await _pump(
              tester,
              _stored(),
              locale: locale,
              scale: scale,
              brightness: brightness,
            );
            await scrollThrough(tester);

            expect(find.byType(OpenScoreModuleScreen), findsOneWidget);
          });

          testWidgets('fits with data, module on, dialog: $name', (
            tester,
          ) async {
            await _pump(
              tester,
              _stored(on: true),
              locale: locale,
              scale: scale,
              brightness: brightness,
            );
            await scrollThrough(tester);
            await _toTop(tester);
            await tester.scrollUntilVisible(
              find.byKey(OpenScoreModuleKeys.delete),
              400,
              scrollable: find.byType(Scrollable).first,
              maxScrolls: 200,
            );
            await tester.ensureVisible(find.byKey(OpenScoreModuleKeys.delete));
            await tester.pumpAndSettle();
            await expectNoLayoutOverflow(() async {
              await tester.tap(find.byKey(OpenScoreModuleKeys.delete));
              await tester.pumpAndSettle();
            });

            expect(
              find.byKey(OpenScoreModuleKeys.deleteConfirm),
              findsOneWidget,
            );
          });

          testWidgets('fits empty: $name', (tester) async {
            await _pump(
              tester,
              _World(),
              locale: locale,
              scale: scale,
              brightness: brightness,
            );
            await scrollThrough(tester);

            expect(find.byType(OpenScoreModuleScreen), findsOneWidget);
          });
        }
      }
    }
  });
}
