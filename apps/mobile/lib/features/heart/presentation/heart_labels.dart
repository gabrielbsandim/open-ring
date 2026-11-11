import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

enum HeartMetric { heartRate, hrv, spo2, stress }

extension HeartMetricLabels on HeartMetric {
  String shortLabel(AppLocalizations l10n) => switch (this) {
    HeartMetric.heartRate => l10n.heartMetricHeartRate,
    HeartMetric.hrv => l10n.heartMetricHrv,
    HeartMetric.spo2 => l10n.heartMetricSpo2,
    HeartMetric.stress => l10n.heartMetricStress,
  };

  String title(AppLocalizations l10n) => switch (this) {
    HeartMetric.heartRate => l10n.heartTitleHeartRate,
    HeartMetric.hrv => l10n.heartTitleHrv,
    HeartMetric.spo2 => l10n.heartTitleSpo2,
    HeartMetric.stress => l10n.heartTitleStress,
  };

  String averageLabel(AppLocalizations l10n) => switch (this) {
    HeartMetric.heartRate => l10n.heartAverageBpm,
    HeartMetric.hrv => l10n.heartAverageMs,
    HeartMetric.spo2 => l10n.heartAveragePercent,
    HeartMetric.stress => l10n.heartAverage,
  };

  Color accent(AppColors colors) => switch (this) {
    HeartMetric.heartRate || HeartMetric.hrv => colors.heart,
    HeartMetric.spo2 => colors.oxygen,
    HeartMetric.stress => colors.stress,
  };
}

extension StressBandLabels on StressBand {
  String label(AppLocalizations l10n) => switch (this) {
    StressBand.rest => l10n.heartStressBandRest,
    StressBand.low => l10n.heartStressBandLow,
    StressBand.medium => l10n.heartStressBandMedium,
    StressBand.high => l10n.heartStressBandHigh,
  };
}
