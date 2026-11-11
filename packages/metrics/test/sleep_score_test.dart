import 'package:metrics/metrics.dart';
import 'package:metrics/src/scoring.dart';
import 'package:test/test.dart';

final from = DateTime.utc(2026, 11, 10, 2);

SleepNight night(List<(SleepPhase, int)> parts) {
  var at = from;
  return SleepNight([
    for (final (phase, minutes) in parts)
      SleepSpan(
        start: at,
        end: at = at.add(Duration(minutes: minutes)),
        phase: phase,
        utcOffset: Duration.zero,
      ),
  ]);
}

const SleepPhase light = SleepPhase.light;
const SleepPhase deep = SleepPhase.deep;
const SleepPhase rem = SleepPhase.rem;
const SleepPhase awake = SleepPhase.awake;

Scored<SleepFactor> scored(ScoreResult<SleepFactor> result) =>
    result as Scored<SleepFactor>;

void main() {
  group('ramp', () {
    test('is zero and one at its ends and linear between', () {
      expect(ramp(65, zeroAt: 65, fullAt: 85), 0);
      expect(ramp(85, zeroAt: 65, fullAt: 85), 1);
      expect(ramp(75, zeroAt: 65, fullAt: 85), 0.5);
      expect(ramp(10, zeroAt: 65, fullAt: 85), 0);
      expect(ramp(99, zeroAt: 65, fullAt: 85), 1);
    });

    test('runs downhill when zeroAt is above fullAt', () {
      expect(ramp(30, zeroAt: 60, fullAt: 30), 1);
      expect(ramp(45, zeroAt: 60, fullAt: 30), 0.5);
      expect(ramp(60, zeroAt: 60, fullAt: 30), 0);
    });
  });

  test('typical night scores from each published input', () {
    final result = scored(
      sleepScore(
        night([
          (awake, 15),
          (light, 60),
          (deep, 50),
          (light, 40),
          (rem, 30),
          (awake, 5),
          (light, 60),
          (deep, 30),
          (rem, 40),
          (light, 60),
          (rem, 30),
          (awake, 10),
        ]),
      ),
    );
    final duration = result.of(SleepFactor.duration)!;
    expect(duration.value, 400);
    expect(duration.weight, 35);
    expect(duration.points, closeTo(35 * 400 / 480, 1e-9));
    expect(result.of(SleepFactor.efficiency)!.value, closeTo(4000 / 43, 1e-9));
    expect(result.of(SleepFactor.efficiency)!.points, 20);
    expect(result.of(SleepFactor.latency)!.value, 15);
    expect(result.of(SleepFactor.latency)!.points, 10);
    expect(result.of(SleepFactor.deep)!.value, closeTo(20, 1e-9));
    expect(result.of(SleepFactor.rem)!.value, closeTo(25, 1e-9));
    expect(result.total, closeTo(94.1667, 1e-4));
    expect(result.value, 94);
  });

  test('a full, efficient night with enough deep and REM scores 100', () {
    final result = sleepScore(
      night([(light, 200), (deep, 90), (rem, 110), (light, 80)]),
    );
    expect(scored(result).value, 100);
  });

  test('longer than the goal earns no extra credit', () {
    final result = scored(
      sleepScore(night([(light, 400), (deep, 120), (rem, 130)])),
    );
    expect(result.of(SleepFactor.duration)!.subscore, 1);
    expect(
      scored(
        sleepScore(
          night([(light, 400), (deep, 120), (rem, 130)]),
          goal: const Duration(hours: 12),
        ),
      ).of(SleepFactor.duration)!.subscore,
      closeTo(650 / 720, 1e-9),
    );
  });

  group('REM', () {
    final noRem = night([(awake, 15), (light, 300), (deep, 100)]);

    test('counts as zero when the ring measures it but none was seen', () {
      final result = scored(sleepScore(noRem));
      expect(result.of(SleepFactor.rem)!.subscore, 0);
      expect(result.value, 79);
    });

    test(
      'drops out and its weight is shared when the ring cannot measure it',
      () {
        final result = scored(sleepScore(noRem, remMeasured: false));
        expect(result.of(SleepFactor.rem), isNull);
        expect(
          result.contributions.fold<double>(0, (sum, c) => sum + c.weight),
          closeTo(100, 1e-9),
        );
        expect(
          result.of(SleepFactor.duration)!.weight,
          closeTo(3500 / 85, 1e-9),
        );
        expect(result.value, 93);
      },
    );
  });

  group('boundaries', () {
    test('efficiency of 85 percent is full credit, 65 percent is none', () {
      final full = scored(sleepScore(night([(light, 85), (awake, 15)])));
      expect(full.of(SleepFactor.efficiency)!.subscore, closeTo(1, 1e-9));
      final none = scored(
        sleepScore(night([(light, 65), (awake, 70), (light, 65)])),
      );
      expect(none.of(SleepFactor.efficiency)!.subscore, closeTo(0, 1e-9));
    });

    test('latency of 45 minutes is half credit', () {
      final result = scored(
        sleepScore(night([(awake, 45), (light, 400), (deep, 80)])),
      );
      expect(result.of(SleepFactor.latency)!.subscore, closeTo(0.5, 1e-9));
    });

    test('one hour asleep is scored, one minute less is not', () {
      expect(sleepScore(night([(light, 60)])), isA<Scored<SleepFactor>>());
      final short = sleepScore(night([(light, 59)]));
      expect(short, isA<InsufficientData<SleepFactor>>());
      expect((short as InsufficientData<SleepFactor>).missing, [
        SleepFactor.duration,
      ]);
    });
  });

  test('no night or no sleep is insufficient data, not a zero', () {
    expect(sleepScore(null), isA<InsufficientData<SleepFactor>>());
    expect(
      sleepScore(night([(awake, 480)])),
      isA<InsufficientData<SleepFactor>>(),
    );
  });

  test('rejects a goal that is not positive', () {
    expect(
      () => sleepScore(night([(light, 60)]), goal: Duration.zero),
      throwsArgumentError,
    );
  });
}
