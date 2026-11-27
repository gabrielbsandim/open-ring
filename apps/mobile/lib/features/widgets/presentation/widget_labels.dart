import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/open_score/application/day_score_view.dart';
import 'package:open_ring/features/ring/application/sync_alerts.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/today/application/today_view.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:open_ring/features/widgets/domain/widget_snapshot.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

typedef MetricText = ({String value, String detail, double? progress});

typedef WidgetDayScoreView = ({
  String value,
  String detail,
  String? messageTitle,
  String? messageDetail,
  List<double?>? pillarPoints,
  bool partial,
});

typedef WidgetStatus = ({String text, bool stale});

WidgetStatus widgetSyncStatus(
  MetricFormat format,
  WidgetSnapshot? snapshot,
  DateTime now,
) {
  final l10n = format.l10n;
  final data = snapshot;
  if (data == null) return (text: l10n.widgetNeverSynced, stale: false);
  final synced = data.syncedAt;
  return switch (data.freshness) {
    SyncFreshness.unpaired => (text: l10n.todayNoRing, stale: false),
    SyncFreshness.neverSynced => (text: l10n.widgetNeverSynced, stale: false),
    SyncFreshness.fresh => (
      text: l10n.widgetSynced(format.clockOrDay(synced!, now)),
      stale: false,
    ),
    SyncFreshness.stale => (
      text: l10n.widgetStale(format.clockOrDay(synced!, now)),
      stale: true,
    ),
  };
}

WidgetStatus ringPreviewStatus(
  MetricFormat format,
  WidgetSnapshot? snapshot,
  DateTime now,
) {
  final l10n = format.l10n;
  final data = snapshot;
  if (data == null ||
      data.freshness != SyncFreshness.fresh ||
      data.batteryPercent == null ||
      data.syncedAt == null) {
    return widgetSyncStatus(format, snapshot, now);
  }
  final time = format.clockOrDay(data.syncedAt!, now);
  if (data.batteryCharging == true) {
    return (text: l10n.widgetRingCharging(time), stale: false);
  }
  if (data.batteryPercent! <= lowBatteryPercent) {
    return (text: l10n.widgetRingLowBattery(time), stale: false);
  }
  return widgetSyncStatus(format, snapshot, now);
}

String dayScoreBandWord(AppLocalizations l10n, DayScoreBand band) =>
    switch (band) {
      DayScoreBand.great => l10n.dayScoreBandGreat,
      DayScoreBand.good => l10n.dayScoreBandGood,
      DayScoreBand.mixed => l10n.dayScoreBandMixed,
      DayScoreBand.low => l10n.dayScoreBandLow,
    };

String weightDirectionWord(
  AppLocalizations l10n,
  WidgetWeightDirection direction,
) => switch (direction) {
  WidgetWeightDirection.falling => l10n.bodyDirectionDown,
  WidgetWeightDirection.rising => l10n.bodyDirectionUp,
  WidgetWeightDirection.steady => l10n.bodyDirectionStable,
  WidgetWeightDirection.building => l10n.bodyDirectionNone,
};

