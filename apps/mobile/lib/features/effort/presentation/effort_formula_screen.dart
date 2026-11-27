import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/effort/application/effort_gate.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/features/effort/domain/effort_day.dart';
import 'package:open_ring/features/effort/presentation/effort_coach_card.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';

abstract final class EffortFormulaKeys {
  static const points = Key('effort_formula_points');
  static const week = Key('effort_formula_week');
  static const load = Key('effort_formula_load');
  static const defaults = Key('effort_formula_defaults');
  static const lines = Key('effort_formula_lines');
  static const coach = Key('effort_formula_coach');
  static const current = Key('effort_formula_current');
  static const history = Key('effort_formula_history');
  static const sources = Key('effort_formula_sources');
  static const ours = Key('effort_formula_ours');
  static const unchecked = Key('effort_formula_unchecked');
  static const cannot = Key('effort_formula_cannot');

  static Key rule(CoachRule rule) => Key('effort_formula_rule_${rule.name}');
}

String _percent(MetricFormat format, double share) =>
    format.integer(share * 100);

String _plain(MetricFormat format, double value) =>
    format.decimal(value, digits: value == value.roundToDouble() ? 0 : 1);

double _share(int days) => 2 / (days + 1);

/// The condition of one coach rule, with the constants it tests.
String coachRuleCondition(MetricFormat format, CoachRule rule) {
  final l10n = format.l10n;
  return switch (rule) {
    CoachRule.sick => l10n.effortFormulaRuleSick,
    CoachRule.lowReadiness => l10n.effortFormulaRuleReadinessUnder(
      format.integer(readinessFairFrom),
    ),
    CoachRule.hardRun => l10n.effortFormulaRuleHardRun(
      format.integer(effortHardRunDays),
    ),
    CoachRule.noEasyDay => l10n.effortFormulaRuleNoEasy(
      format.integer(effortNoEasyDays),
    ),
    CoachRule.fairReadiness => l10n.effortFormulaRuleReadinessUnder(
      format.integer(readinessGoodFrom),
    ),
    CoachRule.spike => l10n.effortFormulaRuleSpike(
      format.integer(effortAcuteDays),
      _plain(format, effortSpikeFactor),
      format.integer(effortChronicDays),
      format.integer(effortSpikeMinWeekly),
    ),
    CoachRule.hardYesterday => l10n.effortFormulaRuleHardYesterday,
    CoachRule.goodReadiness => l10n.effortFormulaRuleReadinessFrom(
      format.integer(readinessGoodFrom),
    ),
    CoachRule.noReadiness => l10n.effortFormulaRuleNoReadiness,
  };
}

/// From how many days of history each rule on load can match.
String coachRuleHistory(MetricFormat format) {
  String number(CoachRule rule) => format.integer(rule.number);
  return format.l10n.effortFormulaCoachHistory(
    number(CoachRule.noEasyDay),
    format.integer(effortMinLoadDays),
    number(CoachRule.hardYesterday),
    format.integer(effortMinLoadDays + 1),
    number(CoachRule.hardRun),
    format.integer(effortMinLoadDays + effortHardRunDays),
    number(CoachRule.spike),
    format.integer(effortMinLoadDays + DateTime.daysPerWeek),
  );
}

/// The load a minute of each workout type, as one line.
String effortTypeDefaults(MetricFormat format) => [
  for (final type in WorkoutType.values)
    '${type.label(format.l10n)} ${_plain(format, effortTypeDefault(type))}',
].join(', ');

class EffortFormulaScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final on = ref.watch(effortEnabledProvider);
    final current = on
        ? ref.watch(effortCoachCardProvider).value?.advice.rule
        : null;
    final weight = _plain(format, vigorousMinuteWeight);
    final walking = _plain(format, effortWalkingLoadFactor);
    final strengthMinutes = format.integer(effortStrengthMinMinutes);
    final minDays = format.integer(effortMinLoadDays);
    return AppPage(
      title: l10n.formulaLink,
      children: [
        BodyText(l10n.effortFormulaIntro),
        const SizedBox(height: 16),
        _Part(
          key: EffortFormulaKeys.points,
          title: l10n.effortFormulaPointsTitle,
          body: l10n.effortFormulaPointsBody(
            weight,
            _percent(format, moderateFraction),
            _percent(format, vigorousFraction),
            _plain(format, moderateMet),
            _plain(format, vigorousMet),
            format.integer(briskStepsPerMinute),
          ),
          note: l10n.effortFormulaPointsNote,
        ),
        const SizedBox(height: cardGap),
        _Part(
          key: EffortFormulaKeys.week,
          title: l10n.effortFormulaWeekTitle,
          body: l10n.effortFormulaWeekBody(
            format.integer(effortWeekPoints),
            format.integer(effortWeekStrengthDays),
            strengthMinutes,
          ),
        ),
        const SizedBox(height: cardGap),
        _Part(
          key: EffortFormulaKeys.load,
          title: l10n.effortFormulaLoadTitle,
          body: l10n.effortFormulaLoadBody(
            [
              for (final fraction in zoneLowerFractions)
                _percent(format, fraction),
            ].join(', '),
            format.decimal(effortRatingDivisor),
          ),
          note: effortTypeDefaults(format),
          noteKey: EffortFormulaKeys.defaults,
        ),
        const SizedBox(height: cardGap),
        _Part(
          key: EffortFormulaKeys.lines,
          title: l10n.effortFormulaLinesTitle,
          body: l10n.effortFormulaLinesBody(
            walking,
            format.integer(effortAcuteDays),
            format.decimal(_share(effortAcuteDays), digits: 2),
            format.integer(effortChronicDays),
            format.decimal(_share(effortChronicDays), digits: 3),
            format.integer(effortLineSeedDays),
            minDays,
          ),
          note: l10n.effortLoadNoRatio,
        ),
        const SizedBox(height: cardGap),
        _Coach(current: current),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          key: EffortFormulaKeys.sources,
          title: l10n.effortFormulaSourcesTitle,
          icon: Icons.check_rounded,
          facts: [
            l10n.effortFormulaSource1(weight, format.integer(effortWeekPoints)),
            l10n.effortFormulaSource2(
              _percent(format, moderateFraction),
              _percent(format, vigorousFraction),
            ),
            l10n.effortFormulaSource3(format.integer(briskStepsPerMinute)),
            l10n.effortFormulaSource4,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          key: EffortFormulaKeys.ours,
          title: l10n.overallSheetOurs,
          icon: Icons.edit_outlined,
          facts: [
            l10n.effortFormulaOurs1,
            l10n.effortFormulaOurs2(strengthMinutes),
            l10n.effortFormulaOurs3(walking),
            l10n.effortFormulaOurs4(minDays),
            l10n.effortFormulaOurs5,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          key: EffortFormulaKeys.unchecked,
          title: l10n.effortFormulaUncheckedTitle,
          icon: Icons.schedule,
          facts: [
            l10n.effortFormulaUnchecked1(
              format.integer(effortWeekStrengthDays),
            ),
            l10n.effortFormulaUnchecked2,
            l10n.effortFormulaUnchecked3,
            l10n.effortFormulaUnchecked4,
            l10n.effortFormulaUnchecked5,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          key: EffortFormulaKeys.cannot,
          title: l10n.effortFormulaCannotTitle,
          icon: Icons.block,
          facts: [
            l10n.effortFormulaCannot1,
            l10n.effortFormulaCannot2,
            l10n.effortFormulaCannot3,
            l10n.effortFormulaCannot4,
          ],
        ),
        const SizedBox(height: 16),
        CaptionText(l10n.metricEstimateNote),
      ],
    );
  }
}

class _Part extends StatelessWidget {
  const new({
    required this.title,
    required this.body,
    this.note,
    this.noteKey,
    super.key,
  });

  final String title;
  final String body;
  final String? note;
  final Key? noteKey;

  @override
  Widget build(BuildContext context) {
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(title: title, accent: AppColors.of(context).textPrimary),
          const SizedBox(height: 8),
          BodyText(body),
          if (note case final note?) ...[
            const SizedBox(height: 10),
            CaptionText(note, key: noteKey),
          ],
        ],
      ),
    );
  }
}

class _Coach extends StatelessWidget {
  const new({required this.current});

  final CoachRule? current;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    return MetricCard(
      key: EffortFormulaKeys.coach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(
            title: l10n.effortFormulaCoachTitle,
            accent: AppColors.of(context).textPrimary,
          ),
          const SizedBox(height: 8),
          BodyText(
            l10n.effortFormulaCoachIntro(
              format.integer(CoachRule.values.length),
            ),
          ),
          if (current case final current?) ...[
            const SizedBox(height: 6),
            BodyText(
              l10n.effortFormulaCoachCurrent(format.integer(current.number)),
              key: EffortFormulaKeys.current,
            ),
          ],
          const SizedBox(height: 4),
          for (final rule in CoachRule.values)
            _RuleRow(rule: rule, current: rule == current),
          const SizedBox(height: 10),
          CaptionText(
            l10n.effortFormulaCoachNote(
              format.integer(effortHardFloor),
              _plain(format, effortHardFactor),
              format.integer(effortChronicDays),
              _percent(format, effortEasyFraction),
              format.integer(CoachRule.sick.number),
            ),
          ),
          const SizedBox(height: 6),
          CaptionText(coachRuleHistory(format), key: EffortFormulaKeys.history),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const new({required this.rule, required this.current});

  final CoachRule rule;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final weight = current ? FontWeight.w700 : FontWeight.w400;
    final color = current ? colors.textPrimary : colors.textSecondary;
    return MergeSemantics(
      key: EffortFormulaKeys.rule(rule),
      child: Semantics(
        selected: current,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 24),
                child: Text(
                  format.integer(rule.number),
                  style: theme.bodyMedium?.copyWith(
                    color: colors.textLabel,
                    fontWeight: weight,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coachRuleCondition(format, rule),
                      style: theme.bodyMedium?.copyWith(
                        color: color,
                        fontWeight: weight,
                        height: 1.35,
                      ),
                    ),
                    Text(
                      coachVerdictLabel(format.l10n, rule.verdict),
                      style: theme.bodySmall?.copyWith(
                        color: colors.textLabel,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
