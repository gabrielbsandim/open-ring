import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/open_score/domain/level_view.dart';

abstract final class LevelChartKeys {
  static const chart = Key('level_chart');
}

enum LevelDot { none, full, partial, tagged, today }

typedef LevelChartDay = ({double? line, int? score, LevelDot dot});

const _height = 176.0;
const _low = 40;
const _high = 100;
const List<int> _grid = [
  dayScoreMixedFrom,
  dayScoreGoodFrom,
  dayScoreGreatFrom,
];

/// The line and the score of each of the last [levelAccountDays] days and
/// today, oldest first.
List<LevelChartDay> levelChartDays(
  DayScoreHistory history,
  LevelTrack track,
  Set<LocalDate> tagged,
) => [
  for (var age = levelAccountDays; age >= 0; age--)
    _chartDay(history, track, tagged, history.today.addDays(-age)),
];

LevelChartDay _chartDay(
  DayScoreHistory history,
  LevelTrack track,
  Set<LocalDate> tagged,
  LocalDate date,
) {
  final today = date == history.today;
  final scored = history.scoredOn(date);
  return (
    line: today ? track.level : track.lineOn(date),
    score: scored?.value,
    dot: _dot(scored, tagged: tagged.contains(date), today: today),
  );
}

LevelDot _dot(
  Scored<DayScoreFactor>? scored, {
  required bool tagged,
  required bool today,
}) {
  if (scored == null) return LevelDot.none;
  if (tagged) return LevelDot.tagged;
  if (today) return LevelDot.today;
  return scored.isFull ? LevelDot.full : LevelDot.partial;
}

class LevelChart extends StatelessWidget {
  const new({required this.days, required this.today, super.key});

  final List<LevelChartDay> days;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final first = today.addDays(1 - days.length);
    final middle = today.addDays(-(days.length ~/ 2));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          key: LevelChartKeys.chart,
          image: true,
          label: l10n.levelChartSemantics(days.length - 1),
          child: SizedBox(
            height: _height,
            child: CustomPaint(
              painter: _ChartPainter(
                days: days,
                line: colors.textPrimary,
                dot: colors.textLabel,
                muted: colors.strongBorder,
                grid: colors.surfaceBorder,
                surface: colors.surface,
                label:
                    theme.textTheme.labelSmall?.copyWith(
                      color: colors.textLabel,
                    ) ??
                    const TextStyle(),
                direction: Directionality.of(context),
              ),
            ),
          ),
        ),
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(left: _ChartPainter.left),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              children: [
                CaptionText(format.monthDay(first)),
                CaptionText(format.monthDay(middle)),
                CaptionText(l10n.workoutDayToday),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _Legend(
              label: l10n.levelTitle,
              mark: SizedBox(
                width: 14,
                height: 2,
                child: ColoredBox(color: colors.textPrimary),
              ),
            ),
            _Legend(
              label: l10n.levelLegendScore,
              mark: _Circle(color: colors.textLabel, filled: true),
            ),
            _Legend(
              label: l10n.dayScoreHistoryLegendPartial,
              mark: _Circle(color: colors.textLabel, filled: false),
            ),
            _Legend(
              label: l10n.dayScoreHistoryLegendTagged,
              mark: _Circle(color: colors.strongBorder, filled: true),
            ),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const new({required this.label, required this.mark});

  final String label;
  final Widget mark;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ExcludeSemantics(child: mark),
      const SizedBox(width: 6),
      Flexible(child: CaptionText(label)),
    ],
  );
}

class _Circle extends StatelessWidget {
  const new({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 9,
    height: 9,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : null,
        border: filled ? null : Border.all(color: color, width: 1.5),
      ),
    ),
  );
}

class _ChartPainter extends CustomPainter {
  const new({
    required this.days,
    required this.line,
    required this.dot,
    required this.muted,
    required this.grid,
    required this.surface,
    required this.label,
    required this.direction,
  });

  final List<LevelChartDay> days;
  final Color line;
  final Color dot;
  final Color muted;
  final Color grid;
  final Color surface;
  final TextStyle label;
  final TextDirection direction;

  static const left = 26.0;
  static const _right = 8.0;
  static const _top = 8.0;
  static const _bottom = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = size.height - _top - _bottom;
    final step = (size.width - left - _right) / (days.length - 1);
    double x(int index) => left + index * step;
    double y(num value) =>
        _top + (_high - value.clamp(_low, _high)) / (_high - _low) * plot;
    final rule = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final mark in _grid) {
      canvas.drawLine(
        Offset(left, y(mark)),
        Offset(size.width - _right, y(mark)),
        rule,
      );
      final text = TextPainter(
        text: TextSpan(text: '$mark', style: label),
        textDirection: direction,
      )..layout();
      text.paint(
        canvas,
        Offset(left - 6 - text.width, y(mark) - text.height / 2),
      );
    }
    final path = Path();
    var started = false;
    for (var i = 0; i < days.length; i++) {
      final value = days[i].line;
      if (value == null) continue;
      if (started) {
        path.lineTo(x(i), y(value));
        continue;
      }
      path.moveTo(x(i), y(value));
      started = true;
    }
    for (var i = 0; i < days.length; i++) {
      _drawDot(canvas, days[i], x(i), y, size.height - _bottom);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawDot(
    Canvas canvas,
    LevelChartDay day,
    double x,
    double Function(num) y,
    double base,
  ) {
    final score = day.score;
    if (score == null) {
      canvas.drawCircle(Offset(x, base - 4), 1.6, Paint()..color = muted);
      return;
    }
    final at = Offset(x, y(score));
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    switch (day.dot) {
      case LevelDot.none:
        return;
      case LevelDot.full:
        canvas.drawCircle(at, 3, Paint()..color = dot);
      case LevelDot.partial:
        canvas
          ..drawCircle(at, 3, Paint()..color = surface)
          ..drawCircle(at, 3, ring..color = dot);
      case LevelDot.tagged:
        canvas.drawCircle(at, 3, Paint()..color = muted);
      case LevelDot.today:
        canvas
          ..drawCircle(at, 4, Paint()..color = surface)
          ..drawCircle(at, 4, ring..color = line);
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.days != days || old.line != line || old.label != label;
}
