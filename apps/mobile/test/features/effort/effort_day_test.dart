import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/effort/domain/effort_day.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

const _today = LocalDate(2026, 11, 10);

DateTime _at(LocalDate day, int hour, [int minute = 0]) =>
    DateTime.utc(day.year, day.month, day.day, hour, minute);

List<BpmSample> _samples(DateTime start, int bpm, {int minutes = 30}) => [
  for (var s = 0; s <= minutes * 60; s += 5)
    (at: start.add(Duration(seconds: s)), bpm: bpm),
];

WorkoutListItem _recorded({
  WorkoutType type = WorkoutType.treadmill,
  int minutes = 30,
}) {
  final start = DateTime.utc(2026, 11, 9, 7);
  return WorkoutListItem(
    id: 1,
    type: type,
    start: start,
    end: start.add(Duration(minutes: minutes)),
    utcOffset: Duration.zero,
    elapsed: Duration(minutes: minutes),
  );
}

ImportedWorkout _imported({
  required WorkoutType type,
  required Duration elapsed,
  DateTime? start,
  Duration utcOffset = Duration.zero,
}) {
  final from = start ?? DateTime.utc(2026, 11, 9, 7);
  return ImportedWorkout(
    recordId: 'r',
    source: 'com.example.other',
    type: type,
    start: from,
    end: from.add(elapsed),
    utcOffset: utcOffset,
  );
}

EffortSession _yoga(LocalDate day, {int hour = 7, int minutes = 30}) =>
    effortSessionOf(
      _imported(
        type: WorkoutType.yoga,
        elapsed: Duration(minutes: minutes),
        start: _at(day, hour),
      ),
    );

ActivitySlot _slot(DateTime start, {int minutes = 15, int steps = 1800}) =>
    ActivitySlot(
      start: start,
      utcOffset: Duration.zero,
      duration: Duration(minutes: minutes),
      steps: steps,
      activeKilocalories: 0,
      distanceMeters: 0,
    );

List<double> _load(List<EffortSession> sessions, List<ActivitySlot> slots) =>
    effortDailyLoad(sessions: sessions, slots: slots, today: _today);

