import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/activity/application/step_goal_history_providers.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/activity/domain/step_goal_history.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

const _dec7 = LocalDate(2026, 12, 7);
final _clock = DateTime.utc(2026, 12, 7, 12);

final class _FailingStore implements UserProfileStore {
  new(this.profile);

  final UserProfile? profile;

  @override
  Future<UserProfile?> read() async => profile;

  @override
  Future<void> save(UserProfile profile, {required DateTime at}) =>
      Future.error(StateError('disk full'));
}

({
  ProviderContainer container,
  InMemoryStepGoalHistory history,
  UserProfileStore store,
})
_setup({UserProfileStore? store}) {
  final history = InMemoryStepGoalHistory();
  final profileStore = store ?? InMemoryUserProfileStore();
  final container = ProviderContainer.test(
    overrides: [
      clockProvider.overrideWithValue(() => _clock),
      userProfileStoreProvider.overrideWithValue(profileStore),
      stepGoalHistoryProvider.overrideWithValue(history),
    ],
  );
  return (container: container, history: history, store: profileStore);
}

void main() {
  test('saving a new goal writes the baseline and the change', () async {
    final (:container, :history, store: _) = _setup();
    await container.read(userProfileProvider.future);

    await container
        .read(userProfileProvider.notifier)
        .save(const UserProfile(dailyStepGoal: 10000));

    expect(await history.changes(), [
      (from: stepGoalBaselineDate, steps: 8000),
      (from: _dec7, steps: 10000),
    ]);
    expect(container.read(userProfileProvider).value?.dailyStepGoal, 10000);
  });

  test('the baseline is the goal the profile held before the save', () async {
    final (:container, :history, store: _) = _setup(
      store: InMemoryUserProfileStore(const UserProfile(dailyStepGoal: 9000)),
    );
    await container.read(userProfileProvider.future);

    await container
        .read(userProfileProvider.notifier)
        .save(const UserProfile(dailyStepGoal: 12000));

    expect(await history.changes(), [
      (from: stepGoalBaselineDate, steps: 9000),
      (from: _dec7, steps: 12000),
    ]);
  });

  test('a weight only edit writes no row', () async {
    final (:container, :history, store: _) = _setup(
      store: InMemoryUserProfileStore(const UserProfile(dailyStepGoal: 10000)),
    );
    await container.read(userProfileProvider.future);

    await container
        .read(userProfileProvider.notifier)
        .save(const UserProfile(dailyStepGoal: 10000, weightKilograms: 70));

    expect(await history.changes(), isEmpty);
    expect(container.read(userProfileProvider).value?.weightKilograms, 70);
  });

  test('a first save without a goal writes no row', () async {
    final (:container, :history, store: _) = _setup();
    await container.read(userProfileProvider.future);

    await container
        .read(userProfileProvider.notifier)
        .save(const UserProfile(weightKilograms: 70));

    expect(await history.changes(), isEmpty);
  });

  test('saving the default goal over an unset one writes no row', () async {
    final (:container, :history, store: _) = _setup();
    await container.read(userProfileProvider.future);

    await container
        .read(userProfileProvider.notifier)
        .save(const UserProfile(dailyStepGoal: defaultStepGoal));

    expect(await history.changes(), isEmpty);
  });

  test('clearing the goal writes a row with the default goal', () async {
    final (:container, :history, store: _) = _setup(
      store: InMemoryUserProfileStore(const UserProfile(dailyStepGoal: 10000)),
    );
    await container.read(userProfileProvider.future);

    await container
        .read(userProfileProvider.notifier)
        .save(const UserProfile());

    expect(await history.changes(), [
      (from: stepGoalBaselineDate, steps: 10000),
      (from: _dec7, steps: defaultStepGoal),
    ]);
  });

  test('two edits on one day leave one row with the last value', () async {
    final (:container, :history, store: _) = _setup();
    await container.read(userProfileProvider.future);
    final controller = container.read(userProfileProvider.notifier);

    await controller.save(const UserProfile(dailyStepGoal: 10000));
    await controller.save(const UserProfile(dailyStepGoal: 9000));

    expect(await history.changes(), [
      (from: stepGoalBaselineDate, steps: 8000),
      (from: _dec7, steps: 9000),
    ]);
  });

  test('a failed profile save keeps the row and rethrows', () async {
    final (:container, :history, store: _) = _setup(store: _FailingStore(null));
    await container.read(userProfileProvider.future);

    await expectLater(
      container
          .read(userProfileProvider.notifier)
          .save(const UserProfile(dailyStepGoal: 10000)),
      throwsA(isA<StateError>()),
    );

    expect(await history.changes(), [
      (from: stepGoalBaselineDate, steps: 8000),
      (from: _dec7, steps: 10000),
    ]);
    expect(container.read(userProfileProvider).value, isNull);
  });

  test(
    'the changes provider reflects a save without a manual refresh',
    () async {
      final (:container, history: _, store: _) = _setup();
      await container.read(userProfileProvider.future);
      expect(await container.read(stepGoalChangesProvider.future), isEmpty);

      await container
          .read(userProfileProvider.notifier)
          .save(const UserProfile(dailyStepGoal: 10000));

      expect(await container.read(stepGoalChangesProvider.future), [
        (from: stepGoalBaselineDate, steps: 8000),
        (from: _dec7, steps: 10000),
      ]);
    },
  );

  test(
    'a save after a failed one brings the history back to the profile',
    () async {
      final history = InMemoryStepGoalHistory();
      await history.record(on: _dec7, steps: 10000, previous: 8000);
      final container = ProviderContainer.test(
        overrides: [
          clockProvider.overrideWithValue(() => _clock),
          userProfileStoreProvider.overrideWithValue(
            InMemoryUserProfileStore(),
          ),
          stepGoalHistoryProvider.overrideWithValue(history),
        ],
      );
      await container.read(userProfileProvider.future);

      await container
          .read(userProfileProvider.notifier)
          .save(const UserProfile(heightCentimeters: 178));

      expect(await history.changes(), [
        (from: stepGoalBaselineDate, steps: 8000),
        (from: _dec7, steps: defaultStepGoal),
      ]);
    },
  );

  group('with the date gone back behind the newest row', () {
    const dec9 = LocalDate(2026, 12, 9);

    Future<(ProviderContainer, InMemoryStepGoalHistory)> behind() async {
      final history = InMemoryStepGoalHistory();
      await history.record(on: dec9, steps: 10000, previous: 8000);
      final container = ProviderContainer.test(
        overrides: [
          clockProvider.overrideWithValue(() => _clock),
          userProfileStoreProvider.overrideWithValue(
            InMemoryUserProfileStore(const UserProfile(dailyStepGoal: 10000)),
          ),
          stepGoalHistoryProvider.overrideWithValue(history),
        ],
      );
      await container.read(userProfileProvider.future);
      return (container, history);
    }

    test('a new goal replaces the newest row and removes nothing', () async {
      final (container, history) = await behind();

      await container
          .read(userProfileProvider.notifier)
          .save(const UserProfile(dailyStepGoal: 12000));

      expect(await history.changes(), [
        (from: stepGoalBaselineDate, steps: 8000),
        (from: dec9, steps: 12000),
      ]);
    });

    test('a save that keeps the goal writes nothing', () async {
      final (container, history) = await behind();

      await container
          .read(userProfileProvider.notifier)
          .save(
            const UserProfile(dailyStepGoal: 10000, heightCentimeters: 178),
          );

      expect(await history.changes(), [
        (from: stepGoalBaselineDate, steps: 8000),
        (from: dec9, steps: 10000),
      ]);
    });

    test('a goal equal to the one of the older day still replaces the newest '
        'row', () async {
      final (container, history) = await behind();

      await container
          .read(userProfileProvider.notifier)
          .save(const UserProfile(dailyStepGoal: 8000));

      expect(await history.changes(), [
        (from: stepGoalBaselineDate, steps: 8000),
        (from: dec9, steps: 8000),
      ]);
    });
  });

  test(
    'the row is dated by the clock at the save, not by a cached date',
    () async {
      var now = DateTime.utc(2026, 12, 6, 23, 50);
      final history = InMemoryStepGoalHistory();
      final container = ProviderContainer.test(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          userProfileStoreProvider.overrideWithValue(
            InMemoryUserProfileStore(),
          ),
          stepGoalHistoryProvider.overrideWithValue(history),
        ],
      );
      await container.read(userProfileProvider.future);
      expect(container.read(currentDateProvider), const LocalDate(2026, 12, 6));
      now = DateTime.utc(2026, 12, 7, 0, 10);

      await container
          .read(userProfileProvider.notifier)
          .save(const UserProfile(dailyStepGoal: 10000));

      expect(await history.changes(), [
        (from: stepGoalBaselineDate, steps: 8000),
        (from: _dec7, steps: 10000),
      ]);
    },
  );
}
