import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';

const List<SleepPhase> hypnogramLanes = [
  SleepPhase.awake,
  SleepPhase.rem,
  SleepPhase.light,
  SleepPhase.deep,
];

const List<SleepPhase> stageSummaryOrder = [
  SleepPhase.light,
  SleepPhase.deep,
  SleepPhase.rem,
  SleepPhase.awake,
];

// A night that holds REM keeps its lane even when the ring is judged not to
// report it, so recorded time is never hidden.
bool showsRem(SleepNight night, {required bool remMeasured}) =>
    remMeasured || night.timeIn(SleepPhase.rem) > Duration.zero;

List<SleepPhase> phasesShown(List<SleepPhase> order, {required bool rem}) => [
  for (final phase in order)
    if (rem || phase != SleepPhase.rem) phase,
];

extension SleepPhaseLabels on SleepPhase {
  String label(MetricFormat format) => switch (this) {
    SleepPhase.awake => format.l10n.sleepStageAwake,
    SleepPhase.rem => format.l10n.sleepStageRem,
    SleepPhase.light => format.l10n.sleepStageLight,
    SleepPhase.deep => format.l10n.sleepStageDeep,
  };

  Color color(AppColors colors) => switch (this) {
    SleepPhase.awake => colors.sleepAwake,
    SleepPhase.rem => colors.sleepRem,
    SleepPhase.light => colors.sleepLight,
    SleepPhase.deep => colors.sleepDeep,
  };
}

extension SleepFactorLabels on SleepFactor {
  String label(MetricFormat format, Duration goal) => switch (this) {
    SleepFactor.duration => format.l10n.sleepFactorDuration(
      format.duration(goal),
    ),
    SleepFactor.efficiency => format.l10n.sleepFactorEfficiency,
    SleepFactor.latency => format.l10n.sleepFactorLatency,
    SleepFactor.deep => format.l10n.sleepFactorDeep,
    SleepFactor.rem => format.l10n.sleepFactorRem,
  };

  String value(MetricFormat format, double value) => switch (this) {
    SleepFactor.duration || SleepFactor.latency => format.duration(
      Duration(seconds: (value * 60).round()),
    ),
    SleepFactor.efficiency ||
    SleepFactor.deep ||
    SleepFactor.rem => format.percent(value),
  };
}

String nightRange(MetricFormat format, SleepNight night) =>
    format.l10n.metricTimeRange(
      format.clock(night.start, night.spans.first.utcOffset),
      format.clock(night.end, night.spans.last.utcOffset),
    );
