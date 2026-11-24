import 'dart:async';

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
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/application/step_goal_history_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/health_context_providers.dart';
import 'package:open_ring/features/ai/domain/goal_reword.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/presentation/goal_reword_card.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_reviewer.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/review_step_goal.dart';
import 'package:open_ring/features/goals/presentation/goal_evidence_sheet.dart';
import 'package:open_ring/features/goals/presentation/goal_sheets.dart';
import 'package:open_ring/features/goals/presentation/goal_week_card.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

const _daysInWeek = 7;

abstract final class GoalReviewScreenKeys {
  static const none = Key('goal_review_none');
  static const hold = Key('goal_review_hold');
  static const week = Key('goal_review_week');
  static const rate = Key('goal_review_rate');
  static const checkIn = Key('goal_review_check_in');
  static const send = Key('goal_review_send');
  static const decision = Key('goal_review_decision');
  static const why = Key('goal_review_why');
  static const accept = Key('goal_review_accept');
  static const keep = Key('goal_review_keep');
  static const steps = Key('goal_review_steps');
  static const answered = Key('goal_review_answered');
  static const failed = Key('goal_review_failed');
  static const retry = Key('goal_review_retry');
  static const refused = Key('goal_review_refused');
  static const demo = Key('goal_review_demo');

  static Key energy(CheckInEnergy energy) =>
      Key('goal_review_energy_${energy.name}');
  static Key food({required bool yes}) => Key('goal_review_food_$yes');
}

/// The review of the newest reviewed week: how it went, two optional
/// questions, and the decision with its answer.
class GoalReviewScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<GoalReviewScreen> createState() => _GoalReviewScreenState();
}

