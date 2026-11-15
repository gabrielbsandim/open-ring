import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/open_score/presentation/day_score_card.dart';
import 'package:open_ring/features/open_score/presentation/day_score_formula_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class DayScoreHistoryKeys {
  static const empty = Key('day_score_history_empty');
  static const emptyAction = Key('day_score_history_empty_action');
  static const view = Key('day_score_history_view');
  static const month = Key('day_score_history_month');
  static const previousMonth = Key('day_score_history_previous_month');
  static const nextMonth = Key('day_score_history_next_month');
  static const average = Key('day_score_history_average');
  static const chart = Key('day_score_history_chart');
  static const readout = Key('day_score_history_readout');
  static const open = Key('day_score_history_open');

  static Key day(LocalDate date) => Key('day_score_history_${date.iso}');
}

enum DayScoreHistoryView {
  calendar(0),
  month(30),
  quarter(90);

  new(this.days);

  final int days;
}

const _daysInWeek = 7;
const _chartHeight = 176.0;
const List<int> _chartGrid = [
  dayScoreMixedFrom,
  dayScoreGoodFrom,
  dayScoreGreatFrom,
];
const _maxScore = 100;

class DayScoreHistoryScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<DayScoreHistoryScreen> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<DayScoreHistoryScreen> {
  DayScoreHistoryView _view = DayScoreHistoryView.calendar;
  LocalDate? _month;
  LocalDate? _selected;

  void _open(LocalDate date) => context.go(AppPaths.dayScoreOn(date.iso));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final on = ref.watch(
      enabledModulesProvider.select(
        (modules) => modules.value?.contains(ModuleId.openScore) ?? false,
      ),
    );
    return AppPage(
      title: l10n.dayScoreHistoryTitle,
      children: on ? _content(ref.watch(dayScoreHistoryProvider), l10n) : [],
    );
  }

  List<Widget> _content(
    AsyncValue<DayScoreHistory> history,
    AppLocalizations l10n,
  ) {
    if (history.hasValue) return _body(history.requireValue, l10n);
    if (history.hasError) return [BodyText(l10n.metricLoadError)];
    return const [SizedBox(height: 96)];
  }

  List<Widget> _body(DayScoreHistory history, AppLocalizations l10n) {
    if (history.firstScored == null) {
      return [
        EmptyStateCard(
          key: DayScoreHistoryKeys.empty,
          icon: Icons.calendar_month_rounded,
          accent: AppColors.of(context).textPrimary,
          title: l10n.dayScoreReceiptNoneYet,
          message: l10n.dayScoreHistoryEmptyBody,
          actionLabel: l10n.dayScoreHistoryEmptyAction,
          actionKey: DayScoreHistoryKeys.emptyAction,
          onAction: () => context.go(AppPaths.dayScore),
        ),
      ];
    }
    final view = _view;
    return [
      SegmentedButton<DayScoreHistoryView>(
        key: DayScoreHistoryKeys.view,
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: DayScoreHistoryView.calendar,
            label: Text(l10n.dayScoreHistoryViewCalendar),
          ),
          ButtonSegment(
            value: DayScoreHistoryView.month,
            label: Text(l10n.dayScoreHistoryView30),
          ),
          ButtonSegment(
            value: DayScoreHistoryView.quarter,
            label: Text(l10n.dayScoreHistoryView90),
          ),
        ],
        selected: {view},
        onSelectionChanged: (picked) => setState(() => _view = picked.first),
      ),
      const SizedBox(height: cardGap),
      if (view == DayScoreHistoryView.calendar)
        _Calendar(
          history: history,
          month: _month ?? _firstOf(history.today),
          onMonth: (month) => setState(() => _month = month),
          onDay: _open,
        ),
      if (view != DayScoreHistoryView.calendar)
        _Bars(
          history: history,
          days: view.days,
          selected: _selected,
          onSelect: (date) => setState(() => _selected = date),
          onOpen: _open,
        ),
      const SizedBox(height: cardGap),
      DayScoreListCard(
        title: l10n.dayScoreHistoryHowTitle,
        lines: [
          l10n.dayScoreHistoryHow1,
          l10n.dayScoreHistoryHow2,
          l10n.dayScoreHistoryHow3,
        ],
      ),
    ];
  }
}

LocalDate _firstOf(LocalDate date) => LocalDate(date.year, date.month, 1);

LocalDate _monthAfter(LocalDate first, int months) {
  final moved = DateTime.utc(first.year, first.month + months);
  return LocalDate(moved.year, moved.month, 1);
}

String _dayLabel(
  MetricFormat format,
  DayScoreHistory history,
  LocalDate date,
) => switch (history.today.daysSince(date)) {
  0 => '${format.l10n.workoutDayToday}, ${format.monthDay(date)}',
  1 => '${format.l10n.workoutDayYesterday}, ${format.monthDay(date)}',
  _ => format.date(date),
};

String _coverage(AppLocalizations l10n, Scored<DayScoreFactor> scored) =>
    scored.isFull
    ? l10n.dayScoreCoverageFull
    : l10n.dayScoreCoveragePartial(scored.coverage.round());

