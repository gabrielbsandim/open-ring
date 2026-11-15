import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/open_score/application/day_score_view.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/open_score/presentation/day_score_card.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class DayScoreReceiptKeys {
  static const previous = Key('day_score_receipt_previous');
  static const next = Key('day_score_receipt_next');
  static const day = Key('day_score_receipt_day');
  static const status = Key('day_score_receipt_status');
  static const none = Key('day_score_receipt_none');
  static const earned = Key('day_score_receipt_earned');
  static const leftOut = Key('day_score_receipt_left_out');
  static const rescale = Key('day_score_receipt_rescale');
  static const result = Key('day_score_receipt_result');
  static const minimum = Key('day_score_receipt_minimum');
  static const open = Key('day_score_receipt_open');
  static const formula = Key('day_score_receipt_formula');

  static Key factor(DayScoreFactor factor) =>
      Key('day_score_receipt_${factor.name}');
}

const _openThreshold = 0.5;

class DayScoreReceiptScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<DayScoreReceiptScreen> createState() => _ReceiptState();
}

class _ReceiptState extends ConsumerState<DayScoreReceiptScreen> {
  LocalDate? _picked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final on = ref.watch(
      enabledModulesProvider.select(
        (modules) => modules.value?.contains(ModuleId.openScore) ?? false,
      ),
    );
    return AppPage(
      title: l10n.dayScoreReceiptTitle,
      children: on ? _content(ref.watch(dayScoreHistoryProvider), l10n) : [],
    );
  }

  List<Widget> _content(
    AsyncValue<DayScoreHistory> history,
    AppLocalizations l10n,
  ) {
    if (history.hasValue) return _day(history.requireValue);
    if (history.hasError) return [BodyText(l10n.metricLoadError)];
    return const [SizedBox(height: 96)];
  }

  List<Widget> _day(DayScoreHistory history) {
    final picked = _picked;
    final date = picked != null && history.inputsOn(picked) != null
        ? picked
        : history.today;
    final inputs = history.inputsOn(date);
    if (inputs == null) return const [];
    final receipt = DayScoreReceipt(inputs);
    final today = date == history.today;
    final format = MetricFormat.of(context);
    return [
      _DayNav(
        date: date,
        today: history.today,
        onPrevious: date == history.dates.first
            ? null
            : () => setState(() => _picked = date.addDays(-1)),
        onNext: today ? null : () => setState(() => _picked = date.addDays(1)),
      ),
      const SizedBox(height: cardGap),
      _Summary(
        receipt: receipt,
        today: today,
        first: history.firstScored == null,
      ),
      const SizedBox(height: cardGap),
      _Math(receipt: receipt, today: today),
      if (today && receipt.open >= _openThreshold) ...[
        const SizedBox(height: cardGap),
        _Open(receipt: receipt),
      ],
      const SizedBox(height: cardGap),
      const _Never(),
      const SizedBox(height: cardGap),
      const _FormulaLink(),
      const SizedBox(height: cardGap),
      CaptionText(format.l10n.metricEstimateNote),
    ];
  }
}

class _DayNav extends ConsumerWidget {
  const new({
    required this.date,
    required this.today,
    required this.onPrevious,
    required this.onNext,
  });