void main() {
  group('criterion 1: effortTypeDefault', () {
    test('gives the ten values of the owner table', () {
      const table = {
        WorkoutType.running: 3.0,
        WorkoutType.treadmill: 3.0,
        WorkoutType.strength: 2.5,
        WorkoutType.stationaryBike: 2.5,
        WorkoutType.cycling: 2.5,
        WorkoutType.hiking: 2.0,
        WorkoutType.elliptical: 2.0,
        WorkoutType.other: 2.0,
        WorkoutType.walking: 1.5,
        WorkoutType.yoga: 1.0,
      };

      expect(table, hasLength(WorkoutType.values.length));
      for (final entry in table.entries) {
        expect(
          effortTypeDefault(entry.key),
          entry.value,
          reason: '${entry.key}',
        );
      }
    });

    test('the window is 42 days', () {
      expect(effortLoadDays, 42);
    });
  });

  group('criterion 2: a recorded treadmill with heart rate and zones', () {
    final entry = _recorded();
    final session = effortSessionOf(
      entry,
      heartRate: _samples(entry.start, 170),
      zones: HeartRateZones(maxHeartRate: 200),
    );

    test('points are 60 equivalent minutes', () {
      expect(session.points.equivalent, closeTo(60, 1e-9));
    });

    test('load is 30 minutes in zone 4, from the heart rate', () {
      expect(session.load.value, 120);
      expect(session.load.source, LoadSource.heartRate);
    });

    test('the session carries the entry fields', () {
      expect(session.type, WorkoutType.treadmill);
      expect(session.start, entry.start);
      expect(session.end, entry.end);
      expect(session.elapsed, const Duration(minutes: 30));
      expect(session.date, const LocalDate(2026, 11, 9));
      expect(session.strength, isFalse);
    });
  });

  group('criterion 2: the max heart rate reaches the points', () {
    final entry = _recorded(type: WorkoutType.strength);
    final samples = _samples(entry.start, 170);

    test('strength with zones counts vigorous minutes double', () {
      final session = effortSessionOf(
        entry,
        heartRate: samples,
        zones: HeartRateZones(maxHeartRate: 200),
      );

      expect(session.points.equivalent, closeTo(60, 1e-9));
    });

    test('strength without zones keeps the type credit', () {
      final session = effortSessionOf(entry, heartRate: samples);

      expect(session.points.equivalent, closeTo(30, 1e-9));
    });
  });

  group('criterion 3: the same workout without zones', () {
    final entry = _recorded();
    final samples = _samples(entry.start, 170);
    final session = effortSessionOf(entry, heartRate: samples);

    test('load is the type default, 30 times 3', () {
      expect(session.load.value, 90);
      expect(session.load.source, LoadSource.typeDefault);
    });

    test('points equal workoutPoints with a null max', () {
      final expected = workoutPoints(entry, heartRate: samples);

      expect(session.points.moderate, expected.moderate);
      expect(session.points.vigorous, expected.vigorous);
      expect(session.points.equivalent, closeTo(60, 1e-9));
    });
  });

  group('criterion 4: samples under zone 1 or none', () {
    final entry = _recorded();

    test('90 bpm with a max of 200 gives the default, not 0', () {
      final session = effortSessionOf(
        entry,
        heartRate: _samples(entry.start, 90),
        zones: HeartRateZones(maxHeartRate: 200),
      );

      expect(session.load.source, LoadSource.typeDefault);
      expect(session.load.value, 90);
    });

    test('zones with no samples give the default', () {
      final session = effortSessionOf(
        entry,
        zones: HeartRateZones(maxHeartRate: 200),
      );

      expect(session.load.source, LoadSource.typeDefault);
      expect(session.load.value, 90);
    });
  });

  group('criterion 5: an imported workout and the strength flag', () {
    test('imported strength of 45 minutes', () {
      final session = effortSessionOf(
        _imported(
          type: WorkoutType.strength,
          elapsed: const Duration(minutes: 45),
        ),
      );

      expect(
        session.points.equivalent,
        metIntensity(3.5, const Duration(minutes: 45)).equivalent,
      );
      expect(session.load.value, 113);
      expect(session.load.source, LoadSource.typeDefault);
      expect(session.strength, isTrue);
    });

    test('strength of 19 minutes 59 seconds is not a strength session', () {
      final session = effortSessionOf(
        _imported(
          type: WorkoutType.strength,
          elapsed: const Duration(minutes: 19, seconds: 59),
        ),
      );

      expect(session.strength, isFalse);
    });

    test('strength of exactly 20 minutes is one', () {
      final session = effortSessionOf(
        _imported(
          type: WorkoutType.strength,
          elapsed: const Duration(minutes: 20),
        ),
      );

      expect(session.strength, isTrue);
    });

    test('a run of 45 minutes is not strength', () {
      final session = effortSessionOf(
        _imported(
          type: WorkoutType.running,
          elapsed: const Duration(minutes: 45),
        ),
      );

      expect(session.strength, isFalse);
    });

    test('a recorded strength workout of 45 minutes is strength', () {
      final session = effortSessionOf(
        _recorded(type: WorkoutType.strength, minutes: 45),
      );

      expect(session.strength, isTrue);
    });
  });

  group('criterion 6: workoutPoints is the old credit', () {
    test('a recorded entry takes the larger of heart rate and type', () {
      final entry = _recorded(type: WorkoutType.strength);
      final samples = _samples(entry.start, 170);

      final points = workoutPoints(
        entry,
        heartRate: samples,
        maxHeartRate: 200,
      );
      final old = workoutIntensity(
        met: entry.type.met,
        elapsed: entry.elapsed,
        heartRate: samples,
        maxHeartRate: 200,
      );

      expect(points.moderate, old.moderate);
      expect(points.vigorous, old.vigorous);
      expect(points.equivalent, closeTo(60, 1e-9));
    });

    test('a recorded entry without a max keeps the type credit', () {
      final entry = _recorded(type: WorkoutType.strength);

      final points = workoutPoints(
        entry,
        heartRate: _samples(entry.start, 170),
      );

      expect(points.equivalent, closeTo(30, 1e-9));
    });

    test('an imported entry takes the type credit and ignores samples', () {
      final entry = _imported(
        type: WorkoutType.strength,
        elapsed: const Duration(minutes: 45),
      );

      final points = workoutPoints(
        entry,
        heartRate: _samples(entry.start, 190, minutes: 45),
        maxHeartRate: 200,
      );
      final old = metIntensity(entry.type.met, entry.elapsed);

      expect(points.moderate, old.moderate);
      expect(points.vigorous, old.vigorous);
      expect(points.equivalent, 45);
    });
  });

  group('criterion 7: a workout belongs to its start day', () {
    // 23:50 local on the 9th at UTC-3 is 02:50 UTC on the 10th.
    final crossing = _imported(
      type: WorkoutType.yoga,
      elapsed: const Duration(minutes: 30),
      start: DateTime.utc(2026, 11, 10, 2, 50),
      utcOffset: const Duration(hours: -3),
    );

    test('the date is the local start day', () {
      expect(effortSessionOf(crossing).date, const LocalDate(2026, 11, 9));
    });

    test('the whole load lands on the start day', () {
      final series = effortDailyLoad(
        sessions: [effortSessionOf(crossing)],
        slots: const [],
        today: const LocalDate(2026, 11, 12),
      );

      expect(series, <double>[30, 0, 0]);
    });

    test('a brisk walk after midnight inside the span is not counted', () {
      final session = effortSessionOf(crossing);
      final walk = _slot(
        DateTime.utc(2026, 11, 10, 3, 5),
        minutes: 10,
        steps: 1200,
      );

      final series = effortDailyLoad(
        sessions: [session],
        slots: [walk],
        today: const LocalDate(2026, 11, 12),
      );

      expect(series, <double>[30, 0, 0]);
    });

    test('a session that starts before the window is left out', () {
      final session = effortSessionOf(
        _imported(
          type: WorkoutType.yoga,
          elapsed: const Duration(hours: 3),
          start: _at(_today.addDays(-43), 22),
        ),
      );

      expect(_load([session], const []), isEmpty);
    });
  });

  group('criterion 8: brisk walking outside a session', () {
    final yesterday = _today.addDays(-1);

    test('15 brisk minutes give 23 for the day', () {
      final series = _load(const [], [_slot(_at(yesterday, 12))]);

      expect(series, <double>[23]);
    });

    test('three slots of 5 minutes are rounded once, not per slot', () {
      final series = _load(const [], [
        _slot(_at(yesterday, 12), minutes: 5, steps: 600),
        _slot(_at(yesterday, 12, 5), minutes: 5, steps: 600),
        _slot(_at(yesterday, 12, 10), minutes: 5, steps: 600),
      ]);

      expect(series, <double>[23]);
    });

    test('the same slots inside a session span add 0', () {
      final session = _yoga(yesterday);

      final series = _load([session], [_slot(_at(yesterday, 7, 5))]);

      expect(series, <double>[30]);
    });

    test('a slot that is not brisk starts the series with 0', () {
      final series = _load(const [], [_slot(_at(yesterday, 12), steps: 300)]);

      expect(series, <double>[0]);
    });

    test('a slot without steps does not start the series', () {
      final series = _load(
        [_yoga(yesterday)],
        [_slot(_at(_today.addDays(-5), 12), steps: 0)],
      );

      expect(series, <double>[30]);
    });
  });

  group('criterion 9: two sessions and brisk minutes on one day', () {
    test('60 and 45 plus 10 brisk minutes give 120', () {
      final yesterday = _today.addDays(-1);
      final sessions = [
        _yoga(yesterday, minutes: 60),
        _yoga(yesterday, hour: 9, minutes: 45),
      ];

      final series = _load(sessions, [
        _slot(_at(yesterday, 12), minutes: 10, steps: 1200),
      ]);

      expect(series, <double>[120]);
    });
  });

  group('criterion 10: the length of the series', () {
    test('first data 13 days before today gives 13 values', () {
      final series = _load([
        _yoga(_today.addDays(-13)),
        _yoga(_today.addDays(-1), minutes: 20),
      ], const []);

      expect(series, hasLength(13));
      expect(series.first, 30);
      expect(series.last, 20);
      expect(series.sublist(1, 12), everyElement(0));
    });

    test('a slot with steps 13 days before today starts the series', () {
      final series = _load(const [], [
        _slot(_at(_today.addDays(-13), 12), steps: 300),
      ]);

      expect(series, hasLength(13));
      expect(series, everyElement(0));
    });

    test('data on each of the last 60 days gives 42 values', () {
      final sessions = [
        for (var age = 1; age <= 60; age++)
          _yoga(_today.addDays(-age), minutes: 10),
      ];

      final series = _load(sessions, const []);

      expect(series, hasLength(effortLoadDays));
      expect(series, everyElement(10));
    });

    test('the first day of the window is today minus 42', () {
      final series = _load([_yoga(_today.addDays(-42))], const []);

      expect(series, hasLength(42));
      expect(series.first, 30);
    });

    test('no data gives an empty list', () {
      expect(_load(const [], const []), isEmpty);
    });

    test('slots without steps only give an empty list', () {
      final series = _load(const [], [
        _slot(_at(_today.addDays(-3), 12), steps: 0),
      ]);

      expect(series, isEmpty);
    });
  });

  group('criterion 11: the series ends yesterday and starts in the window', () {
    final anchor = _yoga(_today.addDays(-5), minutes: 10);

    test('a session today is not in the series', () {
      final series = _load([anchor, _yoga(_today, minutes: 50)], const []);

      expect(series, hasLength(5));
      expect(series.last, 0);
      expect(series.fold<double>(0, (a, b) => a + b), 10);
    });

    test('a slot today or after is not in the series', () {
      final series = _load(
        [anchor],
        [_slot(_at(_today, 8)), _slot(_at(_today.addDays(1), 8))],
      );

      expect(series, hasLength(5));
      expect(series.fold<double>(0, (a, b) => a + b), 10);
    });

    test('only a session today gives an empty list', () {
      expect(_load([_yoga(_today)], [_slot(_at(_today, 8))]), isEmpty);
    });

    test('a session 43 days old is not in the series', () {
      final series = _load([anchor, _yoga(_today.addDays(-43))], const []);

      expect(series, hasLength(5));
      expect(series.first, 10);
    });

    test('only a session 43 days old gives an empty list', () {
      expect(_load([_yoga(_today.addDays(-43))], const []), isEmpty);
    });

    test('a slot 43 days old does not start the series', () {
      final series = _load([anchor], [_slot(_at(_today.addDays(-43), 8))]);

      expect(series, hasLength(5));
    });
  });

  group('criterion 12: a day with no data inside the series', () {
    test('is 0', () {
      final series = _load([
        _yoga(_today.addDays(-4)),
        _yoga(_today.addDays(-1), minutes: 15),
      ], const []);

      expect(series, <double>[30, 0, 0, 15]);
    });

    test('the series is oldest first', () {
      final series = _load([
        _yoga(_today.addDays(-1), minutes: 15),
        _yoga(_today.addDays(-3)),
      ], const []);

      expect(series, <double>[30, 0, 15]);
    });
  });

  group('effortBriskMinutes', () {
    final monday = _today.addDays(-1);

    test('adds the brisk minutes of a day', () {
      final brisk = effortBriskMinutes(
        sessions: const [],
        slots: [
          _slot(_at(monday, 9)),
          _slot(_at(monday, 15), minutes: 5, steps: 600),
        ],
      );
      expect(brisk, {monday: 20.0});
    });

    test('a day with steps and no brisk minute is a zero', () {
      final brisk = effortBriskMinutes(
        sessions: const [],
        slots: [_slot(_at(monday, 9), steps: 300)],
      );
      expect(brisk, {monday: 0.0});
    });

    test(
      'a slot inside a session adds nothing, and one without steps no day',
      () {
        final brisk = effortBriskMinutes(
          sessions: [_yoga(monday, hour: 9)],
          slots: [_slot(_at(monday, 9)), _slot(_at(_today, 9), steps: 0)],
        );
        expect(brisk, {monday: 0.0});
      },
    );
  });

  group('effortWeekDays', () {
    final monday = _today.addDays(-1);
    final days = effortWeekDays(
      [(date: monday.addDays(-1), value: 99), (date: monday, value: 42.4)],
      {_today},
      monday: monday,
      today: _today,
    );

    test('has the seven days from Monday', () {
      expect(
        [for (final day in days) day.date],
        [for (var i = 0; i < 7; i++) monday.addDays(i)],
      );
    });

    test('a day with data keeps its points and a day without is 0', () {
      expect(days[0].points, 42.4);
      expect(days[1].points, 0);
    });

    test('a day after today has no points', () {
      expect([
        for (final day in days.skip(2)) day.points,
      ], everyElement(isNull));
    });

    test('marks the strength days only', () {
      expect(
        [for (final day in days) day.strength],
        [false, true, false, false, false, false, false],
      );
    });
  });

  group('effortWeekWalks', () {
    final monday = _today.addDays(-1);

    test('lists the days of the week with a minute or more, newest first', () {
      final walks = effortWeekWalks(
        {
          monday.addDays(-1): 30,
          monday: 12.4,
          _today: 0.5,
          _today.addDays(1): 20,
        },
        monday: monday,
        today: _today,
      );
      expect(walks, [
        (date: _today, minutes: 0.5),
        (date: monday, minutes: 12.4),
      ]);
    });

    test('leaves out a day under half a minute', () {
      expect(
        effortWeekWalks(
          {_today: 0.4, monday: 0},
          monday: monday,
          today: _today,
        ),
        isEmpty,
      );
    });
  });

  group('effortPointsByType', () {
    EffortSession session(WorkoutType type, int minutes) => effortSessionOf(
      _imported(
        type: type,
        elapsed: Duration(minutes: minutes),
      ),
    );

    test('adds the points of each type, in order of first appearance', () {
      final byType = effortPointsByType([
        session(WorkoutType.walking, 30),
        session(WorkoutType.running, 20),
        session(WorkoutType.walking, 10),
      ]);
      expect(byType.keys, [WorkoutType.walking, WorkoutType.running]);
      expect(byType[WorkoutType.walking], 40);
      expect(byType[WorkoutType.running], 40);
    });

    test('leaves out a type that earned no point', () {
      expect(effortPointsByType([session(WorkoutType.yoga, 60)]), isEmpty);
    });
  });

  group('effortStrengthDays', () {
    test('holds the dates of the strength sessions only', () {
      final strength = effortSessionOf(
        _imported(
          type: WorkoutType.strength,
          elapsed: const Duration(minutes: 45),
          start: _at(const LocalDate(2026, 11, 9), 7),
        ),
      );
      final short = effortSessionOf(
        _imported(
          type: WorkoutType.strength,
          elapsed: const Duration(minutes: 19, seconds: 59),
          start: _at(const LocalDate(2026, 11, 8), 7),
        ),
      );
      final run = effortSessionOf(
        _imported(
          type: WorkoutType.running,
          elapsed: const Duration(minutes: 45),
          start: _at(const LocalDate(2026, 11, 7), 7),
        ),
      );

      expect(effortStrengthDays([strength, short, run]), {
        const LocalDate(2026, 11, 9),
      });
    });

    test('is empty without sessions', () {
      expect(effortStrengthDays(const []), isEmpty);
    });
  });
}