class _GoalReviewScreenState extends ConsumerState<GoalReviewScreen> {
  CheckInEnergy? _energy;
  bool? _food;
  bool _busy = false;
  int? _failedSteps;
  bool _refused = false;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final title = l10n.goalsReviewTitle;
    final state = ref.watch(goalWeekProvider).value;
    final view = ref.watch(goalReviewProvider).value;
    if (state == null) return AppPage(title: title, children: const []);
    if (state is GoalWeekHold) {
      return AppPage(
        title: title,
        children: [
          BodyText(l10n.goalsWeekHold, key: GoalReviewScreenKeys.hold),
        ],
      );
    }
    if (view == null || state is GoalWeekOff || state is GoalWeekNoGoal) {
      return AppPage(
        title: title,
        children: [
          BodyText(l10n.goalsReviewNone, key: GoalReviewScreenKeys.none),
        ],
      );
    }
    final week = view.week;
    final reviewed = week.monday.addDays(-_daysInWeek);
    final lead = week.answer == null
        ? l10n.goalsReviewLead
        : l10n.goalsReviewLeadDone;
    final demo = ref.watch(demoModeProvider);
    return AppPage(
      title: title,
      subtitle: lead(
        week.inputs.week - 1,
        format.monthDay(reviewed),
        format.monthDay(week.monday.addDays(-1)),
      ),
      children: [
        if (demo) ...[
          CaptionText(l10n.goalsReviewDemo, key: GoalReviewScreenKeys.demo),
          const SizedBox(height: cardGap),
        ],
        if (week.inputs.levers.isNotEmpty) ...[
          _WeekCard(week: week, format: format),
          const SizedBox(height: cardGap),
        ],
        if (_takesCheckIn(state, week, demo: demo)) ...[
          _checkIn(l10n, week),
          const SizedBox(height: cardGap),
        ],
        _decision(context, format, view, answerable: _answerable(state, week)),
        if (_rewordPayload(format, view) case final payload?)
          GoalRewordCard(payload: payload),
        const SizedBox(height: 16),
        CaptionText(l10n.goalsReviewFoot),
      ],
    );
  }

  // Only the week the read model still waits on takes an answer, so a week of
  // an earlier block, a held weight goal or demo mode show no buttons.
  bool _answerable(GoalWeekView state, GoalWeek week) {
    if (ref.read(demoModeProvider) || state is! GoalWeekRunning) return false;
    return state.review?.monday == week.monday;
  }

  BuiltAiPayload? _rewordPayload(MetricFormat format, GoalReviewView view) {
    if (!ref.watch(aiEnabledProvider)) return null;
    final week = view.week;
    final change = week.change;
    final levers = week.inputs.levers;
    final (head, line) = _words(format, week, view.review);
    final pause = week.action == ReviewAction.pause;
    return buildGoalRewordPayload(
      replyLanguage: aiLanguageTag(Localizations.localeOf(context)),
      rule: week.rule.number,
      head: head,
      line: line,
      change: change,
      changeText: change == null
          ? null
          : '${leverName(format.l10n, change.kind)}: ${_fromTo(format, change)}',
      fit: levers.isEmpty ? null : levers.where(leverFits).length,
      levers: levers.isEmpty ? null : levers.length,
      pauseDays: pause ? view.review.pauseDays : null,
    );
  }

  bool _takesCheckIn(GoalWeekView state, GoalWeek week, {required bool demo}) {
    if (demo || week.answer != null) return false;
    if (week.inputs.energy != null || week.inputs.foodOrWeight != null) {
      return false;
    }
    if (state is GoalWeekRecovery) return state.monday == week.monday;
    if (state is GoalWeekRunning) return state.monday == week.monday;
    return false;
  }

  Widget _checkIn(AppLocalizations l10n, GoalWeek week) {
    final chosen = _energy != null || _food != null;
    return MetricCard(
      key: GoalReviewScreenKeys.checkIn,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(
            title: l10n.goalsReviewCheckTitle,
            accent: AppColors.of(context).textPrimary,
          ),
          const SizedBox(height: 12),
          BodyText(l10n.goalsReviewEnergyQuestion),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (energy, label) in [
                (CheckInEnergy.low, l10n.goalsReviewEnergyLow),
                (CheckInEnergy.normal, l10n.goalsReviewEnergyNormal),
                (CheckInEnergy.good, l10n.goalsReviewEnergyGood),
              ])
                ChoiceChip(
                  key: GoalReviewScreenKeys.energy(energy),
                  label: Text(label),
                  selected: _energy == energy,
                  onSelected: (on) =>
                      setState(() => _energy = on ? energy : null),
                ),
            ],
          ),
          const SizedBox(height: 14),
          BodyText(l10n.goalsReviewFoodQuestion),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (yes, label) in [
                (false, l10n.goalsReviewNo),
                (true, l10n.goalsReviewYes),
              ])
                ChoiceChip(
                  key: GoalReviewScreenKeys.food(yes: yes),
                  label: Text(label),
                  selected: _food == yes,
                  onSelected: (on) => setState(() => _food = on ? yes : null),
                ),
            ],
          ),
          const SizedBox(height: 10),
          CaptionText(l10n.goalsReviewCheckNote),
          if (!week.pending) ...[
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton(
                key: GoalReviewScreenKeys.send,
                onPressed: chosen && !_busy ? () => _send(week) : null,
                child: Text(l10n.goalsReviewCheckSend),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _decision(
    BuildContext context,
    MetricFormat format,
    GoalReviewView view, {
    required bool answerable,
  }) {
    final l10n = format.l10n;
    final week = view.week;
    final change = week.change;
    final (head, line) = _words(format, week, view.review);
    final needs = change != null && answerable && week.answer == null;
    final profileGoal = ref.watch(stepGoalProvider);
    return MetricCard(
      key: GoalReviewScreenKeys.decision,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(head, style: Theme.of(context).textTheme.titleMedium),
          if (change != null) ...[
            const SizedBox(height: 8),
            CaptionText(leverName(l10n, change.kind)),
            Text(
              _fromTo(format, change),
              style: numberStyle(Theme.of(context).textTheme.titleMedium),
            ),
          ],
          const SizedBox(height: 8),
          BodyText(line),
          const SizedBox(height: 6),
          CaptionText(l10n.goalsReviewRule(week.rule.number)),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: GoalReviewScreenKeys.why,
              onPressed: () => unawaited(
                showGoalEvidence(
                  context,
                  copy: goalRuleCopy(format, week.rule),
                  yours: goalRuleYours(
                    format,
                    week.inputs,
                    hidden: ref.read(numbersHiddenProvider),
                  ),
                ),
              ),
              child: Text(l10n.goalsSheetRuleWhy),
            ),
          ),
          if (change != null && change.kind == LeverKind.steps)
            _steps(format, change, profileGoal),
          if (change == null) ...[
            const SizedBox(height: 10),
            CaptionText(
              week.rule.protection
                  ? l10n.goalsReviewProtection
                  : l10n.goalsReviewNoAnswer,
            ),
          ],
          if (needs) ...[
            const SizedBox(height: 14),
            ActionButton(
              buttonKey: GoalReviewScreenKeys.accept,
              label: l10n.goalsReviewAccept,
              onPressed: _busy
                  ? null
                  : () => _answer(week, WeekAnswer.accepted),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: GoalReviewScreenKeys.keep,
              onPressed: _busy
                  ? null
                  : () => _answer(week, WeekAnswer.declined),
              child: Text(l10n.goalsReviewKeep),
            ),
            const SizedBox(height: 10),
            CaptionText(l10n.goalsReviewKeepNote),
          ],
          if (week.answer case final answer?) ...[
            const SizedBox(height: 14),
            _answered(format, week, answer),
          ],
          if (_refused) ...[
            const SizedBox(height: 10),
            CaptionText(
              l10n.goalsReviewRefused,
              key: GoalReviewScreenKeys.refused,
            ),
          ],
        ],
      ),
    );
  }

  Widget _steps(MetricFormat format, LeverChange change, int profileGoal) {
    final l10n = format.l10n;
    if (change.to == null) return const SizedBox.shrink();
    final raised = stepGoalAfterAccept(change, profileGoal: profileGoal);
    if (raised == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: CaptionText(
          l10n.goalsReviewStepsKept(format.integer(profileGoal)),
          key: GoalReviewScreenKeys.steps,
        ),
      );
    }
    return Padding(
      key: GoalReviewScreenKeys.steps,
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.goalsReviewStepsHead,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          for (final item in [
            l10n.goalsReviewStepsProfile(format.integer(raised)),
            l10n.goalsReviewStepsScore,
            l10n.goalsReviewStepsPast,
          ]) ...[BodyText(item), const SizedBox(height: 4)],
        ],
      ),
    );
  }

  Widget _answered(MetricFormat format, GoalWeek week, WeekAnswer answer) {
    final l10n = format.l10n;
    final failed = _failedSteps ?? _unsaved(week, answer);
    return Column(
      key: GoalReviewScreenKeys.answered,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          answer == WeekAnswer.accepted
              ? l10n.goalsReviewAccepted
              : l10n.goalsReviewKept,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        CaptionText(
          l10n.goalsReviewNext(
            format.monthDay(week.monday.addDays(_daysInWeek)),
          ),
        ),
        if (failed != null) ...[
          const SizedBox(height: 10),
          BodyText(
            l10n.goalsReviewStepFailed,
            key: GoalReviewScreenKeys.failed,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: GoalReviewScreenKeys.retry,
            onPressed: _busy ? null : () => _retry(failed),
            child: Text(l10n.goalsReviewRetry),
          ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () => context.go(AppTab.today.path),
            child: Text(l10n.goalsReviewSeeToday),
          ),
        ),
      ],
    );
  }

  // The profile save dates its change row before it saves the profile, so a
  // row for the accepted target with the profile still under it is a save
  // that failed, even after the screen was left.
  int? _unsaved(GoalWeek week, WeekAnswer answer) {
    final change = week.change;
    final to = change?.to;
    if (answer != WeekAnswer.accepted || to == null) return null;
    if (change?.kind != LeverKind.steps) return null;
    final newest = ref.watch(stepGoalChangesProvider).value?.lastOrNull;
    if (newest == null || newest.steps != to) return null;
    return ref.watch(stepGoalProvider) < to ? to : null;
  }

  Future<void> _answer(GoalWeek week, WeekAnswer choice) async {
    setState(() => _busy = true);
    final outcome = await ref
        .read(goalReviewerProvider.notifier)
        .answer(week.monday, choice, energy: _energy, foodOrWeight: _food);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _refused = outcome == ReviewAnswerOutcome.refused;
      _failedSteps = outcome == ReviewAnswerOutcome.stepGoalFailed
          ? week.change?.to
          : null;
    });
  }

  Future<void> _send(GoalWeek week) async {
    setState(() => _busy = true);
    final review = await ref
        .read(goalReviewerProvider.notifier)
        .checkIn(week.monday, energy: _energy, foodOrWeight: _food);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _refused = review == null;
    });
  }

  Future<void> _retry(int steps) async {
    setState(() => _busy = true);
    final done = await ref
        .read(goalReviewerProvider.notifier)
        .retryStepGoal(steps);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failedSteps = done ? null : steps;
    });
  }
}

