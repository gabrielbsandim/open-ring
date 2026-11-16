import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/energy/presentation/energy_parts.dart';

abstract final class EnergyThroughKeys {
  static const card = Key('energy_through');
  static const chart = Key('energy_through_chart');
  static const by = Key('energy_through_by');
  static const range = Key('energy_through_range');
  static const parts = Key('energy_through_parts');
}

const energyChartGridStep = 1000;
const energyChartMaxLines = 4;
const _axisHours = [0, 6, 12, 18, 24];
const _chartHeight = 176.0;

/// The top of the vertical axis: the first grid step above the upper end of
/// the margin at the last point.
int energyChartTop(EnergyCurve curve) {
  final peak = curve.points.last.day.total * (1 + energyDayMargin);
  return math.max(1, (peak / energyChartGridStep).ceil()) * energyChartGridStep;
}

List<int> energyChartMarks(int top) {
  var step = energyChartGridStep;
  while (top ~/ step > energyChartMaxLines) {
    step *= 2;
  }
  return [for (var mark = step; mark <= top; mark += step) mark];
}

/// The point closest to [fraction] of the day, from 0 at the start to 1 at
/// the end.
int energyPointAt(EnergyCurve curve, double fraction) {
  final span = curve.to.difference(curve.from).inMicroseconds;
  final target = curve.from.add(
    Duration(microseconds: (span * fraction.clamp(0, 1)).round()),
  );
  return energyPointNear(curve, target);
}

int energyPointNear(EnergyCurve curve, DateTime target) {
  var best = 0;
  for (var i = 1; i < curve.points.length; i++) {
    final here = curve.points[i].at.difference(target).abs();
    final kept = curve.points[best].at.difference(target).abs();
    if (here <= kept) best = i;
  }
  return best;
}

class EnergyThroughDay extends StatefulWidget {
  const new({required this.curve, required this.utcOffset, super.key});

  final EnergyCurve curve;
  final Duration utcOffset;

  @override
  State<EnergyThroughDay> createState() => _EnergyThroughDayState();
}

class _EnergyThroughDayState extends State<EnergyThroughDay> {
  DateTime? _picked;

  int get _last => widget.curve.points.length - 1;

  int get _index {
    final picked = _picked;
    return picked == null ? _last : energyPointNear(widget.curve, picked);
  }

  // The newest point is stored as no pick, so it follows the clock when the
  // day is computed again.
  void _select(int index) {
    final bounded = index.clamp(0, _last);
    setState(() {
      _picked = bounded == _last ? null : widget.curve.points[bounded].at;
    });
  }

  String _clock(MetricFormat format, DateTime at) =>
      format.clock(at, widget.utcOffset);

  String _rangeText(MetricFormat format, EnergyRange range) {
    if (range.low < energyRowFloor) return format.l10n.energyRowStarting;
    return format.l10n.energyKcal(
      format.l10n.energyRowRange(
        format.integer(range.low),
        format.integer(range.high),
      ),
    );
  }

  String _by(MetricFormat format, int index) {
    final time = _clock(format, widget.curve.points[index].at);
    return index == _last
        ? format.l10n.energyThroughByNow(time)
        : format.l10n.energyThroughBy(time);
  }