class _Calendar extends StatelessWidget {
  const new({
    required this.history,
    required this.month,
    required this.onMonth,
    required this.onDay,
  });

  final DayScoreHistory history;
  final LocalDate month;
  final ValueChanged<LocalDate> onMonth;
  final ValueChanged<LocalDate> onDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final material = MaterialLocalizations.of(context);
    final firstDay = material.firstDayOfWeekIndex;
    final oldest = _firstOf(history.dates.first);
    final newest = _firstOf(history.today);
    final length = _monthAfter(month, 1).daysSince(month);
    final weekday = DateTime.utc(month.year, month.month).weekday;
    final lead = (weekday - firstDay) % _daysInWeek;
    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var day = 0; day < length; day++)
        _Cell(history: history, date: month.addDays(day), onDay: onDay),
    ];
    final rows = (cells.length / _daysInWeek).ceil();
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                key: DayScoreHistoryKeys.previousMonth,
                onPressed: month.compareTo(oldest) > 0
                    ? () => onMonth(_monthAfter(month, -1))
                    : null,
                tooltip: l10n.dayScoreHistoryPrevMonth,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  key: DayScoreHistoryKeys.month,
                  format.monthYear(month),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                key: DayScoreHistoryKeys.nextMonth,
                onPressed: month.compareTo(newest) < 0
                    ? () => onMonth(_monthAfter(month, 1))
                    : null,
                tooltip: l10n.dayScoreHistoryNextMonth,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < _daysInWeek; i++)
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: CaptionText(
                        material.narrowWeekdays[(firstDay + i) % _daysInWeek],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          for (var row = 0; row < rows; row++)
            Row(
              children: [
                for (var i = 0; i < _daysInWeek; i++)
                  Expanded(
                    child: row * _daysInWeek + i < cells.length
                        ? cells[row * _daysInWeek + i]
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          const _Legend(),
          const SizedBox(height: 8),
          CaptionText(l10n.dayScoreHistoryCalendarHint),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const new({required this.history, required this.date, required this.onDay});

  final DayScoreHistory history;
  final LocalDate date;
  final ValueChanged<LocalDate> onDay;

  static const Map<DayScoreBand, double> _fill = {
    DayScoreBand.low: 0.05,
    DayScoreBand.mixed: 0.10,
    DayScoreBand.good: 0.16,
    DayScoreBand.great: 0.24,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final known = history.on(date) != null;
    final scored = history.scoredOn(date);
    final today = date == history.today;
    final name = _dayLabel(format, history, date);
    final number = Text(
      format.integer(date.day),
      style: theme.textTheme.bodySmall?.copyWith(
        color: known ? colors.textLabel : colors.strongBorder,
        fontWeight: today ? FontWeight.w700 : null,
        decoration: today ? TextDecoration.underline : null,
      ),
    );
    final value = Text(
      scored == null ? '·' : format.integer(scored.value),
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: known ? null : Colors.transparent,
      ),
    );
    final box = Padding(
      padding: const EdgeInsets.all(2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scored != null && scored.isFull
              ? colors.textPrimary.withValues(
                  alpha: _fill[dayScoreBand(scored.value)],
                )
              : null,
          border: scored != null && !scored.isFull
              ? Border.all(color: colors.textLabel, width: 1.5)
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [number, value],
            ),
          ),
        ),
      ),
    );
    if (!known) return ExcludeSemantics(child: box);
    return Semantics(
      key: DayScoreHistoryKeys.day(date),
      button: true,
      label: _semantics(l10n, name, scored),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onDay(date),
        child: box,
      ),
    );
  }

  String _semantics(
    AppLocalizations l10n,
    String name,
    Scored<DayScoreFactor>? scored,
  ) {
    if (scored == null) return l10n.dayScoreHistoryCellNone(name);
    final band = dayScoreBandLabel(l10n, dayScoreBand(scored.value));
    if (scored.isFull) {
      return l10n.dayScoreHistoryCellScored(name, scored.value, band);
    }
    return l10n.dayScoreHistoryCellPartial(
      name,
      scored.value,
      band,
      scored.coverage.round(),
    );
  }
}

class _Legend extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final marks = [
      (
        label: l10n.dayScoreHistoryLegendFull,
        decoration: BoxDecoration(
          color: colors.textLabel,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      (
        label: l10n.dayScoreHistoryLegendPartial,
        decoration: BoxDecoration(
          border: Border.all(color: colors.textLabel, width: 1.5),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      (
        label: l10n.dayScoreReceiptNoScore,
        decoration: BoxDecoration(
          color: colors.strongBorder,
          shape: BoxShape.circle,
        ),
      ),
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final mark in marks)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: SizedBox(
                  width: 10,
                  height: 10,
                  child: DecoratedBox(decoration: mark.decoration),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(child: CaptionText(mark.label)),
            ],
          ),
      ],
    );
  }
}

class _Bars extends StatelessWidget {
  const new({
    required this.history,
    required this.days,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
  });

