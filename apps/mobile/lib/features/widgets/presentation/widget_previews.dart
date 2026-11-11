import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ring/application/sync_alerts.dart';
import 'package:open_ring/features/widgets/domain/widget_snapshot.dart';
import 'package:open_ring/features/widgets/presentation/widget_labels.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';

class _PreviewFrame extends StatelessWidget {
  const new({required this.label, required this.child, super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.surfaceBorder),
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

class _PreviewBar extends StatelessWidget {
  const new({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: LinearProgressIndicator(
      value: value,
      minHeight: 5,
      color: color,
      backgroundColor: AppColors.of(context).track,
    ),
  );
}

class _StatusLine extends StatelessWidget {
  const new({required this.status});

  final WidgetStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Text(
      status.text,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: status.stale ? colors.stress : colors.textLabel),
    );
  }
}

WidgetStatus _previewStatus(
  MetricFormat format,
  WidgetSnapshot? data,
  DateTime now,
) {
  if (data == null) return (text: format.l10n.widgetNoData, stale: false);
  if (!data.paired) return (text: format.l10n.widgetUnpaired, stale: false);
  return widgetSyncStatus(format, data, now);
}

String _show(int? value, MetricFormat format) =>
    value == null ? format.l10n.widgetNoValue : format.integer(value);

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
    final score = _show(data?.readiness, format);
    final factors = <(String, String)>[
      (l10n.widgetRestingHr, _show(data?.restingHeartRate, format)),
      (l10n.healthWriteHrv, _show(data?.hrv, format)),
      (l10n.widgetMetricSleep, _show(data?.sleepScore, format)),
    ];
    final pending = data != null && data.paired && data.readiness == null;
    final progress = (data?.readiness ?? 0) / 100;
    return _PreviewFrame(
      key: previewKey,
      label:
          '${l10n.widgetReadinessName}: $score, '
          '${[for (final (name, value) in factors) '$name $value'].join(', ')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
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
          ),
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
          if (data?.readiness != null) ...[
            const SizedBox(height: 8),
            _PreviewBar(value: progress, color: colors.textPrimary),
          ],
          const SizedBox(height: 8),
          if (pending)
            Text(
              l10n.widgetReadinessPending,
              style: textTheme.labelSmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          _StatusLine(status: _previewStatus(format, data, now)),
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
    final percent = data?.batteryPercent;
    final battery = percent == null
        ? l10n.widgetNoValue
        : format.percent(percent.toDouble());
    final status = _previewStatus(format, data, now);
    return _PreviewFrame(
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
            _PreviewBar(
              value: (percent / 100).clamp(0, 1).toDouble(),
              color: percent <= lowBatteryPercent
                  ? colors.stress
                  : colors.activity,
            ),
          ],
          const SizedBox(height: 8),
          _StatusLine(status: status),
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
    return _PreviewFrame(
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
