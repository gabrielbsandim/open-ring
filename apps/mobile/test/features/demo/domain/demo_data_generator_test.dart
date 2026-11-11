import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/demo/domain/demo_data.dart';
import 'package:open_ring/features/demo/domain/demo_data_generator.dart';
import 'package:open_ring/features/ring/domain/sleep_session_span.dart';
import 'package:ring_driver/ring_driver.dart';

final now = DateTime(2026, 11, 11, 14, 37);

DemoData generate([DateTime? at]) =>
    DemoDataGenerator(now: at ?? now).generate();

String fingerprint(DemoData data) => [
  for (final s in data.heartRate) '${s.at.millisecondsSinceEpoch}:${s.bpm}',
  for (final s in data.hrv) '${s.at.millisecondsSinceEpoch}:${s.milliseconds}',
  for (final s in data.spo2) '${s.at.millisecondsSinceEpoch}:${s.percent}',
  for (final s in data.stress) '${s.at.millisecondsSinceEpoch}:${s.level}',
  for (final b in data.activity) '${b.start.millisecondsSinceEpoch}:${b.steps}',
  for (final s in data.sleep)
    '${s.start.millisecondsSinceEpoch}:${s.stage.name}',
  for (final w in data.workouts)
    '${w.start.millisecondsSinceEpoch}:${w.heartRate.length}',
].join(',');

Map<DateTime, int> stepsByDay(DemoData data) {
  final days = <DateTime, int>{};
  for (final bucket in data.activity) {
    final day = DateTime(
      bucket.start.year,
      bucket.start.month,
      bucket.start.day,
    );
    days[day] = (days[day] ?? 0) + bucket.steps;
  }
  return days;
}