(String, String) _words(MetricFormat format, GoalWeek week, Review review) {
  final l10n = format.l10n;
  return switch (week.action) {
    ReviewAction.end => (l10n.goalsReviewEndHead, l10n.goalsReviewEndLine),
    ReviewAction.pause => (
      l10n.goalsReviewPauseHead,
      switch (review.pauseDays) {
        final days? => l10n.goalsReviewPauseLine(format.integer(days)),
        null => l10n.goalsReviewPauseOpen,
      },
    ),
    ReviewAction.recoveryWeek => (
      l10n.goalsWeekRecoveryTitle,
      l10n.goalsReviewRecoveryLine,
    ),
    ReviewAction.hold => (l10n.goalsReviewHoldHead, l10n.goalsReviewHoldLine),
    ReviewAction.ease => (l10n.goalsReviewEaseHead, l10n.goalsReviewEaseLine),
    ReviewAction.shrink => (
      l10n.goalsReviewChangeHead,
      l10n.goalsReviewShrinkLine,
    ),
    ReviewAction.nextStep => (
      l10n.goalsReviewChangeHead,
      week.rule == ReviewRule.stepSlow
          ? l10n.goalsReviewSlowLine
          : l10n.goalsReviewBuildLine,
    ),
  };
}

String _fromTo(MetricFormat format, LeverChange change) {
  final l10n = format.l10n;
  final from = change.from;
  final to = change.to;
  if (to == null) return l10n.goalsReviewRemove;
  final next = leverValue(format, change.kind, to);
  if (from == null) return l10n.goalsReviewNew(next);
  return l10n.goalsReviewFromTo(leverValue(format, change.kind, from), next);
}

