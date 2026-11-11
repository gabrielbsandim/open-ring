import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/trends/domain/trend_metric.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

extension TrendMetricLabels on TrendMetric {
  String label(AppLocalizations l10n) => switch (this) {
    TrendMetric.restingHeartRate => l10n.trendsMetricRestingHeartRate,
    TrendMetric.hrv => l10n.trendsMetricHrv,
    TrendMetric.sleepDuration => l10n.trendsMetricSleep,
    TrendMetric.sleepScore => l10n.trendsMetricSleepScore,
    TrendMetric.steps => l10n.trendsMetricSteps,
    TrendMetric.spo2 => l10n.trendsMetricSpo2,
  };

  Color accent(AppColors colors) => switch (this) {
    TrendMetric.restingHeartRate || TrendMetric.hrv => colors.heart,
    TrendMetric.sleepDuration || TrendMetric.sleepScore => colors.sleep,
    TrendMetric.steps => colors.activity,
    TrendMetric.spo2 => colors.oxygen,
  };

  String averageLabel(AppLocalizations l10n) => switch (this) {
    TrendMetric.restingHeartRate => l10n.heartAverageBpm,
    TrendMetric.hrv => l10n.heartAverageMs,
    TrendMetric.sleepDuration => l10n.trendsAverageAsleep,
    TrendMetric.sleepScore => l10n.trendsAverageScore,
    TrendMetric.steps => l10n.trendsAverageSteps,
    TrendMetric.spo2 => l10n.heartAveragePercent,
  };

  String source(AppLocalizations l10n) => switch (this) {
    TrendMetric.restingHeartRate => l10n.heartRestingSource,
    TrendMetric.hrv => l10n.trendsSourceHrv,
    TrendMetric.sleepDuration => l10n.trendsSourceSleep,
    TrendMetric.sleepScore => l10n.trendsSourceSleepScore,
    TrendMetric.steps => l10n.trendsSourceSteps,
    TrendMetric.spo2 => l10n.trendsSourceSpo2,
  };

  String emptyMessage(AppLocalizations l10n) =>
      isNightly ? l10n.trendsEmptyNights : l10n.trendsEmptySteps;

  String number(MetricFormat format, double value) => switch (this) {
    TrendMetric.sleepDuration => format.duration(
      Duration(minutes: value.round()),
    ),
    TrendMetric.spo2 => format.percent(value),
    _ => format.integer(value),
  };

  String withUnit(MetricFormat format, double value) => switch (this) {
    TrendMetric.restingHeartRate => format.bpm(value),
    TrendMetric.hrv => format.ms(value),
    TrendMetric.steps => format.l10n.trendsStepsValue(format.integer(value)),
    _ => number(format, value),
  };

  int get _deltaStep => this == TrendMetric.steps ? 10 : 1;

  int roundedDelta(double change) =>
      (change.abs() / _deltaStep).round() * _deltaStep;

  String delta(MetricFormat format, int amount) {
    final l10n = format.l10n;
    return switch (this) {
      TrendMetric.restingHeartRate => format.bpm(amount.toDouble()),
      TrendMetric.hrv => format.ms(amount.toDouble()),
      TrendMetric.sleepDuration => l10n.trendsPerNight(
        format.duration(Duration(minutes: amount)),
      ),
      TrendMetric.steps => l10n.trendsStepsPerDay(format.integer(amount)),
      TrendMetric.sleepScore || TrendMetric.spo2 => l10n.trendsPoints(amount),
    };
  }
}

extension TrendRangeLabels on TrendRange {
  String label(AppLocalizations l10n) => l10n.trendsRangeDays(days);
}
