import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/trends/domain/trend_history.dart';
import 'package:open_ring/features/trends/domain/trend_metric.dart';

const _today = LocalDate(2026, 11, 10);

SleepNight _night(
  LocalDate date, {
  Duration length = const Duration(hours: 7),
}) {
  final end = DateTime.utc(date.year, date.month, date.day, 6);
  return SleepNight([
    SleepSpan(
      start: end.subtract(length),
      end: end,
      phase: SleepPhase.light,
      utcOffset: Duration.zero,
    ),
  ]);
}

List<BpmSample> _heartRate(SleepNight night, int bpm) => [
  for (var i = 0; i < 12; i++)
    (at: night.start.add(Duration(minutes: 5 * i)), bpm: bpm),
];

DailyActivity _steps(LocalDate date, int steps) => DailyActivity(
  date: date,
  steps: steps,
  activeKilocalories: 0,
  distanceMeters: 0,
);

TrendHistory _collect({
  LocalDate today = _today,
  List<SleepNight> nights = const [],
  List<BpmSample> heartRate = const [],
  List<HrvReading> hrv = const [],
  List<Spo2Reading> spo2 = const [],
  List<DailyActivity> activity = const [],
}) => TrendHistory.collect(
  today: today,
  nights: nights,
  heartRate: heartRate,
  hrv: hrv,
  spo2: spo2,
  activity: activity,
  sleepGoal: defaultSleepGoal,
  remMeasured: true,
);

void main() {
  test('with nothing recorded every series is empty', () {
    final history = _collect();

    expect(history.isEmpty, isTrue);
    expect(history.series(TrendMetric.steps, TrendRange.week).hasStats, false);
    expect(history.bands, isEmpty);
  });

  test('dates nightly values by the night and leaves a night without '
      'enough samples as a gap', () {
    final measured = _night(_today.addDays(-1));
    final bare = _night(_today);
    final history = _collect(
      nights: [measured, bare],
      heartRate: [..._heartRate(measured, 55), ..._heartRate(bare, 50).take(2)],
    );

    final series = history.series(
      TrendMetric.restingHeartRate,
      TrendRange.week,
    );

    expect(series.points[5].value, 55);
    expect(series.latest, isNull);
    expect(series.measuredDays, 1);
    expect(
      history.series(TrendMetric.sleepDuration, TrendRange.week).latest,
      420,
    );
  });

  test('a night across the autumn DST change keeps its real length and the '
      'date of the wake offset', () {
    final night = SleepNight([
      SleepSpan(
        start: DateTime.utc(2026, 10, 24, 20),
        end: DateTime.utc(2026, 10, 25, 1),
        phase: SleepPhase.light,
        utcOffset: const Duration(hours: 2),
      ),
      SleepSpan(
        start: DateTime.utc(2026, 10, 25, 1),
        end: DateTime.utc(2026, 10, 25, 5),
        phase: SleepPhase.deep,
        utcOffset: const Duration(hours: 1),
      ),
    ]);
    final history = _collect(
      today: const LocalDate(2026, 10, 27),
      nights: [night],
      activity: [_steps(const LocalDate(2026, 10, 25), 9000)],
    );

    final sleep = history.series(TrendMetric.sleepDuration, TrendRange.week);
    final steps = history.series(TrendMetric.steps, TrendRange.week);

    expect(sleep.days, 7);
    expect(sleep.points[4].date, const LocalDate(2026, 10, 25));
    expect(sleep.points[4].value, 540);
    expect(sleep.measuredDays, 1);
    expect(steps.points[4].value, 9000);
  });

  test('scores each night and leaves out nights too short to score', () {
    final history = _collect(
      nights: [
        _night(_today.addDays(-1)),
        _night(_today, length: const Duration(minutes: 40)),
      ],
    );

    final scores = history.values(TrendMetric.sleepScore);

    expect(scores, hasLength(1));
    expect(scores.single.date, _today.addDays(-1));
  });

  test('a day with zero steps counts as not worn', () {
    final history = _collect(
      activity: [
        _steps(_today.addDays(-1), 0),
        _steps(_today.addDays(-2), 4200),
      ],
    );

    expect(history.values(TrendMetric.steps), [
      (date: _today.addDays(-2), value: 4200.0),
    ]);
  });

  test('drops what is older than the longest range', () {
    final old = _night(_today.addDays(-trendHistoryDays));
    final history = _collect(
      nights: [old],
      activity: [_steps(_today.addDays(-trendHistoryDays), 5000)],
    );

    expect(history.isEmpty, isTrue);
  });

  test('SpO2 is the mean of the plausible readings of the night', () {
    final night = _night(_today);
    final history = _collect(
      nights: [night],
      spo2: [
        for (final (i, percent) in [96, 98, 97, 40].indexed)
          (at: night.start.add(Duration(hours: i)), percent: percent),
      ],
    );

    expect(history.series(TrendMetric.spo2, TrendRange.week).latest, 97);
  });

  test('a resting HR band appears once the baseline has seven nights', () {
    final nights = [
      for (var age = 1; age <= 8; age++) _night(_today.addDays(-age)),
    ];
    final history = _collect(
      nights: nights,
      heartRate: [
        for (final (i, n) in nights.indexed) ..._heartRate(n, 56 + i % 3 * 2),
      ],
    );

    final band = history.bands[TrendMetric.restingHeartRate]!;

    expect(band.low, lessThan(58));
    expect(band.high, greaterThan(58));
    expect(history.bands.containsKey(TrendMetric.hrv), isFalse);
  });

  test('the HRV band is read on the log scale and returned in ms', () {
    final band = baselineBand(
      const BaselineReady(
        scale: BaselineScale.log,
        meanOnScale: 3.7,
        sdOnScale: 0.1,
        days: 10,
      ),
    )!;

    expect(band.low, closeTo(36.598, 1e-3));
    expect(band.high, closeTo(44.701, 1e-3));
    expect(
      baselineBand(const BaselineBuilding(daysCollected: 3, daysNeeded: 7)),
      isNull,
    );
  });
}
