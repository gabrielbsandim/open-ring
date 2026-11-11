import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

BaselineDeviation z(double zScore) =>
    BaselineDeviation(today: 1, baseline: 1, zScore: zScore);

ActivityLoad load(double ratio) => ActivityLoad(
  acute: ratio * 100,
  chronic: 100,
  acuteDays: 7,
  chronicDays: 28,
);

Scored<ReadinessFactor> scored(ScoreResult<ReadinessFactor> result) =>
    result as Scored<ReadinessFactor>;

void main() {
  test('each band starts at its published score', () {
    expect(readinessBand(100), ReadinessBand.optimal);
    expect(readinessBand(85), ReadinessBand.optimal);
    expect(readinessBand(84), ReadinessBand.good);
    expect(readinessBand(70), ReadinessBand.good);
    expect(readinessBand(69), ReadinessBand.fair);
    expect(readinessBand(55), ReadinessBand.fair);
    expect(readinessBand(54), ReadinessBand.low);
    expect(readinessBand(0), ReadinessBand.low);
  });

  test('a day at baseline with a good night', () {
    final result = scored(
      readiness(
        sleepScore: 82,
        hrv: z(0),
        restingHeartRate: z(0),
        activityLoad: load(1),
      ),
    );
    expect(result.of(ReadinessFactor.sleep)!.points, closeTo(28.7, 1e-9));
    expect(result.of(ReadinessFactor.hrv)!.subscore, 0.75);
    expect(result.of(ReadinessFactor.restingHeartRate)!.subscore, 0.75);
    expect(result.of(ReadinessFactor.activityLoad)!.value, 1);
    expect(result.of(ReadinessFactor.activityLoad)!.points, 15);
    expect(result.total, closeTo(81.2, 1e-9));
    expect(result.value, 81);
  });

  test('without an activity load its weight is shared by the rest', () {
    final result = scored(
      readiness(sleepScore: 82, hrv: z(0), restingHeartRate: z(0)),
    );
    expect(result.of(ReadinessFactor.activityLoad), isNull);
    expect(result.of(ReadinessFactor.sleep)!.weight, closeTo(3500 / 85, 1e-9));
    expect(result.total, closeTo(66.2 / 0.85, 1e-9));
    expect(result.value, 78);
  });

  test('missing sleep, HRV or resting HR is insufficient data', () {
    final result = readiness(
      sleepScore: null,
      hrv: null,
      restingHeartRate: z(0),
      activityLoad: load(1),
    );
    expect(result, isA<InsufficientData<ReadinessFactor>>());
    expect((result as InsufficientData<ReadinessFactor>).missing, [
      ReadinessFactor.sleep,
      ReadinessFactor.hrv,
    ]);
    final none = readiness(sleepScore: null, hrv: null, restingHeartRate: null);
    expect((none as InsufficientData<ReadinessFactor>).missing, hasLength(3));
  });

  group('boundaries', () {
    double sub(ReadinessFactor f, {double h = 0, double r = 0, double a = 1}) =>
        scored(
          readiness(
            sleepScore: 50,
            hrv: z(h),
            restingHeartRate: z(r),
            activityLoad: load(a),
          ),
        ).of(f)!.subscore;

    test('HRV: one SD above is full, three below is zero', () {
      expect(sub(ReadinessFactor.hrv, h: 1), 1);
      expect(sub(ReadinessFactor.hrv, h: 2.5), 1);
      expect(sub(ReadinessFactor.hrv, h: -1), 0.5);
      expect(sub(ReadinessFactor.hrv, h: -3), 0);
      expect(sub(ReadinessFactor.hrv, h: -5), 0);
    });

    test('resting HR: one SD below is full, three above is zero', () {
      expect(sub(ReadinessFactor.restingHeartRate, r: -1), 1);
      expect(sub(ReadinessFactor.restingHeartRate, r: 1), 0.5);
      expect(sub(ReadinessFactor.restingHeartRate, r: 3), 0);
    });

    test('load: up to 1.3 is full, 2.0 and above is zero', () {
      expect(sub(ReadinessFactor.activityLoad, a: 0.4), 1);
      expect(sub(ReadinessFactor.activityLoad, a: 1.3), 1);
      expect(sub(ReadinessFactor.activityLoad, a: 1.65), closeTo(0.5, 1e-9));
      expect(sub(ReadinessFactor.activityLoad, a: 2), 0);
      expect(sub(ReadinessFactor.activityLoad, a: 3), 0);
    });

    test('scores stay inside 0 to 100', () {
      final best = readiness(
        sleepScore: 100,
        hrv: z(3),
        restingHeartRate: z(-3),
        activityLoad: load(0.8),
      );
      expect(scored(best).value, 100);
      final worst = readiness(
        sleepScore: 0,
        hrv: z(-4),
        restingHeartRate: z(4),
        activityLoad: load(2.5),
      );
      expect(scored(worst).value, 0);
    });
  });
}
