import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/features/effort/domain/effort_day.dart';
import 'package:open_ring/features/heart/application/heart_view.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';
import 'package:open_ring/features/open_score/domain/day_tag_store.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/sleep/application/sleep_view.dart';
import 'package:open_ring/features/today/application/readiness_view.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

import '../../helpers/metrics_fakes.dart';
import '../../helpers/workout_fakes.dart';

const _other = 'com.example.other';

final class _Spy extends MemoryWorkoutHistory {
  new({super.seed});

  final reads = <int>[];
  final ranges = <({DateTime from, DateTime to})>[];

  @override
  Future<SavedWorkout?> byId(int id) {
    reads.add(id);
    return super.byId(id);
  }

  @override
  Future<List<WorkoutListItem>> intersecting({
    required DateTime from,
    required DateTime to,
  }) {
    ranges.add((from: from, to: to));
    return super.intersecting(from: from, to: to);
  }
}

final class _Imported implements ImportedWorkoutReader {
  new(this.workouts, this.priority);

  final List<ImportedWorkout> workouts;
  final List<String> priority;
  final ranges = <({DateTime from, DateTime to})>[];

  @override
  Future<ImportedWorkouts> recent({required int limit}) async => (
    priority: priority,
    workouts: [...workouts]..sort((a, b) => b.start.compareTo(a.start)),
  );

  @override
  Future<ImportedWorkout?> byRecordId(String recordId) async => null;

  @override
  Future<ImportedWorkouts> intersecting({
    required DateTime from,
    required DateTime to,
  }) async {
    ranges.add((from: from, to: to));
    return (
      priority: priority,
      workouts: [
        for (final workout in workouts)
          if (workout.end.isAfter(from) && workout.start.isBefore(to)) workout,
      ]..sort((a, b) => a.start.compareTo(b.start)),
    );
  }
}

final class _SlowProfileStore implements UserProfileStore {
  final gate = Completer<UserProfile?>();

  @override
  Future<UserProfile?> read() => gate.future;

  @override
  Future<void> save(UserProfile profile, {required DateTime at}) async {}
}

final class _ModulesLoading extends EnabledModulesController {
  new();

  @override
  Future<Set<ModuleId>> build() => Completer<Set<ModuleId>>().future;
}

final class _ModulesFailing extends EnabledModulesController {
  new();

  @override
  Future<Set<ModuleId>> build() =>
      Future<Set<ModuleId>>.error(StateError('modules'));
}

DateTime _at(LocalDate day, int hour, [int minute = 0]) =>
    DateTime.utc(day.year, day.month, day.day, hour, minute);

SavedWorkout _saved(
  int id,
  WorkoutType type,
  DateTime start, {
  int minutes = 30,
  int? bpm,
  Duration utcOffset = Duration.zero,
}) {
  final elapsed = Duration(minutes: minutes);
  return SavedWorkout(
    id: id,
    utcOffset: utcOffset,
    workout: FinishedWorkout(
      type: type,
      start: start,
      end: start.add(elapsed),
      elapsed: elapsed,
      heartRate: [
        if (bpm != null)
          for (var s = 0; s <= elapsed.inSeconds; s += 5)
            (at: start.add(Duration(seconds: s)), bpm: bpm),
      ],
      route: WorkoutRoute(segments: const []),
      pauses: const [],
    ),
  );
}

ImportedWorkout _imported(
  String id,
  WorkoutType type,
  DateTime start, {
  int minutes = 30,
}) => ImportedWorkout(
  recordId: id,
  source: _other,
  type: type,
  start: start,
  end: start.add(Duration(minutes: minutes)),
  utcOffset: Duration.zero,
);

ReadinessView _readiness(int? value) => ReadinessView(
  date: metricsToday,
  score: switch (value) {
    null => InsufficientData<ReadinessFactor>(const [ReadinessFactor.sleep]),
    final v => Scored<ReadinessFactor>([
      Contribution(
        factor: ReadinessFactor.sleep,
        value: v.toDouble(),
        subscore: v.toDouble(),
        weight: 1,
      ),
    ]),
  },
  sleep: SleepDayView(
    date: metricsToday,
    night: null,
    score: InsufficientData<SleepFactor>(const [SleepFactor.duration]),
  ),
  restingHeartRate: const BaselineInput(
    today: null,
    baseline: BaselineBuilding(daysCollected: 0, daysNeeded: 14),
  ),
  hrv: const BaselineInput(
    today: null,
    baseline: BaselineBuilding(daysCollected: 0, daysNeeded: 14),
  ),
  activityLoad: null,
);