  final LocalDate date;
  final LocalDate today;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final now = ref.watch(clockProvider)();
    final status = date == today
        ? l10n.dayScoreReceiptSoFar(format.clock(now, now.timeZoneOffset))
        : l10n.dayScoreReceiptFinal;
    return Row(
      children: [
        IconButton(
          key: DayScoreReceiptKeys.previous,
          onPressed: onPrevious,
          tooltip: l10n.dayScoreReceiptPrev,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: MergeSemantics(
            child: Column(
              children: [
                Text(
                  key: DayScoreReceiptKeys.day,
                  _label(format),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                CaptionText(
                  key: DayScoreReceiptKeys.status,
                  status,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        IconButton(
          key: DayScoreReceiptKeys.next,
          onPressed: onNext,
          tooltip: l10n.dayScoreReceiptNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  String _label(MetricFormat format) => switch (today.daysSince(date)) {
    0 => '${format.l10n.workoutDayToday}, ${format.monthDay(date)}',
    1 => '${format.l10n.workoutDayYesterday}, ${format.monthDay(date)}',
    _ => format.date(date),
  };
}

class _Summary extends StatelessWidget {
  const new({required this.receipt, required this.today, required this.first});

  final DayScoreReceipt receipt;
  final bool today;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final scored = receipt.scored;
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (scored != null) DayScoreHeadline(scored: scored),
          if (scored == null) _None(receipt: receipt, yet: today && first),
          const SizedBox(height: 14),
          ExcludeSemantics(
            child: DayScoreBar(subscore: (f) => receipt.of(f)?.subscore),
          ),
        ],
      ),
    );
  }
}

class _None extends StatelessWidget {
  const new({required this.receipt, required this.yet});

  final DayScoreReceipt receipt;
  final bool yet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final reason = switch (receipt.gap) {
      DayScoreGap.night => l10n.dayScoreNoneSleep,
      DayScoreGap.steps => l10n.dayScoreNoneSteps,
      _ => l10n.dayScoreReceiptNoneCoverage(receipt.coverage.round()),
    };
    return Column(
      key: DayScoreReceiptKeys.none,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          yet ? l10n.dayScoreReceiptNoneYet : l10n.dayScoreReceiptNoneTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        BodyText('$reason ${l10n.dayScoreReceiptBlank}'),
      ],
    );
  }
}

class _Math extends StatelessWidget {
  const new({required this.receipt, required this.today});

  final DayScoreReceipt receipt;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final scored = receipt.scored;
    final missing = receipt.missing;
    final coverage = format.points(receipt.coverage);
    final earned = format.points(receipt.total);
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(
            title: l10n.dayScoreReceiptMath,
            accent: colors.textPrimary,
          ),
          for (final pillar in DayScorePillar.values) ...[
            const SizedBox(height: 14),
            _PillarHead(receipt: receipt, pillar: pillar),
            for (final factor in factorsOf(pillar))
              _FactorRow(
                key: DayScoreReceiptKeys.factor(factor),
                receipt: receipt,
                factor: factor,
                open: today && dayScoreOpenFactors.contains(factor),
              ),
          ],
          const SizedBox(height: 14),
          Divider(height: 1, color: colors.surfaceBorder),
          const SizedBox(height: 10),
          _Line(
            key: DayScoreReceiptKeys.earned,
            label: l10n.dayScoreReceiptEarned,
            value: l10n.dayScoreReceiptOf(earned, coverage),
          ),
          if (missing.isNotEmpty) ...[
            _Line(
              key: DayScoreReceiptKeys.leftOut,
              label: l10n.dayScoreReceiptLeftOut,
              value: l10n.dayScoreReceiptPoints(
                format.points(dayScoreFullCoverage - receipt.coverage),
              ),
            ),
            CaptionText(
              [for (final f in missing) dayScoreFactorLabel(l10n, f)]
                  .join(', '),
            ),
          ],
          if (scored != null && !scored.isFull)
            _Line(
              key: DayScoreReceiptKeys.rescale,
              label: l10n.dayScoreReceiptRescale,
              value:
                  '${format.decimal(receipt.total, digits: receipt.rescaleDigits)}'
                  ' ÷ $coverage × ${format.integer(100)}',
            ),
          _Line(
            key: DayScoreReceiptKeys.result,
            label: l10n.dayScoreTitle,
            value: scored == null
                ? l10n.dayScoreReceiptNoScore
                : format.integer(scored.value),
            strong: true,
          ),
          if (receipt.gap == DayScoreGap.coverage)
            CaptionText(
              key: DayScoreReceiptKeys.minimum,
              l10n.dayScoreReceiptMinimum(receipt.coverage.round()),
            ),
        ],
      ),
    );
  }
}

class _PillarHead extends StatelessWidget {
  const new({required this.receipt, required this.pillar});

  final DayScoreReceipt receipt;
  final DayScorePillar pillar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final factors = factorsOf(pillar);
    final available = receipt.available(factors);
    final subtotal = factors.length > 1 && available > 0;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dayScorePillarColor(colors, pillar),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                dayScorePillarLabel(format.l10n, pillar),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.textLabel,
                ),
              ),
            ),
          ],
        ),
        if (subtotal)
          CaptionText(
            format.l10n.dayScoreReceiptOf(
              format.points(receipt.earned(factors)),
              format.points(available),
            ),
          ),
      ],
    );
  }
}

String _factorRule(AppLocalizations l10n, DayScoreFactor factor) =>
    switch (factor) {
      DayScoreFactor.sleep => l10n.dayScoreReceiptRuleSleep,
      DayScoreFactor.steps => l10n.dayScoreReceiptRuleSteps,
      DayScoreFactor.intensity => l10n.dayScoreReceiptRuleIntensity,
      DayScoreFactor.hrv => l10n.dayScoreReceiptRuleHigher,
      DayScoreFactor.restingHeartRate => l10n.dayScoreReceiptRuleLower,
      DayScoreFactor.stress => l10n.dayScoreReceiptRuleLower,
      DayScoreFactor.spo2 => l10n.dayScoreReceiptRuleSpo2,
    };

