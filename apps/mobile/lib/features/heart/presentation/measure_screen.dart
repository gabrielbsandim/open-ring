import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/heart/application/measure_controller.dart';
import 'package:open_ring/features/heart/application/measure_state.dart';
import 'package:open_ring/features/heart/presentation/measure_labels.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:ring_driver/ring_driver.dart';

abstract final class MeasureKeys {
  static const dial = Key('measure_dial');
  static const status = Key('measure_status');
  static const start = Key('measure_start');
  static const cancel = Key('measure_cancel');
  static const result = Key('measure_result');
  static const failure = Key('measure_failure');
  static const cancelled = Key('measure_cancelled');
  static const openRing = Key('measure_open_ring');

  static Key kind(LiveKind kind) => Key('measure_kind_${kind.name}');
}

class MeasureScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final state = ref.watch(measureProvider);
    final controller = ref.read(measureProvider.notifier);
    final colors = AppColors.of(context);
    return AppPage(
      title: l10n.measureTitle,
      children: [
        if (!state.running)
          _KindPicker(selected: state.kind, onSelected: controller.choose),
        if (state.running)
          Text(
            state.kind.measuringLabel(l10n),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colors.textSecondary),
          ),
        const SizedBox(height: 20),
        _MeasureDial(state: state),
        const SizedBox(height: 12),
        Semantics(
          key: MeasureKeys.status,
          liveRegion: true,
          child: Text(
            state.statusLabel(format),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colors.textSecondary),
          ),
        ),
        if (state.running)
          CaptionText(
            l10n.measureSecondsLeft(state.remaining.inSeconds),
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 20),
        if (state.cancelled) ...[
          CaptionText(
            key: MeasureKeys.cancelled,
            l10n.measureCancelled,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: cardGap),
        ],
        if (state.failure case final failure?) ...[
          _FailureCard(failure: failure, window: state.window),
          const SizedBox(height: cardGap),
        ],
        if (state.result case final result?) ...[
          _ResultCard(result: result),
          const SizedBox(height: cardGap),
        ],
        if (state.phase != MeasurePhase.done) ...[
          _TipCard(kind: state.kind, window: state.window),
          const SizedBox(height: 20),
        ],
        if (!state.running)
          ActionButton(
            key: MeasureKeys.start,
            label: state.phase == MeasurePhase.done
                ? l10n.measureAgain
                : l10n.measureStart,
            onPressed: () => unawaited(controller.start()),
          ),
        if (state.running)
          SecondaryButton(
            key: MeasureKeys.cancel,
            label: l10n.measureCancel,
            onPressed: () => unawaited(controller.cancel()),
          ),
        const SizedBox(height: 16),
        EstimateNote(lead: l10n.measureNote),
      ],
    );
  }
}

class _KindPicker extends StatelessWidget {
  const new({required this.selected, required this.onSelected});

  final LiveKind selected;
  final ValueChanged<LiveKind> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final kind in LiveKind.values)
          ChoiceChip(
            key: MeasureKeys.kind(kind),
            label: Text(kind.shortLabel(l10n)),
            selected: kind == selected,
            showCheckmark: false,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            selectedColor: colors.textPrimary,
            backgroundColor: colors.surface,
            side: BorderSide(
              color: kind == selected
                  ? colors.textPrimary
                  : colors.surfaceBorder,
            ),
            labelStyle: TextStyle(
              color: kind == selected
                  ? colors.background
                  : colors.textSecondary,
            ),
            onSelected: (_) => onSelected(kind),
          ),
      ],
    );
  }
}

class _MeasureDial extends StatelessWidget {
  const new({required this.state});

  final MeasureState state;

  static const _diameter = 200.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final value = state.shownValue;
    final accent = state.kind.accent(colors);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(
          _diameter * math.max(1, scale),
          constraints.maxWidth,
        );
        return Center(
          child: Semantics(
            key: MeasureKeys.dial,
            container: true,
            label: value == null
                ? state.statusLabel(format)
                : state.kind.valueLabel(format, value),
            excludeSemantics: true,
            child: SizedBox.square(
              dimension: size,
              child: CustomPaint(
                painter: MeasureDialPainter(
                  progress: state.progress,
                  color: accent,
                  track: colors.track,
                  fill: colors.surface,
                  stroke: size / 20,
                ),
                child: Center(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    children: [
                      Text(
                        value == null
                            ? l10n.measureNoValue
                            : format.integer(value),
                        style: numberStyle(
                          theme.textTheme.displayMedium,
                          color: value == null ? colors.textLabel : accent,
                        ),
                      ),
                      CaptionText(state.kind.unit(l10n)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class MeasureDialPainter extends CustomPainter {
  const new({
    required this.progress,
    required this.color,
    required this.track,
    required this.fill,
    required this.stroke,
  });

  final double progress;
  final Color color;
  final Color track;
  final Color fill;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawOval(rect, Paint()..color = fill);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0, 1),
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(MeasureDialPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.track != track ||
      old.fill != fill ||
      old.stroke != stroke;
}

class _TipCard extends StatelessWidget {
  const new({required this.kind, required this.window});

  final LiveKind kind;
  final Duration window;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    return MetricCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.back_hand_rounded, size: 24, color: colors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.measureTipTitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                CaptionText(kind.tip(l10n, window)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const new({required this.result});

  final MeasureResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final reading = result.reading;
    final at = reading.at;
    return Semantics(
      liveRegion: true,
      child: MetricCard(
        key: MeasureKeys.result,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                reading.kind.resultLabel(format, reading.value),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            CaptionText(
              l10n.measureResultAt(format.clock(at, at.timeZoneOffset)),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  result.saved
                      ? Icons.check_circle_rounded
                      : Icons.error_outline_rounded,
                  size: 18,
                  color: result.saved ? colors.activity : colors.stress,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BodyText(
                    result.saved
                        ? l10n.measureSaved(healthPlatformName())
                        : l10n.measureNotSaved,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  const new({required this.failure, required this.window});

  final MeasureFailure failure;
  final Duration window;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    return Semantics(
      liveRegion: true,
      child: EmptyStateCard(
        key: MeasureKeys.failure,
        icon: Icons.error_outline_rounded,
        accent: colors.heart,
        title: l10n.measureFailedTitle,
        message: failure.message(l10n, window),
        actionLabel: failure == MeasureFailure.noRing
            ? l10n.metricOpenRing
            : null,
        actionKey: MeasureKeys.openRing,
        onAction: () => context.go(AppTab.ring.path),
      ),
    );
  }
}