({ProviderContainer container, _Spy own, _Imported imported}) _setup({
  List<SavedWorkout> saved = const [],
  List<ImportedWorkout> imported = const [],
  List<String> priority = const [ringSource, _other],
  List<ActivitySlot> slots = const [],
  UserProfileStore? profile,
  Set<ModuleId> modules = const {},
  Map<LocalDate, DayTag> tags = const {},
  int? readiness,
  List<Override> extra = const [],
}) {
  final own = _Spy(seed: saved);
  final reader = _Imported(imported, priority);
  final container = ProviderContainer.test(
    overrides: [
      clockProvider.overrideWithValue(() => metricsNow),
      workoutHistoryReaderProvider.overrideWithValue(own),
      importedWorkoutReaderProvider.overrideWithValue(reader),
      activityHistoryReaderProvider.overrideWithValue(
        FakeActivityHistoryReader(const [], slots: slots),
      ),
      if (profile != null) userProfileStoreProvider.overrideWithValue(profile),
      moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
      dayTagStoreProvider.overrideWithValue(InMemoryDayTagStore(tags)),
      readinessProvider.overrideWith((ref) async => _readiness(readiness)),
      ...extra,
    ],
  );
  return (container: container, own: own, imported: reader);
}

Future<void> _settle(ProviderContainer container) async {
  await container.read(enabledModulesProvider.future);
  await container.read(dayTagsProvider.future);
}

// Every other day for 19 days at 30 load: no hard day, no spike, no run
// without an easy day.
List<ImportedWorkout> _calmWeeks() => [
  for (var age = 1; age <= 19; age += 2)
    _imported('c$age', WorkoutType.yoga, _at(metricsToday.addDays(-age), 8)),
];

