import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/body/domain/weigh_in_store.dart';
import 'package:open_ring/features/energy/application/energy_providers.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

import '../../../helpers/metrics_fakes.dart';

const _other = 'com.example.other';
const _day = LocalDate(2026, 11, 10);
final _from = DateTime.utc(2026, 11, 10);
final _noon = DateTime.utc(2026, 11, 10, 12);

final class _Own implements WorkoutHistoryReader {
  new(this.items);

  final List<WorkoutListItem> items;

  @override
  Future<List<WorkoutListItem>> intersecting({
    required DateTime from,
    required DateTime to,
  }) async => [
    for (final item in items)
      if (item.end.isAfter(from) && item.start.isBefore(to)) item,
  ]..sort((a, b) => a.start.compareTo(b.start));

  @override
  Future<List<WorkoutListItem>> recent({required int limit}) =>
      throw StateError('a day reads by range, not by count');

  @override
  Future<SavedWorkout?> byId(int id) =>
      throw StateError('a day never opens a route');

  @override
  Future<List<SavedWorkout>> routed({
    required DateTime from,
    required DateTime to,
    required Set<WorkoutType> types,
  }) => throw StateError('a day never opens a route');
}

final class _Imported implements ImportedWorkoutReader {
  new(this.workouts, {this.priority = const [ringSource, _other]});

  final List<ImportedWorkout> workouts;
  final List<String> priority;

  @override
  Future<ImportedWorkouts> intersecting({
    required DateTime from,
    required DateTime to,
  }) async => (
    priority: priority,
    workouts: [
      for (final workout in workouts)
        if (workout.end.isAfter(from) && workout.start.isBefore(to)) workout,
    ]..sort((a, b) => a.start.compareTo(b.start)),
  );

  @override
  Future<ImportedWorkouts> recent({required int limit}) =>
      throw StateError('a day reads by range, not by count');

  @override
  Future<ImportedWorkout?> byRecordId(String recordId) =>
      throw StateError('a day never opens one workout');
}

WorkoutListItem _own(
  int id,
  DateTime start,
  int minutes, {
  double? kilocalories = 300,
}) => WorkoutListItem(
  id: id,
  type: WorkoutType.running,
  start: start,
  end: start.add(Duration(minutes: minutes)),
  utcOffset: Duration.zero,
  elapsed: Duration(minutes: minutes),
  activeKilocalories: kilocalories,
);

ImportedWorkout _imported(String id, DateTime start, int minutes) =>
    ImportedWorkout(
      recordId: id,
      source: _other,
      type: WorkoutType.cycling,
      start: start,
      end: start.add(Duration(minutes: minutes)),
      utcOffset: Duration.zero,
    );

ActivitySlot _slot(
  DateTime start,
  int steps, {
  int minutes = 60,
  Duration offset = Duration.zero,
}) => ActivitySlot(
  start: start,
  utcOffset: offset,
  duration: Duration(minutes: minutes),
  steps: steps,
  activeKilocalories: 0,
  distanceMeters: 0,
);

const _profile = UserProfile(
  birthYear: 1996,
  sex: Sex.male,
  heightCentimeters: 175,
  weightKilograms: 70,
);

double _resting(double kilograms) => restingEnergy(
  sex: EnergySex.male,
  age: 30,
  kilograms: kilograms,
  centimeters: 175,
)!;

double _walk(int steps) =>
    stepEnergy(steps: steps, kilograms: 70, centimeters: 175);

Future<EnergyDay> _read({
  DateTime? now,
  UserProfile? profile = _profile,
  Set<ModuleId> modules = const {},
  List<WeighInDraft> weighIns = const [],
  List<ActivitySlot> slots = const [],
  List<WorkoutListItem> own = const [],
  List<ImportedWorkout> imported = const [],
  List<String> priority = const [ringSource, _other],
}) async {
  final weighInStore = InMemoryWeighInStore();
  for (final draft in weighIns) {
    await weighInStore.add(draft);
  }
  final container = ProviderContainer.test(
    overrides: [
      clockProvider.overrideWithValue(() => now ?? _noon),
      userProfileStoreProvider.overrideWithValue(
        InMemoryUserProfileStore(profile),
      ),
      moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
      weighInStoreProvider.overrideWithValue(weighInStore),
      activityHistoryReaderProvider.overrideWithValue(
        FakeActivityHistoryReader(const [], slots: slots),
      ),
      workoutHistoryReaderProvider.overrideWithValue(_Own(own)),
      importedWorkoutReaderProvider.overrideWithValue(
        _Imported(imported, priority: priority),
      ),
    ],
  );
  return await container.read(energyDayProvider(_day).future);
}