WidgetDayScoreView describeDayScore(
  MetricFormat format,
  WidgetSnapshot? snapshot,
  DateTime now, {
  required bool stale,
}) {
  final l10n = format.l10n;
  final none = l10n.widgetNoValue;
  final day = snapshot?.dayScore;
  if (snapshot == null || !snapshot.paired || day == null) {
    return (
      value: none,
      detail: l10n.widgetReadinessPending,
      messageTitle: null,
      messageDetail: null,
      pillarPoints: null,
      partial: false,
    );
  }
  final bandText = day.band == null
      ? l10n.widgetSubEstimate
      : dayScoreBandWord(l10n, day.band!);
  switch (day.kind) {
    case WidgetDayScoreKind.firstDays:
      return (
        value: none,
        detail: '',
        messageTitle: l10n.dayScoreFirstTitle,
        messageDetail: l10n.widgetDayScoreFirstDaysDetail(
          format.integer(day.coverage),
        ),
        pillarPoints: null,
        partial: false,
      );
    case WidgetDayScoreKind.noScore:
      return (
        value: none,
        detail: '',
        messageTitle: l10n.dayScoreNoneTitle,
        messageDetail: switch (day.gap) {
          DayScoreGap.night || null => l10n.dayScoreNoneSleep,
          DayScoreGap.steps => l10n.dayScoreNoneSteps,
          DayScoreGap.coverage => l10n.widgetDayScoreNoneCoverage,
        },
        pillarPoints: null,
        partial: false,
      );
    case WidgetDayScoreKind.afterMidnight:
      return (
        value: day.score == null ? none : format.integer(day.score!),
        detail: '$bandText · ${l10n.widgetDayScoreYesterdayFinal}',
        messageTitle: null,
        messageDetail: null,
        pillarPoints: day.pillarPoints,
        partial: false,
      );
    case WidgetDayScoreKind.partial:
      return (
        value: day.score == null ? none : format.integer(day.score!),
        detail: '$bandText · ${l10n.dayScoreCoveragePartial(day.coverage)}',
        messageTitle: null,
        messageDetail: null,
        pillarPoints: day.pillarPoints,
        partial: true,
      );
    case WidgetDayScoreKind.full:
      final stamp = day.asOf ?? snapshot.syncedAt;
      final time = stamp == null ? none : format.clockOrDay(stamp, now);
      final atText = stale
          ? l10n.widgetDayScoreAsOf(time)
          : l10n.dayScoreSoFar(time);
      return (
        value: day.score == null ? none : format.integer(day.score!),
        detail: '$bandText · $atText',
        messageTitle: null,
        messageDetail: null,
        pillarPoints: day.pillarPoints,
        partial: false,
      );
  }
}

extension WidgetMetricLabels on WidgetMetric {
  String label(AppLocalizations l10n) => switch (this) {
    WidgetMetric.readiness => l10n.widgetMetricReadiness,
    WidgetMetric.sleep => l10n.widgetMetricSleep,
    WidgetMetric.steps => l10n.widgetMetricSteps,
    WidgetMetric.heartRate => l10n.widgetMetricHeartRate,
    WidgetMetric.spo2 => l10n.widgetMetricSpo2,
    WidgetMetric.stress => l10n.widgetMetricStress,
    WidgetMetric.battery => l10n.widgetMetricBattery,
    WidgetMetric.dayScore => l10n.dayScoreTitle,
    WidgetMetric.weight => l10n.profileWeight,
    WidgetMetric.energy => l10n.energyTitle,
    WidgetMetric.effort => l10n.effortTitle,
  };

  Color accent(AppColors colors) => switch (this) {
    WidgetMetric.readiness => colors.textPrimary,
    WidgetMetric.sleep => colors.sleep,
    WidgetMetric.steps => colors.activity,
    WidgetMetric.heartRate => colors.heart,
    WidgetMetric.spo2 => colors.oxygen,
    WidgetMetric.stress => colors.stress,
    WidgetMetric.battery => colors.textSecondary,
    WidgetMetric.dayScore => colors.textPrimary,
    WidgetMetric.weight => colors.textLabel,
    WidgetMetric.energy => colors.activity,
    WidgetMetric.effort => colors.textPrimary,
  };