void main() {
  group('criterion 13: an overlapped imported workout counts once', () {
    final start = _at(metricsToday.addDays(-1), 18);
    final recorded = _saved(1, WorkoutType.treadmill, start);
    final overlapping = _imported(
      'a',
      WorkoutType.cycling,
      start.add(const Duration(minutes: 10)),
      minutes: 45,
    );

    test('the recorded one wins when the ring leads', () async {
      final s = _setup(saved: [recorded], imported: [overlapping]);

      final sessions = await s.container.read(effortSessionsProvider.future);
      final series = await s.container.read(effortDailyLoadProvider.future);

      expect(sessions, hasLength(1));
      expect(sessions.single.type, WorkoutType.treadmill);
      expect(series, <double>[90]);
    });

    test('the imported one wins when its source leads', () async {
      final s = _setup(
        saved: [recorded],
        imported: [overlapping],
        priority: const [_other, ringSource],
      );

      final sessions = await s.container.read(effortSessionsProvider.future);
      final series = await s.container.read(effortDailyLoadProvider.future);

      expect(sessions, hasLength(1));
      expect(sessions.single.type, WorkoutType.cycling);
      expect(series, <double>[113]);
    });

    test('sessions come oldest first, whatever the reader order', () async {
      final s = _setup(
        saved: [
          _saved(2, WorkoutType.treadmill, _at(metricsToday.addDays(-1), 9)),
          _saved(1, WorkoutType.treadmill, _at(metricsToday.addDays(-3), 9)),
        ],
        imported: [
          _imported('m', WorkoutType.yoga, _at(metricsToday.addDays(-2), 9)),
        ],
      );

      final sessions = await s.container.read(effortSessionsProvider.future);

      expect(
        [for (final e in sessions) e.date],
        [
          metricsToday.addDays(-3),
          metricsToday.addDays(-2),
          metricsToday.addDays(-1),
        ],
      );
    });
  });

  group('the window of the sessions', () {
    test('reads both readers padded by one day on each side', () async {
      final s = _setup();

      await s.container.read(effortSessionsProvider.future);

      final range = (
        from: DateTime.utc(2026, 9, 28),
        to: DateTime.utc(2026, 11, 12),
      );
      expect(s.own.ranges, [range]);
      expect(s.imported.ranges, [range]);
    });

    test('keeps the dates from today minus 42 to today only', () async {
      final s = _setup(
        saved: [
          _saved(1, WorkoutType.treadmill, DateTime.utc(2026, 9, 28, 22)),
          _saved(2, WorkoutType.treadmill, DateTime.utc(2026, 9, 29, 7)),
          _saved(3, WorkoutType.treadmill, DateTime.utc(2026, 11, 10, 7)),
          _saved(4, WorkoutType.treadmill, DateTime.utc(2026, 9, 28, 23, 50)),
        ],
      );

      final sessions = await s.container.read(effortSessionsProvider.future);

      expect(
        [for (final e in sessions) e.date],
        [const LocalDate(2026, 9, 29), const LocalDate(2026, 11, 10)],
      );
      expect(s.own.reads, unorderedEquals(<int>[2, 3]));
    });

    test(
      'a workout of the oldest local day is kept despite its offset',
      () async {
        final s = _setup(
          saved: [
            _saved(
              1,
              WorkoutType.treadmill,
              DateTime.utc(2026, 9, 29, 4, 10),
              minutes: 40,
              utcOffset: const Duration(hours: -4),
            ),
          ],
        );

        final sessions = await s.container.read(effortSessionsProvider.future);

        expect(
          [for (final e in sessions) e.date],
          [const LocalDate(2026, 9, 29)],
        );
      },
    );

    test('a recorded workout is read by id, an imported one is not', () async {
      final s = _setup(
        saved: [
          _saved(7, WorkoutType.treadmill, _at(metricsToday.addDays(-2), 9)),
        ],
        imported: [
          _imported('i', WorkoutType.cycling, _at(metricsToday.addDays(-1), 9)),
        ],
      );

      await s.container.read(effortSessionsProvider.future);

      expect(s.own.reads, [7]);
    });
  });

  group('heart rate and the profile', () {
    final start = _at(metricsToday.addDays(-1), 18);

    test('samples read by id and the saved zones set the load', () async {
      final s = _setup(
        saved: [_saved(1, WorkoutType.treadmill, start, bpm: 170)],
        profile: InMemoryUserProfileStore(const UserProfile(maxHeartRate: 200)),
      );

      await s.container.read(userProfileProvider.future);
      final session = (await s.container.read(effortSessionsProvider.future))
          .single;

      expect(session.load.value, 120);
      expect(session.load.source, LoadSource.heartRate);
      expect(session.points.equivalent, closeTo(60, 1e-9));
    });

    test('a profile still loading gives null zones, then recomputes', () async {
      final store = _SlowProfileStore();
      final s = _setup(
        saved: [_saved(1, WorkoutType.treadmill, start, bpm: 170)],
        profile: store,
      );

      final first = (await s.container.read(effortSessionsProvider.future))
          .single;
      store.gate.complete(const UserProfile(maxHeartRate: 200));
      await s.container.read(userProfileProvider.future);
      final second = (await s.container.read(effortSessionsProvider.future))
          .single;

      expect(first.load.source, LoadSource.typeDefault);
      expect(first.load.value, 90);
      expect(second.load.source, LoadSource.heartRate);
      expect(second.load.value, 120);
    });

    test('a new data revision reads the workouts again', () async {
      final s = _setup();

      final before = await s.container.read(effortSessionsProvider.future);
      await s.own.save(
        _saved(1, WorkoutType.treadmill, start).workout,
        at: metricsNow,
      );
      s.container.read(dataRevisionProvider.notifier).bump();
      final after = await s.container.read(effortSessionsProvider.future);

      expect(before, isEmpty);
      expect(after, hasLength(1));
    });
  });

  group('criterion 14: the Sick tag and the Open Score module', () {
    final sickToday = {metricsToday: DayTag.sick};

    test('Sick today with Open Score on gives the sick rule', () async {
      final s = _setup(modules: {ModuleId.openScore}, tags: sickToday);
      await _settle(s.container);

      final advice = await s.container.read(effortCoachProvider.future);

      expect(s.container.read(effortSickProvider), isTrue);
      expect(advice.rule, CoachRule.sick);
    });

    test('Sick today with Open Score off gives another rule', () async {
      final s = _setup(modules: {ModuleId.energy}, tags: sickToday);
      await _settle(s.container);

      final advice = await s.container.read(effortCoachProvider.future);

      expect(s.container.read(effortSickProvider), isFalse);
      expect(advice.rule, CoachRule.noReadiness);
    });

    test('modules still loading give another rule', () async {
      final s = _setup(
        tags: sickToday,
        extra: [enabledModulesProvider.overrideWith(_ModulesLoading.new)],
      );
      await s.container.read(dayTagsProvider.future);

      final advice = await s.container.read(effortCoachProvider.future);

      expect(s.container.read(effortSickProvider), isFalse);
      expect(advice.rule, CoachRule.noReadiness);
    });

    test('modules in error give another rule', () async {
      final s = _setup(
        tags: sickToday,
        extra: [enabledModulesProvider.overrideWith(_ModulesFailing.new)],
      );
      await s.container.read(dayTagsProvider.future);
      await expectLater(
        s.container.read(enabledModulesProvider.future),
        throwsStateError,
      );

      final advice = await s.container.read(effortCoachProvider.future);

      expect(s.container.read(effortSickProvider), isFalse);
      expect(advice.rule, CoachRule.noReadiness);
    });

    test('tags still loading give another rule', () async {
      final s = _setup(
        modules: {ModuleId.openScore},
        extra: [
          dayTagsProvider.overrideWith(
            (ref) => Completer<Map<LocalDate, DayTag>>().future,
          ),
        ],
      );
      await s.container.read(enabledModulesProvider.future);

      final advice = await s.container.read(effortCoachProvider.future);

      expect(s.container.read(effortSickProvider), isFalse);
      expect(advice.rule, CoachRule.noReadiness);
    });

    test('tags in error give another rule', () async {
      final s = _setup(
        modules: {ModuleId.openScore},
        extra: [
          dayTagsProvider.overrideWith(
            (ref) => Future<Map<LocalDate, DayTag>>.error(StateError('tags')),
          ),
        ],
      );
      await s.container.read(enabledModulesProvider.future);
      await expectLater(
        s.container.read(dayTagsProvider.future),
        throwsStateError,
      );

      expect(s.container.read(effortSickProvider), isFalse);
    });

    test('a Sick tag of yesterday is not sick today', () async {
      final s = _setup(
        modules: {ModuleId.openScore},
        tags: {metricsToday.addDays(-1): DayTag.sick},
      );
      await _settle(s.container);

      expect(s.container.read(effortSickProvider), isFalse);
    });

    test('another tag today is not sick', () async {
      final s = _setup(
        modules: {ModuleId.openScore},
        tags: {metricsToday: DayTag.rest},
      );
      await _settle(s.container);

      expect(s.container.read(effortSickProvider), isFalse);
    });
  });

  group('criterion 15: the coach', () {
    test('a null readiness with a calm series gives noReadiness', () async {
      final s = _setup(imported: _calmWeeks());

      final advice = await s.container.read(effortCoachProvider.future);

      expect(advice.rule, CoachRule.noReadiness);
      expect(advice.yesterdayLoad, 30);
    });

    test('the readiness of the day reaches the advice', () async {
      final s = _setup(imported: _calmWeeks(), readiness: 40);

      final advice = await s.container.read(effortCoachProvider.future);

      expect(advice.rule, CoachRule.lowReadiness);
    });
  });

  group('criterion 16: the week and the last seven days', () {
    // 2026-11-10 is a Tuesday: the week is the 9th and the 10th.
    final strength = [
      for (final day in [5, 6, 7, 9])
        _imported(
          's$day',
          WorkoutType.strength,
          DateTime.utc(2026, 11, day, 7),
          minutes: 45,
        ),
    ];

    test('the week equals effortWeek over the daily intensity', () async {
      final s = _setup(imported: strength);

      final week = await s.container.read(effortWeekProvider.future);
      final sessions = await s.container.read(effortSessionsProvider.future);
      final expected = effortWeek(
        await s.container.read(dailyIntensityProvider.future),
        effortStrengthDays(sessions),
        today: metricsToday,
      );

      expect(week.monday, expected.monday);
      expect(week.points, expected.points);
      expect(week.strengthDays, expected.strengthDays);
      expect(week.monday, const LocalDate(2026, 11, 9));
      expect(week.points, 45);
    });

    test('a 45 minute strength workout of this week is one day', () async {
      final s = _setup(imported: strength);

      final week = await s.container.read(effortWeekProvider.future);

      expect(week.strengthDays, 1);
    });

    test('the last seven days equal weeklyIntensityMinutes', () async {
      final s = _setup(imported: strength);

      final seven = await s.container.read(effortLastSevenProvider.future);
      final expected = weeklyIntensityMinutes(
        await s.container.read(dailyIntensityProvider.future),
        today: metricsToday,
      );

      expect(seven, expected);
      expect(seven, 180);
    });

    test('under four active days the last seven days are null', () async {
      final s = _setup(imported: strength.take(2).toList());

      expect(await s.container.read(effortLastSevenProvider.future), isNull);
    });
  });

  group('criterion 17: a workout recorded today', () {
    test('is in the sessions and the week, not in the load series', () async {
      final s = _setup(
        saved: [
          _saved(1, WorkoutType.treadmill, _at(metricsToday, 7), minutes: 40),
        ],
        imported: [
          _imported('y', WorkoutType.yoga, _at(metricsToday.addDays(-1), 8)),
        ],
      );

      final sessions = await s.container.read(effortSessionsProvider.future);
      final week = await s.container.read(effortWeekProvider.future);
      final series = await s.container.read(effortDailyLoadProvider.future);

      expect(
        [for (final e in sessions) e.date],
        [metricsToday.addDays(-1), metricsToday],
      );
      expect(week.points, 80);
      expect(series, <double>[30]);
    });

    test('only a workout today leaves the series empty', () async {
      final s = _setup(
        saved: [
          _saved(1, WorkoutType.treadmill, _at(metricsToday, 7), minutes: 40),
        ],
      );

      expect(await s.container.read(effortDailyLoadProvider.future), isEmpty);
    });
  });
}
