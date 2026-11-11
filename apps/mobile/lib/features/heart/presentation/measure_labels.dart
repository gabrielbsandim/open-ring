import 'package:flutter/widgets.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/heart/application/measure_state.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';
import 'package:ring_driver/ring_driver.dart';

extension LiveKindLabels on LiveKind {
  String shortLabel(AppLocalizations l10n) => switch (this) {
    LiveKind.heartRate => l10n.heartMetricHeartRate,
    LiveKind.spo2 => l10n.heartMetricSpo2,
  };

  String measuringLabel(AppLocalizations l10n) => switch (this) {
    LiveKind.heartRate => l10n.measuringHeartRate,
    LiveKind.spo2 => l10n.measuringSpo2,
  };

  String unit(AppLocalizations l10n) => switch (this) {
    LiveKind.heartRate => l10n.measureUnitBpm,
    LiveKind.spo2 => l10n.measureUnitPercent,
  };

  String valueLabel(MetricFormat format, int value) => switch (this) {
    LiveKind.heartRate => format.bpm(value.toDouble()),
    LiveKind.spo2 => format.percent(value.toDouble()),
  };

  String resultLabel(MetricFormat format, int value) => switch (this) {
    LiveKind.heartRate => format.l10n.measureResultHeartRate(
      valueLabel(format, value),
    ),
    LiveKind.spo2 => format.l10n.measureResultSpo2(valueLabel(format, value)),
  };

  String tip(AppLocalizations l10n, Duration window) => switch (this) {
    LiveKind.heartRate => l10n.measureTipHeartRate(window.inSeconds),
    LiveKind.spo2 => l10n.measureTipSpo2,
  };

  Color accent(AppColors colors) => switch (this) {
    LiveKind.heartRate => colors.heart,
    LiveKind.spo2 => colors.oxygen,
  };
}

extension MeasureStateLabels on MeasureState {
  String statusLabel(MetricFormat format) {
    final l10n = format.l10n;
    return switch (phase) {
      MeasurePhase.idle => l10n.measureStatusIdle,
      MeasurePhase.connecting => l10n.measureStatusConnecting,
      MeasurePhase.searching => l10n.measureStatusSearching,
      MeasurePhase.reading => l10n.measureStatusReading,
      MeasurePhase.done => l10n.measureStatusDone,
      MeasurePhase.failed => l10n.measureStatusFailed,
    };
  }
}

extension MeasureFailureLabels on MeasureFailure {
  String message(AppLocalizations l10n, Duration window) => switch (this) {
    MeasureFailure.noRing => l10n.measureFailedNoRing,
    MeasureFailure.busy => l10n.measureFailedBusy,
    MeasureFailure.unreachable => l10n.measureFailedUnreachable,
    MeasureFailure.noReading => l10n.measureFailedNoReading(window.inSeconds),
  };
}
