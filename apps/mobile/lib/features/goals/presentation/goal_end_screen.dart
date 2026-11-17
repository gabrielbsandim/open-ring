import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/goals/application/goal_ender.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goals_gate.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_end.dart';
import 'package:open_ring/features/goals/presentation/goal_week_card.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class GoalEndKeys {
  static const switchGoal = Key('goal_end_switch');
  static const endGoal = Key('goal_end_end');
  static const keep = Key('goal_end_keep');
  static const goBack = Key('goal_end_go_back');
  static const confirm = Key('goal_end_confirm');
  static const cancel = Key('goal_end_cancel');
  static const retry = Key('goal_end_retry');
  static const notice = Key('goal_end_notice');
  static const failed = Key('goal_end_failed');
}

class GoalEndScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<GoalEndScreen> createState() => _GoalEndScreenState();
}

class _GoalEndScreenState extends ConsumerState<GoalEndScreen> {
  GoalEndReason? _asking;
  StepGoalRaise? _raise;
  var _busy = false;
  int? _failedBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final on = ref.watch(goalsEnabledProvider);
    return AppPage(
      title: l10n.goalsEndTitle,
      children: on ? [_Short(children: _content(l10n))] : const [],
    );
  }

  List<Widget> _content(AppLocalizations l10n) {
    final failedBack = _failedBack;
    if (failedBack != null) return _failed(l10n, failedBack);
    final active = ref.watch(activeGoalProvider);
    if (active.hasError) return [BodyText(l10n.metricLoadError)];
    if (!active.hasValue) return const [SizedBox(height: 96)];
    final goal = active.value;
    if (goal == null) return [BodyText(l10n.goalsScreenNoGoalBody)];
    final raise = ref.watch(goalEndRaiseProvider);
    if (!raise.hasValue && !raise.hasError) {
      return const [SizedBox(height: 96)];
    }
    final asking = _asking;
    return [
      BodyText(l10n.goalsEndLead(goalKindName(l10n, goal.kind))),
      const SizedBox(height: 12),
      if (asking == null)
        ..._choices(l10n, raise.value)
      else
        _confirm(l10n, asking),
    ];
  }

  List<Widget> _choices(AppLocalizations l10n, StepGoalRaise? raise) {
    final format = MetricFormat.of(context);
    return [
      MetricCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Tile(
              key: GoalEndKeys.switchGoal,
              icon: Icons.flag_outlined,
              title: l10n.goalsEndSwitch,
              body: l10n.goalsEndSwitchBody,
              onTap: () => _ask(GoalEndReason.switched, raise),
            ),
            _Tile(
              key: GoalEndKeys.endGoal,
              icon: Icons.check_circle_outline,
              title: l10n.goalsEndEnd,
              body: l10n.goalsEndEndBody,
              onTap: () => _ask(GoalEndReason.person, raise),
            ),
          ],
        ),
      ),
      if (raise != null) ...[
        const SizedBox(height: 12),
        MetricCard(
          key: GoalEndKeys.notice,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.directions_walk),
              const SizedBox(width: 12),
              Expanded(
                child: BodyText(
                  l10n.goalsEndNotice(
                    format.integer(raise.from),
                    format.integer(raise.to),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 12),
      CaptionText(l10n.goalsEndFoot),
    ];
  }

  Widget _confirm(AppLocalizations l10n, GoalEndReason reason) {
    final format = MetricFormat.of(context);
    final theme = Theme.of(context);
    final raise = _raise;
    final switching = reason == GoalEndReason.switched;
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              switching
                  ? l10n.goalsEndConfirmSwitchTitle
                  : l10n.goalsEndConfirmEndTitle,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 6),
          BodyText(l10n.goalsEndConfirmBody),
          if (raise == null) ...[
            const SizedBox(height: 14),
            ActionButton(
              buttonKey: GoalEndKeys.confirm,
              label: switching ? l10n.goalsEndSwitch : l10n.goalsEndEnd,
              onPressed: _busy ? null : () => unawaited(_finish(reason)),
            ),
          ] else ...[
            const SizedBox(height: 6),
            BodyText(l10n.goalsEndConfirmAsk),
            const SizedBox(height: 14),
            ActionButton(
              buttonKey: GoalEndKeys.keep,
              label: l10n.goalsEndKeep(format.integer(raise.to)),
              onPressed: _busy ? null : () => unawaited(_finish(reason)),
            ),
            const SizedBox(height: 10),
            SecondaryButton(
              buttonKey: GoalEndKeys.goBack,
              label: l10n.goalsEndBack(format.integer(raise.from)),
              onPressed: _busy
                  ? null
                  : () => unawaited(_finish(reason, back: raise.from)),
            ),
            const SizedBox(height: 10),
            CaptionText(
              l10n.goalsEndRaisedNote(
                format.integer(raise.from),
                format.integer(raise.to),
              ),
            ),
          ],
          const SizedBox(height: 4),
          TextButton(
            key: GoalEndKeys.cancel,
            onPressed: _busy ? null : () => setState(() => _asking = null),
            child: Text(l10n.goalsEndCancel),
          ),
        ],
      ),
    );
  }

  List<Widget> _failed(AppLocalizations l10n, int steps) => [
    Semantics(
      liveRegion: true,
      child: BodyText(
        l10n.goalsEndFailed(MetricFormat.of(context).integer(steps)),
        key: GoalEndKeys.failed,
      ),
    ),
    const SizedBox(height: 14),
    ActionButton(
      buttonKey: GoalEndKeys.retry,
      label: l10n.goalsReviewRetry,
      onPressed: _busy ? null : () => unawaited(_retry(steps)),
    ),
  ];

  // The raise is kept from the tap: once the goal ends it can no longer be
  // read, and the retry still needs it.
  void _ask(GoalEndReason reason, StepGoalRaise? raise) => setState(() {
    _asking = reason;
    _raise = raise;
  });

  Future<void> _finish(GoalEndReason reason, {int? back}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final outcome = await ref
        .read(goalEnderProvider.notifier)
        .end(reason, stepGoalBack: back);
    if (!mounted) return;
    switch (outcome) {
      case GoalEndOutcome.ended:
        _leave(reason);
      case GoalEndOutcome.stepGoalFailed:
        setState(() {
          _busy = false;
          _failedBack = back;
        });
      case GoalEndOutcome.refused:
        setState(() {
          _busy = false;
          _asking = null;
        });
    }
  }

  Future<void> _retry(int steps) async {
    if (_busy) return;
    setState(() => _busy = true);
    final done = await ref
        .read(goalEnderProvider.notifier)
        .retryStepGoalBack(steps);
    if (!mounted) return;
    if (!done) {
      setState(() => _busy = false);
      return;
    }
    _leave(_asking ?? GoalEndReason.person);
  }

  void _leave(GoalEndReason reason) {
    if (reason == GoalEndReason.switched) {
      context.pushReplacement(AppPaths.goalsPick);
      return;
    }
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppPaths.goals);
  }
}

class _Tile extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      button: true,
      label: '$title. $body',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              children: [
                Icon(icon, color: colors.textLabel),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      CaptionText(body),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.textLabel),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// One child, so the list builds the confirm buttons even off screen.
class _Short extends StatelessWidget {
  const new({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  );
}