  String? _spoken(MetricFormat format, int index) {
    if (index < 0 || index > _last) return null;
    final range = _rangeText(format, widget.curve.points[index].day.range);
    return '${_by(format, index)}, $range';
  }

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    final theme = Theme.of(context).textTheme;
    final curve = widget.curve;
    final index = _index;
    final point = curve.points[index];
    final by = _by(format, index);
    final range = _rangeText(format, point.day.range);
    final top = energyChartTop(curve);
    final band = colors.textLabel.withValues(alpha: 0.28);
    return MetricCard(
      key: EnergyThroughKeys.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.energyThroughTitle,
              style: theme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 6),
          BodyText(l10n.energyThroughBody),
          const SizedBox(height: 12),
          Semantics(
            container: true,
            label: l10n.energyThroughSemantics,
            value: _spoken(format, index),
            increasedValue: _spoken(format, index + 1),
            decreasedValue: _spoken(format, index - 1),
            onIncrease: index < _last ? () => _select(index + 1) : null,
            onDecrease: index > 0 ? () => _select(index - 1) : null,
            child: LayoutBuilder(
              builder: (context, box) => GestureDetector(
                key: EnergyThroughKeys.chart,
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _select(
                  energyPointAt(
                    curve,
                    _ThroughPainter.fractionAt(
                      details.localPosition.dx,
                      box.maxWidth,
                    ),
                  ),
                ),
                child: CustomPaint(
                  size: Size(box.maxWidth, _chartHeight),
                  painter: _ThroughPainter(
                    curve: curve,
                    selected: index,
                    top: top,
                    marks: [
                      for (final mark in energyChartMarks(top))
                        (value: mark, label: format.integer(mark)),
                    ],
                    parts: [
                      for (final part in EnergyPart.values)
                        energyPartColor(colors, part),
                    ],
                    band: band,
                    low: colors.surface,
                    grid: colors.surfaceBorder,
                    cursor: colors.textPrimary,
                    surface: colors.surface,
                    label:
                        theme.labelSmall?.copyWith(color: colors.textLabel) ??
                        const TextStyle(),
                    direction: Directionality.of(context),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(
              left: _ThroughPainter.left,
              right: _ThroughPainter.right,
            ),
            child: TimeAxis(
              labels: [
                for (final hour in _axisHours)
                  _clock(format, curve.from.add(Duration(hours: hour))),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ExcludeSemantics(
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                for (final part in EnergyPart.values)
                  _Legend(
                    label: energyPartLabel(l10n, part),
                    color: energyPartColor(colors, part),
                  ),
                _Legend(label: l10n.energyLegendRange, color: band),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CaptionText(by, key: EnergyThroughKeys.by),
          const SizedBox(height: 2),
          Text(
            range,
            key: EnergyThroughKeys.range,
            style: numberStyle(theme.titleMedium),
          ),
          const SizedBox(height: 2),
          CaptionText(
            l10n.energyThroughParts(
              format.integer(energyPartShown(point.day.base)),
              format.integer(energyPartShown(point.day.steps)),
              format.integer(energyPartShown(point.day.workouts)),
            ),
            key: EnergyThroughKeys.parts,
          ),
          const SizedBox(height: 10),
          CaptionText(l10n.energyThroughNote),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const new({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
          child: const SizedBox.square(dimension: 10),
        ),
        const SizedBox(width: 6),
        Flexible(child: CaptionText(label)),
      ],
    );
  }
}

typedef _Mark = ({int value, String label});

class _ThroughPainter extends CustomPainter {
  const new({
    required this.curve,
    required this.selected,
    required this.top,
    required this.marks,
    required this.parts,
    required this.band,
    required this.low,
    required this.grid,
    required this.cursor,
    required this.surface,
    required this.label,
    required this.direction,
  });

  final EnergyCurve curve;
  final int selected;
  final int top;
  final List<_Mark> marks;
  final List<Color> parts;
  final Color band;
  final Color low;
  final Color grid;
  final Color cursor;
  final Color surface;
  final TextStyle label;
  final TextDirection direction;

  static const left = 40.0;
  static const right = 8.0;
  static const _top = 8.0;
  static const _bottom = 4.0;

  static double fractionAt(double dx, double width) =>
      ((dx - left) / (width - left - right)).clamp(0, 1);

  @override
  void paint(Canvas canvas, Size size) {
    final plotWidth = size.width - left - right;
    final plotHeight = size.height - _top - _bottom;
    final span = curve.to.difference(curve.from).inMicroseconds;
    double x(DateTime at) =>
        left + at.difference(curve.from).inMicroseconds / span * plotWidth;
    double y(num value) => _top + (1 - value.clamp(0, top) / top) * plotHeight;

    final rule = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final mark in marks) {
      canvas.drawLine(
        Offset(left, y(mark.value)),
        Offset(size.width - right, y(mark.value)),
        rule,
      );
      final text = TextPainter(
        text: TextSpan(text: mark.label, style: label),
        textDirection: direction,
      )..layout();
      text
        ..paint(
          canvas,
          Offset(left - 6 - text.width, y(mark.value) - text.height / 2),
        )
        ..dispose();
    }

    final points = curve.points;
    final layers = <double Function(EnergyDayEstimate)>[
      (_) => 0,
      (day) => day.base,
      (day) => day.base + day.steps,
      (day) => day.total,
      (day) => day.total * (1 + energyDayMargin),
    ];
    Path between(int lower, int upper) {
      final path = Path()
        ..moveTo(x(points.first.at), y(layers[upper](points.first.day)));
      for (final point in points.skip(1)) {
        path.lineTo(x(point.at), y(layers[upper](point.day)));
      }
      for (final point in points.reversed) {
        path.lineTo(x(point.at), y(layers[lower](point.day)));
      }
      return path..close();
    }

    canvas.drawPath(between(3, 4), Paint()..color = band);
    for (var part = 0; part < parts.length; part++) {
      canvas.drawPath(between(part, part + 1), Paint()..color = parts[part]);
    }
    final under = Path()
      ..moveTo(
        x(points.first.at),
        y(points.first.day.total * (1 - energyDayMargin)),
      );
    for (final point in points.skip(1)) {
      under.lineTo(x(point.at), y(point.day.total * (1 - energyDayMargin)));
    }
    canvas.drawPath(
      under,
      Paint()
        ..color = low
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final chosen = points[selected];
    final at = Offset(x(chosen.at), y(chosen.day.total));
    canvas
      ..drawLine(
        Offset(at.dx, _top),
        Offset(at.dx, size.height - _bottom),
        Paint()
          ..color = cursor
          ..strokeWidth = 1,
      )
      ..drawCircle(at, 5.5, Paint()..color = surface)
      ..drawCircle(at, 4, Paint()..color = cursor);
  }

  @override
  bool shouldRepaint(_ThroughPainter old) =>
      old.curve != curve ||
      old.selected != selected ||
      old.top != top ||
      old.band != band ||
      old.cursor != cursor ||
      old.label != label;
}
