import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ring/application/sync_alerts.dart';
import 'package:open_ring/features/today/application/today_view.dart';
import 'package:open_ring/features/widgets/domain/widget_snapshot.dart';
import 'package:open_ring/features/widgets/presentation/widget_labels.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class WidgetPreviewFrame extends StatelessWidget {
  const new({required this.label, required this.child, this.colors, super.key});

  final String label;
  final Widget child;
  final AppColors? colors;

  @override
  Widget build(BuildContext context) {
    final palette = colors ?? AppColors.of(context);
    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border.all(color: palette.surfaceBorder),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: child,
          ),
        ),
      ),
    );
  }
}

class WidgetPreviewBar extends StatelessWidget {
  const new({required this.value, required this.color, this.track, super.key});

  final double value;
  final Color color;
  final Color? track;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: LinearProgressIndicator(
      value: value,
      minHeight: 5,
      color: color,
      backgroundColor: track ?? AppColors.of(context).track,
    ),
  );
}

class WidgetStatusLine extends StatelessWidget {
  const new({required this.status, this.colors, super.key});

  final WidgetStatus status;
  final AppColors? colors;

  @override
  Widget build(BuildContext context) {
    final palette = colors ?? AppColors.of(context);
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: status.stale ? palette.stress : palette.textLabel,
      fontWeight: status.stale ? FontWeight.w600 : FontWeight.w400,
    );
    if (!status.stale) return Text(status.text, style: style);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.warning_amber_rounded, size: 13, color: palette.stress),
        const SizedBox(width: 4),
        Flexible(child: Text(status.text, style: style)),
      ],
    );
  }
}

String _show(int? value, MetricFormat format) =>
    value == null ? format.l10n.widgetNoValue : format.integer(value);

Color _ringBarColor(
  AppColors colors, {
  required int? percent,
  required bool charging,
  required bool stale,
}) {
  if (stale) return colors.textLabel;
  if (!charging && percent != null && percent <= lowBatteryPercent) {
    return colors.stress;
  }
  return colors.activity;
}

class ReadinessWidgetPreview extends StatelessWidget {
  const new({required this.snapshot, required this.now, super.key});

  static const previewKey = Key('readiness_widget_preview');

  final WidgetSnapshot? snapshot;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final data = snapshot;
    if (data == null || !data.paired) {
      return WidgetPreviewFrame(
        key: previewKey,
        label: '${l10n.widgetReadinessName}: ${l10n.todayNoRing}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReadinessHeader(l10n: l10n, colors: colors),
            const SizedBox(height: 10),
            Text(
              l10n.widgetUnpaired,
              style: textTheme.bodyMedium?.copyWith(color: colors.textLabel),
            ),
            const SizedBox(height: 10),
            WidgetStatusLine(status: (text: l10n.todayNoRing, stale: false)),
          ],
        ),
      );
    }
    final score = _show(data.readiness, format);
    final factors = <(String, String)>[
      (l10n.widgetRestingHr, _show(data.restingHeartRate, format)),
      (l10n.healthWriteHrv, _show(data.hrv, format)),
      (l10n.widgetMetricSleep, _show(data.sleepScore, format)),
    ];
    final pending = data.readiness == null;
    final progress = (data.readiness ?? 0) / 100;
    return WidgetPreviewFrame(
      key: previewKey,
      label:
          '${l10n.widgetReadinessName}: $score, '
          '${[for (final (name, value) in factors) '$name $value'].join(', ')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReadinessHeader(l10n: l10n, colors: colors),
          const SizedBox(height: 8),
          Text(
            score,
            style: numberStyle(
              textTheme.displaySmall,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          for (final (name, value) in factors)
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textLabel,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  value,
                  style: numberStyle(
                    textTheme.labelSmall,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          if (data.readiness != null) ...[
            const SizedBox(height: 8),
            WidgetPreviewBar(value: progress, color: colors.textPrimary),
          ],
          const SizedBox(height: 8),
          if (pending)
            Text(
              l10n.widgetReadinessPending,
              style: textTheme.labelSmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          WidgetStatusLine(status: widgetSyncStatus(format, data, now)),
        ],
      ),
    );
  }
}

class RingWidgetPreview extends StatelessWidget {
  const new({required this.snapshot, required this.now, super.key});

  static const previewKey = Key('ring_widget_preview');

  final WidgetSnapshot? snapshot;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final data = snapshot;
    final disconnected =
        data == null ||
        data.freshness == SyncFreshness.unpaired ||
        data.freshness == SyncFreshness.neverSynced;
    final percent = disconnected ? null : data.batteryPercent;
    final battery = percent == null
        ? l10n.widgetNoValue
        : format.percent(percent.toDouble());
    final status = ringPreviewStatus(format, data, now);
    final charging =
        !disconnected && data.batteryCharging == true && !status.stale;
    final barColor = _ringBarColor(
      colors,
      percent: percent,
      charging: charging,
      stale: status.stale,
    );
    return WidgetPreviewFrame(
      key: previewKey,
      label: '${l10n.widgetRingName}: $battery, ${status.text}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.widgetRingName,
                  style: textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (charging && percent != null) ...[
                Icon(Icons.bolt_rounded, size: 16, color: colors.activity),
                const SizedBox(width: 2),
              ],
              Text(
                battery,
                style: numberStyle(
                  textTheme.titleMedium,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          if (percent != null) ...[
            const SizedBox(height: 8),
            WidgetPreviewBar(
              value: (percent / 100).clamp(0, 1).toDouble(),
              color: barColor,
            ),
          ],
          const SizedBox(height: 8),
          WidgetStatusLine(status: status),
        ],
      ),
    );
  }
}

class WorkoutWidgetPreview extends StatelessWidget {
  const new({required this.snapshot, required this.now, super.key});

  static const previewKey = Key('workout_widget_preview');

  final WidgetSnapshot? snapshot;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final last = snapshot?.lastWorkout;
    final subtitle = last == null
        ? l10n.widgetWorkoutSubtitle
        : '${last.type.label(l10n)} · '
              '${format.clockOrDay(last.start, now)} · '
              '${format.duration(last.elapsed)}';
    return WidgetPreviewFrame(
      key: previewKey,
      label: '${l10n.widgetWorkoutName}: $subtitle',
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.activity,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(Icons.play_arrow_rounded, color: colors.background),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.widgetWorkoutName,
                  style: textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.textLabel,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.textLabel),
        ],
      ),
    );
  }
}

class _ReadinessHeader extends StatelessWidget {
  const new({required this.l10n, required this.colors});

  final AppLocalizations l10n;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l10n.widgetReadinessName,
          style: textTheme.titleSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          l10n.widgetSubEstimate,
          style: textTheme.labelSmall?.copyWith(color: colors.textLabel),
        ),
      ],
    );
  }
}
