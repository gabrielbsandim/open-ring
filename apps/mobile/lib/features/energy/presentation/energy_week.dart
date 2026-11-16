import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/energy/presentation/energy_parts.dart';
import 'package:open_ring/features/energy/presentation/energy_through_day.dart';

abstract final class EnergyWeekKeys {
  static const card = Key('energy_week');
  static const chart = Key('energy_week_chart');
  static const day = Key('energy_week_day');
  static const range = Key('energy_week_range');
  static const parts = Key('energy_week_parts');
  static const usual = Key('energy_week_usual');
}

const _chartHeight = 150.0;

/// The top of the vertical axis: the first grid step above the highest range.
int energyWeekTop(List<EnergyWeekDay> days) {
  final peak = days.fold<int>(
    0,
    (peak, entry) => math.max(peak, entry.day?.range.high ?? 0),
  );
  return math.max(1, (peak / energyChartGridStep).ceil()) * energyChartGridStep;
}

/// The mean of the past days on record, without today, which is not over.
double? energyWeekUsual(List<EnergyWeekDay> days) =>
    energyUsual([for (final entry in days.take(days.length - 1)) ?entry.day]);

class EnergyWeek extends StatefulWidget {
  const new({required this.days, required this.asOf, super.key});

  final List<EnergyWeekDay> days;
  final DateTime asOf;

  @override
  State<EnergyWeek> createState() => _EnergyWeekState();
}

class _EnergyWeekState extends State<EnergyWeek> {
  LocalDate? _picked;

  int get _last => widget.days.length - 1;

  // Today is stored as no pick, so it stays on today after midnight.
  int get _index {
    final at = widget.days.indexWhere((entry) => entry.date == _picked);
    return at < 0 ? _last : at;
  }

  void _select(int index) {
    final bounded = index.clamp(0, _last);
    setState(() {
      _picked = bounded == _last ? null : widget.days[bounded].date;
    });
  }

  String _dayText(MetricFormat format, int index) {
    if (index < _last) return format.date(widget.days[index].date);
    final asOf = widget.asOf;
    final clock = format.clock(asOf, asOf.timeZoneOffset);
    return '${format.l10n.tabToday}, $clock';
  }

  String _rangeText(MetricFormat format, EnergyDayEstimate? day) {
    final l10n = format.l10n;
    if (day == null) return l10n.energyWeekNoData;
    return _kcal(format, day.range);
  }

  String _kcal(MetricFormat format, EnergyRange range) {
    if (range.low < energyRowFloor) return format.l10n.energyRowStarting;
    return format.l10n.energyKcal(
      format.l10n.energyRowRange(
        format.integer(range.low),
        format.integer(range.high),
      ),
    );
  }

