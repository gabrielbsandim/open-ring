import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/effort/application/effort_gate.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class EffortCoachKeys {
  static const card = Key('today_effort_coach');
  static const verdict = Key('today_effort_coach_verdict');
  static const line = Key('today_effort_coach_line');
  static const rule = Key('today_effort_coach_rule');
  static const note = Key('today_effort_coach_note');
}

String coachVerdictLabel(AppLocalizations l10n, CoachVerdict verdict) =>
    switch (verdict) {
      CoachVerdict.push => l10n.effortCoachPush,
      CoachVerdict.maintain => l10n.effortCoachMaintain,
      CoachVerdict.recover => l10n.effortCoachRecover,
    };

String coachNote(AppLocalizations l10n, CoachVerdict verdict) =>
    switch (verdict) {
      CoachVerdict.push => l10n.effortCoachNotePush,
      CoachVerdict.maintain => l10n.effortCoachNoteMaintain,
      CoachVerdict.recover => l10n.effortCoachNoteRecover,
    };

String coachLine(
  AppLocalizations l10n,
  CoachRule rule, {
  required bool covered,
}) => switch (rule) {
  CoachRule.sick => l10n.effortCoachLineSick,
  CoachRule.lowReadiness => l10n.effortCoachLineLowReadiness,
  CoachRule.hardRun => l10n.effortCoachLineHardRun,
  CoachRule.noEasyDay => l10n.effortCoachLineNoEasyDay,
  CoachRule.fairReadiness => l10n.effortCoachLineFairReadiness,
  CoachRule.spike => l10n.effortCoachLineSpike,
  CoachRule.hardYesterday => l10n.effortCoachLineHardYesterday,
  CoachRule.goodReadiness when covered => l10n.effortCoachLineCovered,
  CoachRule.goodReadiness => l10n.effortCoachLineGoodReadiness,
  CoachRule.noReadiness => l10n.effortCoachLineNoReadiness,
};

/// The numbers the rule that fired read, in one or two sentences.
String coachWhy(MetricFormat format, EffortCoachCard card) {
  final l10n = format.l10n;
  final advice = card.advice;
  String whole(num? value) => format.integer((value ?? 0).round());
  final readiness = whole(card.readiness);
  final hardFrom = whole(advice.hardFrom);
  final yesterday = whole(advice.yesterdayLoad);
  return switch (advice.rule) {
    CoachRule.sick => l10n.effortCoachWhySick,
    CoachRule.lowReadiness => l10n.effortCoachWhyLowReadiness(
      readiness,
      whole(readinessFairFrom),
    ),
    CoachRule.hardRun => l10n.effortCoachWhyHardRun(
      whole(advice.hardDays),
      hardFrom,
    ),
    CoachRule.noEasyDay => l10n.effortCoachWhyNoEasyDay(
      whole(effortEasyFraction * (advice.chronic ?? 0)),
      whole(advice.daysSinceEasy),
    ),
    CoachRule.fairReadiness => l10n.effortCoachWhyFairReadiness(
      readiness,
      whole(readinessFairFrom),
      whole(readinessGoodFrom - 1),
    ),
    CoachRule.spike => l10n.effortCoachWhySpike(
      whole(advice.acute),
      whole(advice.chronicWeekAgo),
    ),
    CoachRule.hardYesterday => l10n.effortCoachWhyHardYesterday(
      yesterday,
      hardFrom,
    ),
    CoachRule.goodReadiness when advice.hardFrom == null =>
      l10n.effortCoachWhyGoodWaiting(
        readiness,
        whole(readinessGoodFrom),
        whole(effortMinLoadDays),
      ),
    CoachRule.goodReadiness => l10n.effortCoachWhyGoodNotHard(
      readiness,
      whole(readinessGoodFrom),
      yesterday,
      hardFrom,
    ),
    CoachRule.noReadiness => l10n.effortCoachWhyNoReadiness,
  };
}

IconData _icon(CoachVerdict verdict) => switch (verdict) {
  CoachVerdict.push => Icons.trending_up_rounded,
  CoachVerdict.maintain => Icons.trending_flat_rounded,
  CoachVerdict.recover => Icons.spa_rounded,
};

class EffortCoachSlot extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(effortEnabledProvider)) return const SizedBox.shrink();
    final card = ref.watch(effortCoachCardProvider).value;
    if (card == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: cardGap),
      child: EffortCoachCardView(
        card: card,
        onTap: () => context.go(AppPaths.effort),
      ),
    );
  }
}

class EffortCoachCardView extends StatelessWidget {
  const new({required this.card, this.onTap, super.key});

  final EffortCoachCard card;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    final theme = Theme.of(context).textTheme;
    final rule = card.advice.rule;
    return MetricCard(
      key: EffortCoachKeys.card,
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.effortCoachTitle,
            style: theme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.strongBorder, width: 1.5),
                  ),
                  child: Icon(_icon(rule.verdict), color: colors.textPrimary),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coachVerdictLabel(l10n, rule.verdict),
                      key: EffortCoachKeys.verdict,
                      style: theme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      coachLine(l10n, rule, covered: card.covered),
                      key: EffortCoachKeys.line,
                      style: theme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceInner,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text.rich(
              key: EffortCoachKeys.rule,
              TextSpan(
                children: [
                  TextSpan(
                    text: l10n.effortCoachRuleFired(
                      format.integer(rule.number),
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(text: ' '),
                  TextSpan(text: coachWhy(format, card)),
                ],
              ),
              style: theme.bodySmall?.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(height: 10),
          CaptionText(coachNote(l10n, rule.verdict), key: EffortCoachKeys.note),
        ],
      ),
    );
  }
}
