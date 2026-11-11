import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/today/application/today_view.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:open_ring/features/widgets/domain/widget_snapshot.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

typedef MetricText = ({String value, String detail, double? progress});

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
    SyncFreshness.unpaired => (text: l10n.widgetNeverSynced, stale: false),
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

extension WidgetMetricLabels on WidgetMetric {
  String label(AppLocalizations l10n) => switch (this) {
    WidgetMetric.readiness => l10n.widgetMetricReadiness,
    WidgetMetric.sleep => l10n.widgetMetricSleep,
    WidgetMetric.steps => l10n.widgetMetricSteps,
    WidgetMetric.heartRate => l10n.widgetMetricHeartRate,
    WidgetMetric.spo2 => l10n.widgetMetricSpo2,
    WidgetMetric.stress => l10n.widgetMetricStress,
    WidgetMetric.battery => l10n.widgetMetricBattery,
  };

  Color accent(AppColors colors) => switch (this) {
    WidgetMetric.readiness => colors.textPrimary,
    WidgetMetric.sleep => colors.sleep,
    WidgetMetric.steps => colors.activity,
    WidgetMetric.heartRate => colors.heart,
    WidgetMetric.spo2 => colors.oxygen,
    WidgetMetric.stress => colors.stress,
    WidgetMetric.battery => colors.textSecondary,
  };

  MetricText describe(MetricFormat format, WidgetSnapshot? snapshot) {
    final l10n = format.l10n;
    final none = l10n.widgetNoValue;
    String show(int? value, String Function(int) text) =>
        value == null ? none : text(value);
    return switch (this) {
      WidgetMetric.readiness => (
        value: show(snapshot?.readiness, (v) => '$v'),
        detail: l10n.widgetSubEstimate,
        progress: _share(snapshot?.readiness, 100),
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
        progress: _share(snapshot?.steps, snapshot?.stepGoal ?? 0),
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
        progress: _share(snapshot?.batteryPercent, 100),
      ),
    };
  }
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
