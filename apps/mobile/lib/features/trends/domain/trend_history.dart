import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/trends/domain/trend_metric.dart';
import 'package:open_ring/features/trends/domain/trend_series.dart';

@immutable
final class TrendHistory {
  new({
    required this.today,
    required Map<TrendMetric, List<DailyValue>> values,
    required Map<TrendMetric, TrendBand> bands,
  }) : _values = Map.unmodifiable(values),
       bands = Map.unmodifiable(bands);

  factory collect({
    required LocalDate today,
    required Iterable<SleepNight> nights,
    required List<BpmSample> heartRate,
    required List<HrvReading> hrv,
    required List<Spo2Reading> spo2,
    required List<DailyActivity> activity,
    required Duration sleepGoal,
    required bool remMeasured,
  }) {
    final kept = [
      for (final night in nights)
        if (_inHistory(today, night.date)) night,
    ];
    List<DailyValue> nightly(double? Function(SleepNight night) measure) => [
      for (final night in kept)
        if (measure(night) case final value?) (date: night.date, value: value),
    ];
    final resting = nightly(
      (n) => restingHeartRate(heartRate.where((s) => _during(s.at, n))),
    );
    final nightlyHrvValues = nightly(
      (n) => nightlyHrv(hrv.where((r) => _during(r.at, n))),
    );
    final values = <TrendMetric, List<DailyValue>>{
      TrendMetric.restingHeartRate: resting,
      TrendMetric.hrv: nightlyHrvValues,
      TrendMetric.sleepDuration: nightly((n) => n.asleep.inSeconds / 60),
      TrendMetric.sleepScore: nightly(
        (n) =>
            switch (sleepScore(n, goal: sleepGoal, remMeasured: remMeasured)) {
              Scored(:final value) => value.toDouble(),
              InsufficientData() => null,
            },
      ),
      TrendMetric.steps: [
        for (final day in activity)
          if (day.steps > 0 && _inHistory(today, day.date))
            (date: day.date, value: day.steps.toDouble()),
      ],
      TrendMetric.spo2: nightly(
        (n) => spo2NightSummary(spo2, from: n.start, to: n.end)?.mean,
      ),
    };
    final bands = <TrendMetric, TrendBand>{
      TrendMetric.restingHeartRate: ?baselineBand(
        restingHeartRateBaseline(resting, today: today),
      ),
      TrendMetric.hrv: ?baselineBand(
        hrvBaseline(nightlyHrvValues, today: today),
      ),
    };
    return TrendHistory(today: today, values: values, bands: bands);
  }

  final LocalDate today;
  final Map<TrendMetric, List<DailyValue>> _values;
  final Map<TrendMetric, TrendBand> bands;

  List<DailyValue> values(TrendMetric metric) => _values[metric] ?? const [];

  bool get isEmpty => _values.values.every((v) => v.isEmpty);

  TrendSeries series(TrendMetric metric, TrendRange range) => TrendSeries.of(
    values(metric),
    today: today,
    days: range.days,
    partialLast: !metric.isNightly,
  );

  static bool _inHistory(LocalDate today, LocalDate date) {
    final age = today.daysSince(date);
    return age >= 0 && age < trendHistoryDays;
  }

  static bool _during(DateTime at, SleepNight night) =>
      !at.isBefore(night.start) && at.isBefore(night.end);
}

TrendBand? baselineBand(BaselineResult baseline) => switch (baseline) {
  BaselineBuilding() => null,
  BaselineReady(
    scale: BaselineScale.linear,
    :final meanOnScale,
    :final sdOnScale,
  ) =>
    (low: meanOnScale - sdOnScale, high: meanOnScale + sdOnScale),
  BaselineReady(
    scale: BaselineScale.log,
    :final meanOnScale,
    :final sdOnScale,
  ) =>
    (
      low: math.exp(meanOnScale - sdOnScale),
      high: math.exp(meanOnScale + sdOnScale),
    ),
};
