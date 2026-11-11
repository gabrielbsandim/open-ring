import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/heart/presentation/baseline_text.dart';
import 'package:open_ring/features/today/application/readiness_view.dart';

extension ReadinessFactorLabels on ReadinessFactor {
  String label(MetricFormat format) => switch (this) {
    ReadinessFactor.sleep => format.l10n.readinessFactorSleep,
    ReadinessFactor.hrv => format.l10n.readinessFactorHrv,
    ReadinessFactor.restingHeartRate => format.l10n.readinessFactorRestingHr,
    ReadinessFactor.activityLoad => format.l10n.readinessFactorLoad,
  };

  Color accent(AppColors colors) => switch (this) {
    ReadinessFactor.sleep => colors.sleep,
    ReadinessFactor.hrv || ReadinessFactor.restingHeartRate => colors.heart,
    ReadinessFactor.activityLoad => colors.activity,
  };
}

typedef FactorText = ({String? value, String? baseline, String note});

FactorText describeFactor(
  MetricFormat format,
  ReadinessView view,
  ReadinessFactor factor,
) {
  final l10n = format.l10n;
  return switch (factor) {
    ReadinessFactor.sleep => _sleep(format, view),
    ReadinessFactor.hrv => (
      value: _maybe(view.hrv.today, format.ms),
      baseline: _typical(format, view.hrv.baseline, format.ms),
      note: baselineLine(
        format,
        view.hrv,
        compared: (d) => hrvVersusBaseline(format, d),
        missing: l10n.readinessNightMissing,
      ),
    ),
    ReadinessFactor.restingHeartRate => (
      value: _maybe(view.restingHeartRate.today, format.bpm),
      baseline: _typical(format, view.restingHeartRate.baseline, format.bpm),
      note: baselineLine(
        format,
        view.restingHeartRate,
        compared: (d) => restingVersusBaseline(format, d),
        missing: l10n.readinessNightMissing,
      ),
    ),
    ReadinessFactor.activityLoad => _load(format, view.activityLoad),
  };
}

FactorText _sleep(MetricFormat format, ReadinessView view) {
  final night = view.sleep.night;
  final score = view.sleep.scoreValue;
  final l10n = format.l10n;
  if (night == null || score == null) {
    return (value: null, baseline: null, note: l10n.readinessSleepMissing);
  }
  return (
    value: '$score',
    baseline: null,
    note: l10n.readinessSleepNote(
      format.duration(night.asleep),
      format.percent(night.efficiency * 100),
    ),
  );
}

FactorText _load(MetricFormat format, ActivityLoad? load) {
  final l10n = format.l10n;
  if (load == null) {
    return (value: null, baseline: null, note: l10n.readinessLoadMissing);
  }
  return (
    value: format.decimal(load.ratio, digits: 2),
    baseline: l10n.readinessLoadDetail(
      format.integer(load.acute),
      format.integer(load.chronic),
    ),
    note: l10n.readinessLoadNote,
  );
}

String? _maybe(double? value, String Function(double) show) =>
    value == null ? null : show(value);

String? _typical(
  MetricFormat format,
  BaselineResult baseline,
  String Function(double) show,
) => switch (baseline) {
  BaselineReady(:final typical) => format.l10n.readinessBaseline(show(typical)),
  BaselineBuilding() => null,
};
