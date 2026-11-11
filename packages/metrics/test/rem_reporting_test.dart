import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

SleepNight night(int day, {required bool rem}) {
  final start = DateTime.utc(2026, 11, day, 23);
  final mid = start.add(const Duration(hours: 4));
  return SleepNight([
    SleepSpan(
      start: start,
      end: mid,
      phase: SleepPhase.light,
      utcOffset: Duration.zero,
    ),
    SleepSpan(
      start: mid,
      end: mid.add(const Duration(hours: 2)),
      phase: rem ? SleepPhase.rem : SleepPhase.deep,
      utcOffset: Duration.zero,
    ),
  ]);
}

void main() {
  group('observe', () {
    test('one night with REM is enough to know the ring reports it', () {
      expect(
        RemReporting.observe(nights: 1, nightsWithRem: 1),
        RemReporting.reported,
      );
      expect(
        RemReporting.observe(nights: 40, nightsWithRem: 1),
        RemReporting.reported,
      );
    });

    test('no REM across seven nights means the ring does not report it', () {
      expect(remAbsentAfterNights, 7);
      expect(
        RemReporting.observe(nights: 7, nightsWithRem: 0),
        RemReporting.absent,
      );
      expect(
        RemReporting.observe(nights: 30, nightsWithRem: 0),
        RemReporting.absent,
      );
    });

    test('fewer nights without REM are not yet a verdict', () {
      expect(
        RemReporting.observe(nights: 0, nightsWithRem: 0),
        RemReporting.unknown,
      );
      expect(
        RemReporting.observe(nights: 6, nightsWithRem: 0),
        RemReporting.unknown,
      );
    });

    test('the threshold can be set per call', () {
      expect(
        RemReporting.observe(nights: 3, nightsWithRem: 0, absentAfter: 3),
        RemReporting.absent,
      );
    });

    test('rejects counts that cannot happen', () {
      expect(
        () => RemReporting.observe(nights: 2, nightsWithRem: 3),
        throwsArgumentError,
      );
      expect(
        () => RemReporting.observe(nights: 2, nightsWithRem: -1),
        throwsArgumentError,
      );
      expect(
        () => RemReporting.observe(nights: 2, nightsWithRem: 0, absentAfter: 0),
        throwsArgumentError,
      );
    });
  });

  test('only an absent verdict drops REM from the score', () {
    expect(RemReporting.reported.measured, isTrue);
    expect(RemReporting.unknown.measured, isTrue);
    expect(RemReporting.absent.measured, isFalse);
  });

  group('ofNights', () {
    test('counts the nights that hold any REM time', () {
      final nights = [
        for (var day = 1; day <= 7; day++) night(day, rem: day == 4),
      ];

      expect(RemReporting.ofNights(nights), RemReporting.reported);
    });

    test('seven nights of light and deep only are absent', () {
      final nights = [
        for (var day = 1; day <= 7; day++) night(day, rem: false),
      ];

      expect(RemReporting.ofNights(nights), RemReporting.absent);
      expect(RemReporting.ofNights(nights.take(6)), RemReporting.unknown);
    });

    test('an absent verdict renormalises the score as metrics.md defines', () {
      final nights = [
        for (var day = 1; day <= 7; day++) night(day, rem: false),
      ];
      final reporting = RemReporting.ofNights(nights);

      final score = sleepScore(
        nights.last,
        remMeasured: reporting.measured,
      ) as Scored<SleepFactor>;

      expect(score.of(SleepFactor.rem), isNull);
      expect(
        score.contributions.fold<double>(0, (sum, c) => sum + c.weight),
        closeTo(100, 1e-9),
      );
      expect(score.of(SleepFactor.deep)!.weight, closeTo(2000 / 85, 1e-9));
    });
  });
}