EnergyDayEstimate _estimate(EnergyDay day) {
  expect(day, isA<EnergyDayEstimate>());
  return day as EnergyDayEstimate;
}

WeighInDraft _weighIn(DateTime at, double kilograms) =>
    WeighInDraft(at: at, offsetMinutes: 0, kilograms: kilograms);

void main() {
  group('weight', () {
    test('the profile weight is used when nothing was logged', () async {
      final day = _estimate(await _read(modules: {ModuleId.body}));

      expect(day.resting, closeTo(_resting(70), 1e-9));
    });

    test('the latest weigh-in beats the profile weight', () async {
      final day = _estimate(
        await _read(
          modules: {ModuleId.body},
          weighIns: [
            _weighIn(DateTime.utc(2026, 11, 8, 8), 72),
            _weighIn(DateTime.utc(2026, 11, 9, 8), 75),
          ],
        ),
      );

      expect(day.resting, closeTo(_resting(75), 1e-9));
    });

    test('with the Body module off the profile weight is used', () async {
      final day = _estimate(
        await _read(weighIns: [_weighIn(DateTime.utc(2026, 11, 9, 8), 75)]),
      );

      expect(day.resting, closeTo(_resting(70), 1e-9));
    });

    test('a logged weight fills a profile with no weight', () async {
      final day = _estimate(
        await _read(
          profile: const UserProfile(
            birthYear: 1996,
            sex: Sex.male,
            heightCentimeters: 175,
          ),
          modules: {ModuleId.body},
          weighIns: [_weighIn(DateTime.utc(2026, 11, 9, 8), 75)],
        ),
      );

      expect(day.resting, closeTo(_resting(75), 1e-9));
    });
  });

  group('the person', () {
    test('no profile and no weigh-in names every field', () async {
      final day = await _read(profile: null);

      expect(
        day,
        isA<EnergyDayMissing>().having(
          (m) => m.fields,
          'fields',
          EnergyField.values.toSet(),
        ),
      );
    });

    test('the age is the year of the day less the birth year', () async {
      final adult = await _read(
        profile: const UserProfile(
          birthYear: 2008,
          sex: Sex.male,
          heightCentimeters: 175,
          weightKilograms: 70,
        ),
      );
      final minor = await _read(
        profile: const UserProfile(
          birthYear: 2009,
          sex: Sex.male,
          heightCentimeters: 175,
          weightKilograms: 70,
        ),
      );

      expect(adult, isA<EnergyDayEstimate>());
      expect(minor, isA<EnergyDayUnderage>());
    });
  });

  group('the clock', () {
    test('base is the resting share of the day so far', () async {
      final day = _estimate(await _read());

      expect(
        day.base,
        closeTo(baseEnergy(_resting(70), const Duration(hours: 12)), 1e-9),
      );
    });

    test('after a later clock the base is higher', () async {
      final noon = _estimate(await _read());
      final evening = _estimate(
        await _read(now: DateTime.utc(2026, 11, 10, 18)),
      );

      expect(evening.base, greaterThan(noon.base));
      expect(
        evening.base,
        closeTo(baseEnergy(_resting(70), const Duration(hours: 18)), 1e-9),
      );
    });

    test('today is the day of the clock', () async {
      final container = ProviderContainer.test(
        overrides: [
          clockProvider.overrideWithValue(() => _noon),
          userProfileStoreProvider.overrideWithValue(
            InMemoryUserProfileStore(_profile),
          ),
          activityHistoryReaderProvider.overrideWithValue(
            FakeActivityHistoryReader(
              const [],
              slots: [_slot(_from.add(const Duration(hours: 9)), 1200)],
            ),
          ),
        ],
      );

      final today = _estimate(await container.read(energyTodayProvider.future));
      final named = _estimate(
        await container.read(energyDayProvider(_day).future),
      );

      expect(today.steps, closeTo(_walk(1200), 1e-9));
      expect(today.total, closeTo(named.total, 1e-9));
    });
  });

  group('steps', () {
    test('the steps of the day slots are counted', () async {
      final day = _estimate(
        await _read(
          slots: [
            _slot(_from.add(const Duration(hours: 8)), 1000),
            _slot(_from.add(const Duration(hours: 9)), 500),
          ],
        ),
      );

      expect(day.steps, closeTo(_walk(1500), 1e-9));
    });

    test('a slot is placed by its instant, not by its stored offset', () async {
      final day = _estimate(
        await _read(
          slots: [
            _slot(
              _from.add(const Duration(hours: 10)),
              1000,
              offset: const Duration(hours: 3),
            ),
          ],
          own: [_own(1, _from.add(const Duration(hours: 10)), 30)],
        ),
      );

      expect(day.steps, closeTo(_walk(500), 1e-9));
    });
  });

  group('workouts', () {
    test('an own workout adds its stored kilocalories', () async {
      final day = _estimate(
        await _read(own: [_own(1, _from.add(const Duration(hours: 10)), 30)]),
      );

      expect(day.workouts, 300);
    });

    test('an own workout without a count is estimated', () async {
      final day = _estimate(
        await _read(
          own: [
            _own(
              1,
              _from.add(const Duration(hours: 10)),
              30,
              kilocalories: null,
            ),
          ],
        ),
      );

      expect(
        day.workouts,
        closeTo(
          workoutEnergy(
            met: WorkoutType.running.met,
            kilograms: 70,
            elapsed: const Duration(minutes: 30),
          ),
          1e-9,
        ),
      );
    });

    test('an own and an imported workout that overlap count once', () async {
      final day = _estimate(
        await _read(
          own: [_own(1, _from.add(const Duration(hours: 10)), 30)],
          imported: [
            _imported(
              'a',
              _from.add(const Duration(hours: 10, minutes: 15)),
              30,
            ),
          ],
        ),
      );

      expect(day.workouts, 300);
    });

    test('the higher priority source is the one counted', () async {
      final day = _estimate(
        await _read(
          priority: const [_other, ringSource],
          own: [_own(1, _from.add(const Duration(hours: 10)), 30)],
          imported: [
            _imported(
              'a',
              _from.add(const Duration(hours: 10, minutes: 15)),
              30,
            ),
          ],
        ),
      );

      expect(
        day.workouts,
        closeTo(
          workoutEnergy(
            met: WorkoutType.cycling.met,
            kilograms: 70,
            elapsed: const Duration(minutes: 30),
          ),
          1e-9,
        ),
      );
    });

    test('workouts that do not overlap both count', () async {
      final day = _estimate(
        await _read(
          own: [_own(1, _from.add(const Duration(hours: 8)), 30)],
          imported: [_imported('a', _from.add(const Duration(hours: 10)), 30)],
        ),
      );

      expect(day.workouts, greaterThan(300));
    });

    test('an own workout from before the day still hides an imported '
        'one spanning the day start', () async {
      final day = _estimate(
        await _read(
          slots: [_slot(_from, 1000)],
          own: [_own(1, DateTime.utc(2026, 11, 9, 23), 45)],
          imported: [_imported('a', DateTime.utc(2026, 11, 9, 23, 30), 60)],
        ),
      );

      expect(day.steps, closeTo(_walk(1000), 1e-9));
      expect(day.workouts, 0);
    });

    test('an imported workout spanning the day start with no rival removes '
        'the steps it covers', () async {
      final day = _estimate(
        await _read(
          slots: [_slot(_from, 1000)],
          imported: [_imported('a', DateTime.utc(2026, 11, 9, 23, 30), 60)],
        ),
      );

      expect(day.steps, closeTo(_walk(500), 1e-9));
      expect(day.workouts, 0);
    });

    test('an own workout from after the day still hides an imported one '
        'inside it', () async {
      final day = _estimate(
        await _read(
          own: [_own(1, DateTime.utc(2026, 11, 11, 0, 10), 30)],
          imported: [_imported('a', DateTime.utc(2026, 11, 10, 23, 50), 30)],
        ),
      );

      expect(day.workouts, 0);
    });

    test('an imported workout with no length adds nothing', () async {
      final day = _estimate(
        await _read(
          slots: [_slot(_from.add(const Duration(hours: 10)), 1000)],
          imported: [_imported('a', _from.add(const Duration(hours: 10)), 0)],
        ),
      );

      expect(day.workouts, 0);
      expect(day.steps, closeTo(_walk(1000), 1e-9));
    });
  });
}
