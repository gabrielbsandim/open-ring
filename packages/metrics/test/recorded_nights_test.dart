import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

const pathVariable = 'OPENRING_RECORDED_NIGHTS';

DateTime instant(Object? utcMs) =>
    DateTime.fromMillisecondsSinceEpoch(utcMs! as int, isUtc: true);

SleepSpan spanOf(Map<String, dynamic> row) => SleepSpan(
  start: instant(row['startUtcMs']),
  end: instant(row['endUtcMs']),
  phase: SleepPhase.values.byName(row['stage'] as String),
  utcOffset: Duration(minutes: row['offsetMinutes'] as int),
);

BpmSample sampleOf(Map<String, dynamic> row) =>
    (at: instant(row['atUtcMs']), bpm: row['bpm'] as int);

List<T> rows<T>(
  Map<String, dynamic> recording,
  String key,
  T Function(Map<String, dynamic>) parse,
) => [
  for (final row in recording[key] as List<dynamic>)
    parse(row as Map<String, dynamic>),
];

bool within(DateTime at, SleepNight night) =>
    !at.isBefore(night.start) && !at.isAfter(night.end);

String fingerprint(Iterable<SleepNight> nights) => [
  for (final n in nights) '${n.start} ${n.end} ${n.asleep} ${n.spans.length}',
].join('|');

// Real nights are personal health data, so they stay outside the repository
// and this suite runs only when the variable names their file.
void main() {
  final path = Platform.environment[pathVariable];
  if (path == null) {
    test('recorded nights', () {}, skip: '$pathVariable is not set');
    return;
  }

  final recording =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final spans = rows(recording, 'spans', spanOf);
  final heartRate = rows(recording, 'heartRate', sampleOf);
  final nights = stitchSleep(spans);

  test('the recording holds at least one night', () {
    expect(nights, isNotEmpty);
  });

  test('stitching does not depend on the order of the spans', () {
    final expected = fingerprint(nights);
    for (var seed = 0; seed < 20; seed++) {
      final shuffled = [...spans]..shuffle(Random(seed));
      expect(fingerprint(stitchSleep(shuffled)), expected);
    }
  });

  test('the nights do not overlap', () {
    for (var i = 1; i < nights.length; i++) {
      expect(nights[i].start.isBefore(nights[i - 1].end), isFalse);
    }
  });

  test('the spans of a night are ordered and do not overlap', () {
    for (final night in nights) {
      for (var i = 1; i < night.spans.length; i++) {
        expect(night.spans[i].start.isBefore(night.spans[i - 1].end), isFalse);
      }
    }
  });

  test('spans and gaps add up to time in bed', () {
    for (final night in nights) {
      final spanTime = night.spans.fold(
        Duration.zero,
        (sum, span) => sum + span.duration,
      );
      final gapTime = night.gaps.fold(
        Duration.zero,
        (sum, gap) => sum + gap.duration,
      );
      expect(spanTime + gapTime, night.timeInBed);
    }
  });

  test('efficiency is a fraction and awakenings fit in the awake time', () {
    for (final night in nights) {
      expect(night.efficiency, inInclusiveRange(0, 1));
      expect(night.wakeAfterSleepOnset <= night.awake, isTrue);
    }
  });

  test('each night falls on its wake date', () {
    for (final night in nights) {
      final wake = night.end.add(night.spans.last.utcOffset);
      expect(night.date, LocalDate(wake.year, wake.month, wake.day));
    }
  });

  test('a scored night stays within 0 and 100, a short one is not scored', () {
    for (final night in nights) {
      final result = sleepScore(night);
      if (night.asleep < minimumScoredSleep) {
        expect(result, isA<InsufficientData<SleepFactor>>());
        continue;
      }
      expect((result as Scored<SleepFactor>).value, inInclusiveRange(0, 100));
    }
  });

  test('resting heart rate comes from the readings of that night', () {
    for (final night in nights) {
      final valid = [
        for (final s in heartRate)
          if (s.bpm > 0 && within(s.at, night)) s.bpm,
      ];
      final resting = restingHeartRate(
        heartRate.where((s) => within(s.at, night)),
      );
      if (resting == null) continue;
      expect(resting, inInclusiveRange(valid.reduce(min), valid.reduce(max)));
    }
  });
}