  MetricText describe(
    MetricFormat format,
    WidgetSnapshot? snapshot, {
    UnitSystem units = UnitSystem.metric,
    DateTime? now,
    bool stale = false,
  }) {
    final l10n = format.l10n;
    final none = l10n.widgetNoValue;
    final disconnected = snapshot != null && !snapshot.paired && requiresRing;
    String show(int? value, String Function(int) text) =>
        disconnected || value == null ? none : text(value);
    return switch (this) {
      WidgetMetric.readiness => (
        value: show(snapshot?.readiness, (v) => '$v'),
        detail: l10n.widgetSubEstimate,
        progress: disconnected ? null : _share(snapshot?.readiness, 100),
      ),
      WidgetMetric.sleep => (
        value: show(
          snapshot?.sleepMinutes,
          (v) => format.duration(Duration(minutes: v)),
        ),
        detail: l10n.widgetSubSleepScore(
          show(snapshot?.sleepScore, (v) => '$v'),
        ),
        progress: null,
      ),
      WidgetMetric.steps => (
        value: show(snapshot?.steps, format.integer),
        detail: l10n.widgetSubStepsGoal(
          format.integer(snapshot?.stepGoal ?? 0),
        ),
        progress: disconnected
            ? null
            : _share(snapshot?.steps, snapshot?.stepGoal ?? 0),
      ),
      WidgetMetric.heartRate => (
        value: show(snapshot?.heartRateMean, format.integer),
        detail: l10n.widgetSubBpmAverage,
        progress: null,
      ),
      WidgetMetric.spo2 => (
        value: show(snapshot?.spo2, (v) => format.percent(v.toDouble())),
        detail: l10n.widgetSubAverage,
        progress: null,
      ),
      WidgetMetric.stress => (
        value: show(snapshot?.stress, format.integer),
        detail: l10n.widgetSubAverage,
        progress: null,
      ),
      WidgetMetric.battery => (
        value: show(
          snapshot?.batteryPercent,
          (v) => format.percent(v.toDouble()),
        ),
        detail: l10n.widgetSubBattery,
        progress: disconnected ? null : _share(snapshot?.batteryPercent, 100),
      ),
      WidgetMetric.dayScore => _describeDayScoreMetric(
        format,
        snapshot,
        now ?? DateTime.now(),
        stale: stale,
      ),
      WidgetMetric.weight => _describeWeightMetric(format, snapshot, units),
      WidgetMetric.energy => _describeEnergyMetric(format, snapshot),
      WidgetMetric.effort => _describeEffortMetric(format, snapshot),
    };
  }
}

MetricText _describeDayScoreMetric(
  MetricFormat format,
  WidgetSnapshot? snapshot,
  DateTime now, {
  required bool stale,
}) {
  final view = describeDayScore(format, snapshot, now, stale: stale);
  return (
    value: view.value,
    detail: view.messageTitle ?? view.detail,
    progress: snapshot?.paired == true
        ? _share(snapshot?.dayScore?.score, 100)
        : null,
  );
}

MetricText _describeWeightMetric(
  MetricFormat format,
  WidgetSnapshot? snapshot,
  UnitSystem units,
) {
  final l10n = format.l10n;
  final w = snapshot?.weight;
  if (w == null) {
    return (
      value: l10n.widgetNoValue,
      detail: l10n.bodyDirectionCaption,
      progress: null,
    );
  }
  final value = snapshot!.hideNumbers || w.trendKilograms == null
      ? weightDirectionWord(l10n, w.direction)
      : UnitFormat(format, units).bodyWeight(w.trendKilograms!);
  return (value: value, detail: l10n.bodyDirectionCaption, progress: null);
}

MetricText _describeEnergyMetric(
  MetricFormat format,
  WidgetSnapshot? snapshot,
) {
  final l10n = format.l10n;
  final energy = snapshot != null && !snapshot.paired ? null : snapshot?.energy;
  final value = energy == null
      ? l10n.widgetNoValue
      : l10n.energyRowRange(
          format.integer(energy.lowKcal),
          format.integer(energy.highKcal),
        );
  return (value: value, detail: l10n.energyRowUnit, progress: null);
}

MetricText _describeEffortMetric(
  MetricFormat format,
  WidgetSnapshot? snapshot,
) {
  final l10n = format.l10n;
  final none = l10n.widgetNoValue;
  final effort = snapshot != null && !snapshot.paired ? null : snapshot?.effort;
  if (effort == null) {
    return (
      value: none,
      detail: l10n.widgetEffortSummary(
        format.integer(effortWeekPoints),
        none,
        format.integer(effortWeekStrengthDays),
      ),
      progress: null,
    );
  }
  return (
    value: format.integer(effort.points),
    detail: l10n.widgetEffortSummary(
      format.integer(effort.targetPoints),
      format.integer(effort.strengthDays),
      format.integer(effort.strengthTarget),
    ),
    progress: _share(effort.points, effort.targetPoints),
  );
}

extension WidgetThemeLabels on WidgetTheme {
  String label(AppLocalizations l10n) => switch (this) {
    WidgetTheme.app => l10n.widgetThemeApp,
    WidgetTheme.dark => l10n.widgetThemeDark,
    WidgetTheme.light => l10n.widgetThemeLight,
  };
}

double? _share(int? value, int total) {
  if (value == null || total <= 0) return null;
  return (value / total).clamp(0, 1).toDouble();
}