  String? _spoken(MetricFormat format, int index) {
    if (index < 0 || index > _last) return null;
    final range = _rangeText(format, widget.days[index].day);
    return '${_dayText(format, index)}, $range';
  }

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    final theme = Theme.of(context).textTheme;
    final days = widget.days;
    final index = _index;
    final day = days[index].day;
    final usual = energyWeekUsual(days);
    final top = energyWeekTop(days);
    return MetricCard(
      key: EnergyWeekKeys.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.energyWeekTitle,
              style: theme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 6),
          BodyText(l10n.energyWeekBody),
          const SizedBox(height: 12),
          Semantics(
            container: true,
            label: l10n.energyWeekSemantics,
            value: _spoken(format, index),
            increasedValue: _spoken(format, index + 1),
            decreasedValue: _spoken(format, index - 1),
            onIncrease: index < _last ? () => _select(index + 1) : null,
            onDecrease: index > 0 ? () => _select(index - 1) : null,
            child: LayoutBuilder(
              builder: (context, box) => GestureDetector(
                key: EnergyWeekKeys.chart,
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _select(
                  _WeekPainter.indexAt(
                    details.localPosition.dx,
                    box.maxWidth,
                    days.length,
                  ),
                ),
                child: CustomPaint(
                  size: Size(box.maxWidth, _chartHeight),
                  painter: _WeekPainter(
                    days: [for (final entry in days) entry.day],
                    selected: index,
                    top: top,
                    marks: [
                      for (final mark in energyChartMarks(top))
                        (value: mark, label: format.integer(mark)),
                    ],
                    bar: colors.textLabel,
                    today: colors.textPrimary,
                    surface: colors.surface,
                    highlight: colors.surfaceInner,
                    grid: colors.surfaceBorder,
                    label:
                        theme.labelSmall?.copyWith(color: colors.textLabel) ??
                        const TextStyle(),
                    direction: Directionality.of(context),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(
                left: _WeekPainter.left,
                right: _WeekPainter.right,
              ),
              child: Row(
                children: [
                  for (final entry in days)
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: CaptionText(format.weekday(entry.date)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          CaptionText(_dayText(format, index), key: EnergyWeekKeys.day),
          const SizedBox(height: 2),
          Text(
            _rangeText(format, day),
            key: EnergyWeekKeys.range,
            style: day == null
                ? theme.bodyMedium?.copyWith(color: colors.textSecondary)
                : numberStyle(theme.titleMedium),
          ),
          if (day != null) ...[
            const SizedBox(height: 2),
            CaptionText(
              l10n.energyThroughParts(
                format.integer(energyPartShown(day.base)),
                format.integer(energyPartShown(day.steps)),
                format.integer(energyPartShown(day.workouts)),
              ),
              key: EnergyWeekKeys.parts,
            ),
          ],
          if (usual != null) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 2,
              children: [
                BodyText(l10n.energyWeekUsual),
                BodyText(
                  _kcal(format, energyRange(usual, energyDayMargin)),
                  key: EnergyWeekKeys.usual,
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          CaptionText(l10n.energyWeekNote),
        ],
      ),
    );
  }
}

typedef _Mark = ({int value, String label});

class _WeekPainter extends CustomPainter {
  const new({
    required this.days,
    required this.selected,
    required this.top,
    required this.marks,
    required this.bar,
    required this.today,
    required this.surface,
    required this.highlight,
    required this.grid,
    required this.label,
    required this.direction,
  });

  final List<EnergyDayEstimate?> days;
  final int selected;
  final int top;
  final List<_Mark> marks;
  final Color bar;
  final Color today;
  final Color surface;
  final Color highlight;
  final Color grid;
  final TextStyle label;
  final TextDirection direction;

  static const left = 40.0;
  static const right = 8.0;
  static const _top = 8.0;
  static const _bottom = 4.0;
  static const _barWidth = 18.0;
  static const _minBar = 6.0;

  static int indexAt(double dx, double width, int count) {
    final column = (width - left - right) / count;
    return ((dx - left) / column).floor().clamp(0, count - 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final column = (size.width - left - right) / days.length;
    final plot = size.height - _top - _bottom;
    double y(num value) => _top + (1 - value.clamp(0, top) / top) * plot;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left + selected * column + 3, _top, column - 6, plot),
        const Radius.circular(4),
      ),
      Paint()..color = highlight,
    );
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

    final width = math.min(_barWidth, column * 0.6);
    for (final (index, day) in days.indexed) {
      if (day == null) continue;
      final open = index == days.length - 1;
      final center = left + (index + 0.5) * column;
      final high = y(day.range.high);
      final height = math.max(_minBar, y(day.range.low) - high);
      final shape = RRect.fromRectAndRadius(
        Rect.fromLTWH(center - width / 2, high, width, height),
        const Radius.circular(5),
      );
      canvas.drawRRect(
        shape,
        Paint()
          ..color = open ? today : bar
          ..style = open ? PaintingStyle.stroke : PaintingStyle.fill
          ..strokeWidth = 1.5,
      );
      final middle = y(day.total).clamp(high + 1, high + height - 1);
      canvas.drawLine(
        Offset(center - width / 2 + 2, middle),
        Offset(center + width / 2 - 2, middle),
        Paint()
          ..color = open ? today : surface
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_WeekPainter old) =>
      old.days != days ||
      old.selected != selected ||
      old.top != top ||
      old.bar != bar ||
      old.today != today ||
      old.label != label;
}
