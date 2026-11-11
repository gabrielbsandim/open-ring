import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/heart/application/heart_view.dart';
import 'package:open_ring/features/sleep/application/sleep_view.dart';
import 'package:open_ring/features/sleep/presentation/sleep_labels.dart';
import 'package:open_ring/features/today/application/readiness_view.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/presentation/readiness_labels.dart';

typedef _FormulaRow = ({
  Key key,
  String label,
  String rule,
  String today,
  String points,
});

class FormulaScreen extends ConsumerWidget {
  const new({super.key});

  static const readinessKey = Key('formula_readiness');
  static const baselineKey = Key('formula_baseline');
  static const sleepKey = Key('formula_sleep');
  static Key readinessFactorKey(ReadinessFactor factor) =>
      Key('formula_readiness_${factor.name}');
  static Key sleepFactorKey(SleepFactor factor) =>
      Key('formula_sleep_${factor.name}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppPage(
      title: MetricFormat.of(context).l10n.formulaLink,
      children: [
        AsyncBody(
          value: ref.watch(formulaViewProvider),
          builder: (view) => _FormulaBody(view: view),
        ),
      ],
    );
  }
}

class _FormulaBody extends StatelessWidget {
  const new({required this.view});

  final FormulaView view;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final readiness = view.readiness;
    final week = view.week;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BodyText(l10n.formulaIntro),
        const SizedBox(height: 8),
        BodyText(l10n.formulaRamp),
        const SizedBox(height: 16),
        _FormulaCard(
          key: FormulaScreen.readinessKey,
          title: l10n.readinessTitle,
          accent: colors.textPrimary,
          score: readiness.value,
          rows: [
            for (final factor in ReadinessFactor.values)
              _readinessRow(format, readiness, factor),
          ],
          notes: [if (readiness.value == null) l10n.readinessNeeds],
        ),
        const SizedBox(height: cardGap),
        MetricCard(
          key: FormulaScreen.baselineKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccentTitle(
                title: l10n.formulaBaselineTitle,
                accent: colors.heart,
              ),
              const SizedBox(height: 10),
              BodyText(
                l10n.formulaBaselineRule(
                  format.integer(baselineWindowDays),
                  format.integer(baselineMinDays),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: cardGap),
        _FormulaCard(
          key: FormulaScreen.sleepKey,
          title: l10n.readinessFactorSleep,
          accent: colors.sleep,
          score: week.latest.scoreValue,
          rows: [
            for (final factor in SleepFactor.values)
              if (week.remMeasured || factor != SleepFactor.rem)
                _sleepRow(format, week, factor),
          ],
          notes: [
            if (week.latest.scoreValue == null) l10n.sleepScoreTooShort,
            if (!week.remMeasured) l10n.sleepRemNotMeasured,
          ],
        ),
        const SizedBox(height: 16),
        const EstimateNote(),
      ],
    );
  }

  _FormulaRow _readinessRow(
    MetricFormat format,
    ReadinessView view,
    ReadinessFactor factor,
  ) {
    final contribution = view.contribution(factor);
    return (
      key: FormulaScreen.readinessFactorKey(factor),
      label: factor.label(format),
      rule: _readinessRule(format, factor),
      today: format.l10n.formulaToday(_readinessToday(format, view, factor)),
      points: _points(format, contribution, factor.weight),
    );
  }

  String _readinessRule(MetricFormat format, ReadinessFactor factor) {
    final l10n = format.l10n;
    return switch (factor) {
      ReadinessFactor.sleep => l10n.formulaReadinessSleep,
      ReadinessFactor.hrv => l10n.formulaReadinessHrv(
        format.signed(hrvZeroZ),
        format.signed(hrvFullZ),
      ),
      ReadinessFactor.restingHeartRate => l10n.formulaReadinessRestingHr(
        format.signed(restingHeartRateZeroZ),
        format.signed(restingHeartRateFullZ),
      ),
      ReadinessFactor.activityLoad => l10n.formulaReadinessLoad(
        format.integer(acuteLoadDays),
        format.integer(chronicLoadDays),
        format.decimal(loadFullRatio, digits: 1),
        format.decimal(loadZeroRatio, digits: 1),
      ),
    };
  }

  String _readinessToday(
    MetricFormat format,
    ReadinessView view,
    ReadinessFactor factor,
  ) {
    final missing = format.l10n.metricNoReading;
    return switch (factor) {
      ReadinessFactor.sleep => view.sleep.scoreValue?.toString() ?? missing,
      ReadinessFactor.hrv => _deviation(format, view.hrv, format.ms),
      ReadinessFactor.restingHeartRate => _deviation(
        format,
        view.restingHeartRate,
        format.bpm,
      ),
      ReadinessFactor.activityLoad => _load(format, view.activityLoad),
    };
  }

  String _load(MetricFormat format, ActivityLoad? load) => load == null
      ? format.l10n.metricNoReading
      : format.decimal(load.ratio, digits: 2);

  String _deviation(
    MetricFormat format,
    BaselineInput input,
    String Function(double) show,
  ) {
    final deviation = input.deviation;
    if (deviation != null) {
      return format.l10n.formulaDeviation(
        show(deviation.today),
        show(deviation.baseline),
        format.signed(deviation.zScore, digits: 1),
      );
    }
    final today = input.today;
    return today == null ? format.l10n.metricNoReading : show(today);
  }

  _FormulaRow _sleepRow(
    MetricFormat format,
    SleepWeekView week,
    SleepFactor factor,
  ) {
    final contribution = switch (week.latest.score) {
      final Scored<SleepFactor> scored => scored.of(factor),
      InsufficientData() => null,
    };
    final today = contribution == null
        ? format.l10n.metricNoReading
        : factor.value(format, contribution.value);
    return (
      key: FormulaScreen.sleepFactorKey(factor),
      label: factor.label(format, week.goal),
      rule: _sleepRule(format, factor, week.goal),
      today: format.l10n.formulaToday(today),
      points: _points(format, contribution, factor.weight),
    );
  }

  String _sleepRule(MetricFormat format, SleepFactor factor, Duration goal) {
    final l10n = format.l10n;
    return switch (factor) {
      SleepFactor.duration => l10n.formulaSleepDuration(format.duration(goal)),
      SleepFactor.efficiency => l10n.formulaSleepEfficiency(
        format.percent(efficiencyZeroPercent),
        format.percent(efficiencyFullPercent),
      ),
      SleepFactor.latency => l10n.formulaSleepLatency(
        format.duration(Duration(minutes: latencyFullMinutes.round())),
        format.duration(Duration(minutes: latencyZeroMinutes.round())),
      ),
      SleepFactor.deep => l10n.formulaSleepDeep(
        format.percent(deepTargetPercent),
      ),
      SleepFactor.rem => l10n.formulaSleepRem(format.percent(remTargetPercent)),
    };
  }

  String _points(
    MetricFormat format,
    Contribution<Enum>? contribution,
    double baseWeight,
  ) {
    if (contribution == null) {
      return format.l10n.readinessUpTo(format.points(baseWeight));
    }
    return format.l10n.metricPoints(
      format.points(contribution.points),
      format.points(contribution.weight),
    );
  }
}

class _FormulaCard extends StatelessWidget {
  const new({
    required this.title,
    required this.accent,
    required this.score,
    required this.rows,
    required this.notes,
    super.key,
  });

  final String title;
  final Color accent;
  final int? score;
  final List<_FormulaRow> rows;
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    final value = score;
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(title: title, accent: accent),
          for (final row in rows) ...[
            Divider(height: 28, color: colors.surfaceBorder),
            _FormulaRowView(key: row.key, row: row),
          ],
          Divider(height: 28, color: colors.strongBorder),
          MergeSemantics(
            child: MetricRow(
              label: l10n.readinessTotal,
              value: value == null ? l10n.readinessNotScored : '$value',
            ),
          ),
          for (final note in notes) ...[
            const SizedBox(height: 8),
            CaptionText(note),
          ],
        ],
      ),
    );
  }
}

class _FormulaRowView extends StatelessWidget {
  const new({required this.row, super.key});

  final _FormulaRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                row.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              CaptionText(row.points, color: colors.textSecondary),
            ],
          ),
          const SizedBox(height: 6),
          BodyText(row.rule),
          const SizedBox(height: 6),
          Text(row.today, style: numberStyle(theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