String _factorGone(AppLocalizations l10n, DayScoreFactor factor) =>
    switch (factor) {
      DayScoreFactor.sleep => l10n.dayScoreReceiptGoneSleep,
      DayScoreFactor.steps => l10n.dayScoreReceiptGoneSteps,
      DayScoreFactor.intensity => l10n.dayScoreReceiptGoneIntensity,
      DayScoreFactor.hrv => l10n.dayScoreReceiptGoneBaseline,
      DayScoreFactor.restingHeartRate => l10n.dayScoreReceiptGoneBaseline,
      DayScoreFactor.stress => l10n.dayScoreReceiptGoneStress,
      DayScoreFactor.spo2 => l10n.dayScoreReceiptGoneSpo2,
    };

String _z(MetricFormat format, BaselineDeviation? deviation) =>
    format.signed(deviation?.zScore ?? 0, digits: 1);

String _factorInput(
  MetricFormat format,
  DayScoreInputs inputs,
  DayScoreFactor factor,
) {
  final l10n = format.l10n;
  return switch (factor) {
    DayScoreFactor.sleep => l10n.dayScoreReceiptInputSleep(
      format.integer(inputs.sleepScore ?? 0),
    ),
    DayScoreFactor.steps => l10n.dayScoreReceiptInputSteps(
      format.integer(inputs.steps ?? 0),
      format.integer(inputs.stepGoal),
    ),
    DayScoreFactor.intensity => l10n.dayScoreReceiptInputIntensity(
      format.integer(inputs.intensityMinutes ?? 0),
      format.integer(intensityWeeklyTarget),
    ),
    DayScoreFactor.hrv => l10n.dayScoreReceiptInputBaseline(
      format.ms(inputs.hrv?.today ?? 0),
      _z(format, inputs.hrv),
    ),
    DayScoreFactor.restingHeartRate => l10n.dayScoreReceiptInputBaseline(
      format.bpm(inputs.restingHeartRate?.today ?? 0),
      _z(format, inputs.restingHeartRate),
    ),
    DayScoreFactor.stress => l10n.dayScoreReceiptInputStress(
      format.integer(inputs.stress?.today ?? 0),
      _z(format, inputs.stress),
    ),
    DayScoreFactor.spo2 => l10n.dayScoreReceiptInputSpo2(
      l10n.metricPercent(format.decimal(inputs.spo2Mean ?? 0, digits: 1)),
    ),
  };
}

class _FactorRow extends StatelessWidget {
  const new({
    required this.receipt,
    required this.factor,
    required this.open,
    super.key,
  });

  final DayScoreReceipt receipt;
  final DayScoreFactor factor;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final part = receipt.of(factor);
    final weight = factor.weight.round();
    final input = _factorInput(format, receipt.inputs, factor);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Line(
              label: dayScoreFactorName(l10n, factor),
              value: part == null
                  ? l10n.dayScoreReceiptOut
                  : l10n.dayScoreReceiptOf(
                      format.points(part.points),
                      format.integer(weight),
                    ),
            ),
            if (part == null)
              CaptionText(
                '${_factorGone(l10n, factor)} '
                '${l10n.dayScoreReceiptOutPoints(weight)}',
              ),
            if (part != null) ...[
              CaptionText(
                l10n.dayScoreReceiptInput(
                  open ? l10n.dayScoreReceiptUntilNow(input) : input,
                ),
              ),
              CaptionText(
                l10n.dayScoreReceiptRule(_factorRule(l10n, factor), weight),
              ),
            ],
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: DayScoreMeter(
                fill: part?.subscore,
                color: dayScorePillarColor(colors, factor.pillar),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    this.strong = false,
    super.key,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = strong
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyLarge;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          children: [
            Text(label, style: style),
            Text(value, style: style),
          ],
        ),
      ),
    );
  }
}

class _Open extends StatelessWidget {
  const new({required this.receipt});

  final DayScoreReceipt receipt;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final names = [
      for (final factor in dayScoreOpenFactors)
        if (receipt.of(factor) != null) dayScoreFactorLabel(l10n, factor),
    ].join(', ');
    return MetricCard(
      color: colors.surfaceInner,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.schedule_rounded,
              size: 20,
              color: colors.textLabel,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: BodyText(
              key: DayScoreReceiptKeys.open,
              l10n.dayScoreReceiptOpen(format.points(receipt.open), names),
            ),
          ),
        ],
      ),
    );
  }
}

class _Never extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(
            title: l10n.dayScoreReceiptNeverTitle,
            accent: colors.textPrimary,
          ),
          const SizedBox(height: 8),
          BodyText(l10n.dayScoreReceiptNever1),
          const SizedBox(height: 4),
          BodyText(l10n.dayScoreReceiptNever2),
        ],
      ),
    );
  }
}

class _FormulaLink extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    return MetricCard(
      key: DayScoreReceiptKeys.formula,
      onTap: () => context.go(AppPaths.dayScoreFormula),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.formulaLink,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                CaptionText(l10n.dayScoreFormulaLinkCaption),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ExcludeSemantics(
            child: Icon(Icons.chevron_right_rounded, color: colors.textLabel),
          ),
        ],
      ),
    );
  }
}