  final DayScoreHistory history;
  final int days;
  final LocalDate? selected;
  final ValueChanged<LocalDate> onSelect;
  final ValueChanged<LocalDate> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final average = history.fullAverage(days);
    final first = history.today.addDays(1 - days);
    final picked = selected;
    final shown = picked != null && picked.compareTo(first) >= 0
        ? picked
        : null;
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            key: DayScoreHistoryKeys.average,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (average != null) ...[
                  Text(
                    format.integer(average.value),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  CaptionText(l10n.dayScoreHistoryAvgFull(average.count)),
                ],
                if (average == null) BodyText(l10n.dayScoreHistoryAvgNone),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            label: l10n.dayScoreHistoryChartSemantics(days),
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                key: DayScoreHistoryKeys.chart,
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => onSelect(
                  first.addDays(
                    _BarsPainter.indexAt(
                      details.localPosition.dx,
                      constraints.maxWidth,
                      days,
                    ),
                  ),
                ),
                child: CustomPaint(
                  size: Size(constraints.maxWidth, _chartHeight),
                  painter: _BarsPainter(
                    scores: [
                      for (var i = 0; i < days; i++)
                        _bar(history, first.addDays(i)),
                    ],
                    selected: shown?.daysSince(first),
                    bar: colors.textPrimary,
                    grid: colors.surfaceBorder,
                    none: colors.strongBorder,
                    highlight: colors.surfaceInner,
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
          ),
          const SizedBox(height: 10),
          const _Legend(),
          const SizedBox(height: 12),
          if (shown == null) CaptionText(l10n.dayScoreHistoryPick),
          if (shown != null)
            _Readout(history: history, date: shown, onOpen: onOpen),
        ],
      ),
    );
  }

  _Bar? _bar(DayScoreHistory history, LocalDate date) {
    if (history.on(date) == null) return null;
    final scored = history.scoredOn(date);
    return (value: scored?.value, full: scored?.isFull ?? false);
  }
}

typedef _Bar = ({int? value, bool full});

class _BarsPainter extends CustomPainter {
  const new({
    required this.scores,
    required this.selected,
    required this.bar,
    required this.grid,
    required this.none,
    required this.highlight,
    required this.label,
    required this.direction,
  });

  final List<_Bar?> scores;
  final int? selected;
  final Color bar;
  final Color grid;
  final Color none;
  final Color highlight;
  final TextStyle label;
  final TextDirection direction;

  static const _left = 26.0;
  static const _top = 8.0;
  static const _bottom = 8.0;
  static const _barShare = 0.7;
  static const _minBar = 1.6;

  static int indexAt(double dx, double width, int count) {
    final slot = (width - _left) / count;
    return ((dx - _left) / slot).floor().clamp(0, count - 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plot = size.height - _top - _bottom;
    final slot = (size.width - _left) / scores.length;
    final width = (slot * _barShare).clamp(_minBar, slot);
    double y(num score) => _top + (_maxScore - score) / _maxScore * plot;
    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final mark in [0, ..._chartGrid]) {
      canvas.drawLine(
        Offset(_left, y(mark)),
        Offset(size.width, y(mark)),
        line,
      );
    }
    for (final mark in _chartGrid) {
      final text = TextPainter(
        text: TextSpan(text: '$mark', style: label),
        textDirection: direction,
      )..layout();
      text.paint(
        canvas,
        Offset(_left - 6 - text.width, y(mark) - text.height / 2),
      );
    }
    final picked = selected;
    if (picked != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(_left + picked * slot, _top, slot, plot),
          const Radius.circular(2),
        ),
        Paint()..color = highlight,
      );
    }
    final fill = Paint()..color = bar;
    final stroke = Paint()
      ..color = bar
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final dot = Paint()..color = none;
    for (var i = 0; i < scores.length; i++) {
      final score = scores[i];
      if (score == null) continue;
      final x = _left + i * slot + (slot - width) / 2;
      final value = score.value;
      if (value == null) {
        canvas.drawCircle(
          Offset(x + width / 2, y(0) - 4),
          (width / 2).clamp(1, 2),
          dot,
        );
        continue;
      }
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(x, y(value), x + width, y(0)),
        Radius.circular((width / 3).clamp(0, 2)),
      );
      canvas.drawRRect(
        score.full ? rect : rect.deflate(0.5),
        score.full ? fill : stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.scores != scores ||
      old.selected != selected ||
      old.bar != bar ||
      old.label != label;
}

class _Readout extends StatelessWidget {
  const new({required this.history, required this.date, required this.onOpen});

  final DayScoreHistory history;
  final LocalDate date;
  final ValueChanged<LocalDate> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final scored = history.scoredOn(date);
    final main = scored == null
        ? l10n.dayScoreReceiptNoneTitle
        : '${format.integer(scored.value)} · '
              '${dayScoreBandLabel(l10n, dayScoreBand(scored.value))}';
    return Wrap(
      key: DayScoreHistoryKeys.readout,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              CaptionText(_dayLabel(format, history, date)),
              Text(
                main,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (scored != null) CaptionText(_coverage(l10n, scored)),
            ],
          ),
        ),
        SecondaryButton(
          key: DayScoreHistoryKeys.open,
          label: l10n.dayScoreHistoryOpenReceipt,
          onPressed: () => onOpen(date),
        ),
      ],
    );
  }
}