void main() {
  test('the same instant always gives the same data', () {
    expect(fingerprint(generate()), fingerprint(generate()));
  });

  test('a later refresh on the same day keeps the earlier history', () {
    final morning = generate(DateTime(2026, 11, 11, 9));
    final evening = generate(DateTime(2026, 11, 11, 21));
    final cut = DateTime(2026, 11, 11);

    final before = [
      for (final s in morning.heartRate)
        if (s.at.isBefore(cut)) s.bpm,
    ];
    final later = [
      for (final s in evening.heartRate)
        if (s.at.isBefore(cut)) s.bpm,
    ];

    expect(later, before);
  });

  test('history moves with the current day', () {
    DateTime dayOf(DemoData data) {
      final first = data.heartRate.first.at;
      return DateTime(first.year, first.month, first.day);
    }

    final today = generate();
    final tomorrow = generate(now.add(const Duration(days: 1)));

    expect(dayOf(tomorrow).difference(dayOf(today)), const Duration(days: 1));
  });

  test('nothing is dated after now', () {
    final data = generate();

    expect(data.syncedAt, now);
    expect(data.heartRate.every((s) => !s.at.isAfter(now)), isTrue);
    expect(data.hrv.every((s) => !s.at.isAfter(now)), isTrue);
    expect(data.spo2.every((s) => !s.at.isAfter(now)), isTrue);
    expect(data.stress.every((s) => !s.at.isAfter(now)), isTrue);
    expect(
      data.activity.every((b) => !b.start.add(b.duration).isAfter(now)),
      isTrue,
    );
    expect(data.sleep.every((s) => !s.end.isAfter(now)), isTrue);
    expect(data.workouts.every((w) => !w.end.isAfter(now)), isTrue);
    expect(data.syncRuns.every((r) => !r.at.isAfter(now)), isTrue);
  });

  test('heart rate comes every five minutes for fourteen days', () {
    final samples = generate().heartRate;

    for (var i = 1; i < samples.length; i++) {
      expect(
        samples[i].at.difference(samples[i - 1].at),
        DemoDataGenerator.heartRateInterval,
      );
    }
    expect(
      samples.first.at.isBefore(DateTime(2026, 10, 28)),
      isTrue,
      reason: 'the first night starts the evening before the first day',
    );
    expect(samples.last.at, DateTime(2026, 11, 11, 14, 35));
  });

  test('hrv, spo2 and stress follow their own intervals', () {
    final data = generate();

    expect(data.hrv.every((s) => s.at.minute % 30 == 0), isTrue);
    expect(data.spo2.every((s) => s.at.minute == 0), isTrue);
    expect(data.stress.every((s) => s.at.minute % 30 == 0), isTrue);
    expect(data.hrv.length, greaterThan(14 * 40));
    expect(data.spo2.length, greaterThan(14 * 20));
    expect(data.stress.length, greaterThan(14 * 25));
  });

  test('every night is one session with every sleep stage', () {
    final nights = SleepSessionSpan.group(generate().sleep);

    expect(nights, hasLength(15));
    for (final night in nights) {
      final length = night.end.difference(night.start);
      expect(length, greaterThan(const Duration(hours: 6)));
      expect(length, lessThan(const Duration(hours: 10)));
      for (var i = 1; i < night.segments.length; i++) {
        expect(night.segments[i].start, night.segments[i - 1].end);
      }
      final stages = {for (final s in night.segments) s.stage};
      expect(
        stages,
        containsAll([SleepStage.light, SleepStage.deep, SleepStage.rem]),
      );
    }
  });

  test('a night still in progress is left out', () {
    final early = generate(DateTime(2026, 11, 11, 3));

    expect(SleepSessionSpan.group(early.sleep), hasLength(14));
    expect(
      early.sleep.every((s) => s.end.isBefore(DateTime(2026, 11, 11))),
      isTrue,
    );
  });

  test('readings stay in a healthy, believable range', () {
    final data = generate();

    expect(data.heartRate.every((s) => s.bpm >= 40 && s.bpm <= 190), isTrue);
    expect(
      data.hrv.every((s) => s.milliseconds >= 10 && s.milliseconds <= 120),
      isTrue,
    );
    expect(data.spo2.every((s) => s.percent >= 90 && s.percent <= 100), isTrue);
    expect(data.stress.every((s) => s.level >= 1 && s.level <= 100), isTrue);
    expect(data.activity.every((b) => b.steps > 0), isTrue);
    expect(data.battery.percent, inInclusiveRange(20, 100));
  });

  test('every full day walks a plausible number of steps', () {
    final days = stepsByDay(generate());

    expect(days, hasLength(15));
    final full = days.entries.where(
      (e) => e.key.isBefore(DateTime(2026, 11, 11)),
    );
    for (final MapEntry(key: day, value: steps) in full) {
      expect(steps, inInclusiveRange(4000, 16000), reason: '$day');
    }
  });

  test('two workouts carry their own heart rate and no route', () {
    final workouts = generate().workouts;

    expect(workouts, hasLength(2));
    for (final workout in workouts) {
      final beats = [for (final s in workout.heartRate) s.bpm];
      expect(beats, isNotEmpty);
      expect(workout.route.isEmpty, isTrue);
      expect(workout.gps, isFalse);
      expect(workout.maxHeartRate, beats.reduce((a, b) => a > b ? a : b));
      expect(
        workout.averageHeartRate,
        inExclusiveRange(90, workout.maxHeartRate!),
      );
      expect(workout.activeKilocalories, greaterThan(0));
      expect(workout.elapsed, workout.end.difference(workout.start));
    }
  });

  test('a short history leaves out workouts older than it', () {
    final data = DemoDataGenerator(now: now, days: 3).generate();

    expect(data.workouts, hasLength(1));
  });

  test('the demo ring can never be mistaken for a real one', () {
    final data = generate();

    expect(data.deviceId, demoDeviceId);
    expect(data.deviceId, contains('DEMO'));
    expect(
      RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(data.deviceId),
      isFalse,
    );
    expect(data.identity.name, 'R09 Demo');
  });
}
