import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/open_score/application/celebration_providers.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/application/open_score_data_providers.dart';
import 'package:open_ring/features/open_score/application/week_goal_providers.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';

import '../../../helpers/open_score_fakes.dart';

const _monday = LocalDate(2026, 11, 9);
const _tuesday = LocalDate(2026, 11, 10);
const _closed = LocalDate(2026, 11, 15);

const _run = Key('run_clear');

class _Host extends ConsumerWidget {
  const new({required this.onResult});

  final ValueChanged<bool> onResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton(
    key: _run,
    onPressed: () => unawaited(clearOpenScoreData(ref).then(onResult)),
    child: const Text('run'),
  );
}

class _World {
  new({Map<LocalDate, DayTag> tags = const {}, int? goal, String? closed})
    : tagStore = SpyDayTagStore(tags),
      goalStore = SpyWeekGoalStore(goal),
      celebrationStore = SpyCelebrationStore(closed);

  final SpyDayTagStore tagStore;
  final SpyWeekGoalStore goalStore;
  final SpyCelebrationStore celebrationStore;
  bool? result;

  Future<ProviderContainer> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dayTagStoreProvider.overrideWithValue(tagStore),
          weekGoalStoreProvider.overrideWithValue(goalStore),
          celebrationStoreProvider.overrideWithValue(celebrationStore),
        ],
        child: MaterialApp(home: _Host(onResult: (value) => result = value)),
      ),
    );
    return ProviderScope.containerOf(tester.element(find.byKey(_run)));
  }
}

Future<void> _tapRun(WidgetTester tester) async {
  await tester.tap(find.byKey(_run));
  await tester.pumpAndSettle();
}

_World _seeded() => _World(
  tags: {_monday: DayTag.sick, _tuesday: DayTag.rest},
  goal: 6,
  closed: _closed.iso,
);

void main() {
  group('criterion 4: the tag count provider', () {
    testWidgets('reads the raw count of the tag store', (tester) async {
      final container = await _seeded().pump(tester);

      expect(await container.read(openScoreTagCountProvider.future), 2);
    });

    testWidgets('is 0 for an empty store', (tester) async {
      final container = await _World().pump(tester);

      expect(await container.read(openScoreTagCountProvider.future), 0);
    });

    testWidgets('re-reads the store when the data revision is bumped', (
      tester,
    ) async {
      final world = _seeded();
      final container = await world.pump(tester);
      expect(await container.read(openScoreTagCountProvider.future), 2);

      await world.tagStore.remove(_monday);
      container.read(dataRevisionProvider.notifier).bump();

      expect(await container.read(openScoreTagCountProvider.future), 1);
    });
  });

  group('criterion 5: after clearOpenScoreData', () {
    testWidgets('the goal is the default, the closed date null, no tags', (
      tester,
    ) async {
      final world = _seeded();
      final container = await world.pump(tester);
      expect(await container.read(weekGoalProvider.future), 6);
      expect(await container.read(celebrationClosedProvider.future), _closed);
      expect((await container.read(dayTagsProvider.future)).length, 2);

      await _tapRun(tester);

      expect(world.result, isTrue);
      expect(await container.read(weekGoalProvider.future), weekGoalDefault);
      expect(await container.read(celebrationClosedProvider.future), isNull);
      expect(await container.read(dayTagsProvider.future), isEmpty);
      expect(await container.read(openScoreTagCountProvider.future), 0);
    });

    testWidgets('the stores hold nothing and the revision moved once', (
      tester,
    ) async {
      final world = _seeded();
      final container = await world.pump(tester);
      final before = container.read(dataRevisionProvider);

      await _tapRun(tester);

      expect(await world.tagStore.count(), 0);
      expect(world.goalStore.goal, isNull);
      expect(world.celebrationStore.closed, isNull);
      expect(container.read(dataRevisionProvider), before + 1);
    });

    testWidgets('on empty stores it still returns true and bumps once', (
      tester,
    ) async {
      final world = _World();
      final container = await world.pump(tester);
      final before = container.read(dataRevisionProvider);

      await _tapRun(tester);

      expect(world.result, isTrue);
      expect(container.read(dataRevisionProvider), before + 1);
    });
  });

  group('criterion 6: a store that throws', () {
    testWidgets('the tag store throwing returns false and bumps once', (
      tester,
    ) async {
      final world = _seeded();
      world.tagStore.clearFailure = StateError('disk');
      final container = await world.pump(tester);
      expect(await container.read(weekGoalProvider.future), 6);
      final before = container.read(dataRevisionProvider);

      await _tapRun(tester);

      expect(world.result, isFalse);
      expect(world.tagStore.clearCalls, 1);
      expect(container.read(dataRevisionProvider), before + 1);
      expect(await world.tagStore.count(), 2);
      expect(await container.read(openScoreTagCountProvider.future), 2);
    });

    testWidgets('the goal store throwing after the tags returns false', (
      tester,
    ) async {
      final world = _seeded();
      world.goalStore.clearFailure = StateError('disk');
      final container = await world.pump(tester);
      expect(await container.read(weekGoalProvider.future), 6);
      final before = container.read(dataRevisionProvider);

      await _tapRun(tester);

      expect(world.result, isFalse);
      expect(await world.tagStore.count(), 0);
      expect(container.read(dataRevisionProvider), before + 1);
      expect(await container.read(openScoreTagCountProvider.future), 0);
      expect(await container.read(dayTagsProvider.future), isEmpty);
      expect(await container.read(weekGoalProvider.future), 6);
    });

    testWidgets('the celebration store throwing refreshes the goal too', (
      tester,
    ) async {
      final world = _seeded();
      world.celebrationStore.clearFailure = StateError('disk');
      final container = await world.pump(tester);
      expect(await container.read(weekGoalProvider.future), 6);
      expect(await container.read(celebrationClosedProvider.future), _closed);
      final before = container.read(dataRevisionProvider);

      await _tapRun(tester);

      expect(world.result, isFalse);
      expect(container.read(dataRevisionProvider), before + 1);
      expect(await world.tagStore.count(), 0);
      expect(await container.read(weekGoalProvider.future), weekGoalDefault);
      expect(await container.read(celebrationClosedProvider.future), _closed);
    });
  });
}