class _WeekCard extends ConsumerWidget {
  const new({required this.week, required this.format});

  final GoalWeek week;
  final MetricFormat format;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    final levers = week.inputs.levers;
    final fit = levers.where(leverFits).length;
    final rate = week.inputs.rate;
    final hidden = ref.watch(numbersHiddenProvider);
    return MetricCard(
      key: GoalReviewScreenKeys.week,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(
            title: l10n.goalsReviewWeekTitle,
            accent: colors.textPrimary,
          ),
          for (final lever in levers)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: MergeSemantics(
                child: Row(
                  children: [
                    Icon(
                      leverFits(lever) ? Icons.check : Icons.remove,
                      size: 20,
                      color: colors.textLabel,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(leverName(l10n, lever.lever.kind))),
                    const SizedBox(width: 10),
                    Text(
                      l10n.goalsWeekCount(
                        format.integer(lever.achieved),
                        format.integer(leverNeed(lever.lever)),
                      ),
                      style: numberStyle(
                        Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          MetricRow(
            label: l10n.goalsReviewFit,
            value: l10n.goalsWeekCount(
              format.integer(fit),
              format.integer(levers.length),
            ),
          ),
          CaptionText(
            l10n.goalsReviewFitNote(format.integer(goalDailyFitDays)),
          ),
          if (week.inputs.kind == GoalKind.loseFat && rate != null && !hidden)
            Padding(
              key: GoalReviewScreenKeys.rate,
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MetricRow(
                    label: l10n.goalsReviewRate,
                    value: l10n.goalsReviewRateValue(
                      goalPercent(format, rate.percent),
                    ),
                  ),
                  CaptionText(
                    l10n.goalsReviewRateDetail(
                      goalPercent(format, rate.percentLow),
                      goalPercent(format, rate.percentHigh),
                      goalPercent(format, week.inputs.targetPercent),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
