import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/goals/application/goal_intake_providers.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goals_gate.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class GoalPickKeys {
  static const none = Key('goal_pick_none');
  static const loseFat = Key('goal_pick_lose_fat');
  static const getFitter = Key('goal_pick_get_fitter');
  static const sleepBetter = Key('goal_pick_sleep_better');
  static const continueButton = Key('goal_pick_continue');
  static const note = Key('goal_pick_note');
}

/// The one action under the rows, with its caption and what it does.
typedef _Action = ({String label, String? note, VoidCallback? onPressed});

class GoalPickScreen extends ConsumerStatefulWidget {
  const new({this.initial, super.key});

  final GoalKind? initial;

  @override
  ConsumerState<GoalPickScreen> createState() => _GoalPickScreenState();
}

class _GoalPickScreenState extends ConsumerState<GoalPickScreen> {
  late GoalKind? _choice = widget.initial;
  var _starting = false;
  var _failed = false;
  var _alreadyActive = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final on = ref.watch(goalsEnabledProvider);
    return AppPage(
      title: l10n.goalsPickTitle,
      subtitle: on ? l10n.goalsPickLead : null,
      children: on ? [_Short(children: _content(l10n))] : const [],
    );
  }

  List<Widget> _content(AppLocalizations l10n) {
    final active = ref.watch(activeGoalProvider);
    if (active.hasError) return [BodyText(l10n.metricLoadError)];
    if (!active.hasValue) return const [SizedBox(height: 96)];
    if (active.value != null || _alreadyActive) {
      return [BodyText(l10n.goalsPickActive)];
    }
    final modules = ref.watch(enabledModulesProvider).value ?? const {};
    final bodyOn = modules.contains(ModuleId.body);
    final action = _action(l10n, bodyOn: bodyOn);
    final note = action.note;
    return [
      MetricCard(
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: l10n.goalsPickGroup,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _row(GoalPickKeys.none, null, l10n.goalsPickNone, [
                l10n.goalsPickNoneDetail,
              ]),
              _row(
                GoalPickKeys.loseFat,
                GoalKind.loseFat,
                l10n.goalsPickLoseFat,
                [
                  l10n.goalsPickLoseFatDetail,
                  if (bodyOn)
                    l10n.goalsPickUsesBody
                  else
                    l10n.goalsPickNeedsBody,
                ],
                dim: !bodyOn,
              ),
              _row(
                GoalPickKeys.getFitter,
                GoalKind.getFitter,
                l10n.goalsPickGetFitter,
                [l10n.goalsPickGetFitterDetail],
              ),
              _row(
                GoalPickKeys.sleepBetter,
                GoalKind.sleepBetter,
                l10n.goalsPickSleepBetter,
                [l10n.goalsPickSleepBetterDetail],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      ActionButton(
        buttonKey: GoalPickKeys.continueButton,
        label: action.label,
        onPressed: action.onPressed,
      ),
      if (_failed) ...[
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: CaptionText(
            l10n.goalsStartFailed,
            textAlign: TextAlign.center,
          ),
        ),
      ],
      if (note != null) ...[
        const SizedBox(height: 8),
        CaptionText(note, key: GoalPickKeys.note, textAlign: TextAlign.center),
      ],
    ];
  }

  Widget _row(
    Key key,
    GoalKind? kind,
    String title,
    List<String> lines, {
    bool dim = false,
  }) => _Option(
    key: key,
    title: title,
    lines: lines,
    dim: dim,
    selected: _choice == kind,
    onTap: () => setState(() {
      _choice = kind;
      _failed = false;
    }),
  );

  _Action _action(AppLocalizations l10n, {required bool bodyOn}) {
    final choice = _choice;
    if (choice == GoalKind.loseFat && !bodyOn) {
      return (
        label: l10n.goalsPickOpenBody,
        note: l10n.goalsPickBodyNote,
        onPressed: () => context.go(AppPaths.settingsModuleBody),
      );
    }
    if (choice == null) {
      return (
        label: l10n.goalsPickContinueNone,
        note: l10n.goalsPickNoteNone,
        onPressed: () => context.go(AppTab.today.path),
      );
    }
    if (choice != GoalKind.loseFat) {
      return (
        label: l10n.goalsPickContinue,
        note: l10n.goalsPickNoteOther,
        onPressed: _starting ? null : () => unawaited(_start(choice)),
      );
    }
    final facts = ref.watch(intakeFactsProvider).value;
    final _Action closed = (
      label: l10n.goalsPickContinue,
      note: null,
      onPressed: null,
    );
    if (facts == null) return closed;
    return switch (pickStep(choice, facts)) {
      PickBlocked(:final block) => (
        label: l10n.goalsPickContinue,
        note: null,
        onPressed: () => context.go(AppPaths.goalsRefusedFor(block)),
      ),
      PickWeight(next: IntakeNext.screening) => (
        label: l10n.goalsPickContinue,
        note: l10n.goalsPickNoteWeight,
        onPressed: () => context.go(AppPaths.goalsScreening),
      ),
      _ => closed,
    };
  }

  Future<void> _start(GoalKind kind) async {
    setState(() {
      _starting = true;
      _failed = false;
    });
    final controller = ref.read(goalStartControllerProvider);
    try {
      final goal = await controller.startWithoutWeight(kind);
      if (!mounted) return;
      if (goal == null) {
        setState(() => _alreadyActive = true);
        return;
      }
      context.go(AppTab.today.path);
    } on Object {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _failed = true;
      });
    }
  }
}

class _Option extends StatelessWidget {
  const new({
    required this.title,
    required this.lines,
    required this.selected,
    required this.onTap,
    this.dim = false,
    super.key,
  });

  final String title;
  final List<String> lines;
  final bool selected;
  final bool dim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: [title, ...lines].join('. '),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? colors.textPrimary : colors.textLabel,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: dim ? colors.textLabel : null,
                        ),
                      ),
                      for (final line in lines) ...[
                        const SizedBox(height: 2),
                        CaptionText(line),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// One child, so the list builds the action under the rows even off screen.
class _Short extends StatelessWidget {
  const new({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  );
}
