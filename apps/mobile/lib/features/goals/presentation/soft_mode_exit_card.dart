import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/goals/application/goal_intake_providers.dart';
import 'package:open_ring/features/goals/application/goals_gate.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class SoftModeExitKeys {
  static const leave = Key('soft_mode_exit_leave');
  static const confirm = Key('soft_mode_exit_confirm');
  static const cancel = Key('soft_mode_exit_cancel');
  static const failed = Key('soft_mode_exit_failed');
}

/// The one place soft mode can be left, and only on the person's own tap.
class SoftModeExitCard extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SoftModeExitCard> createState() => _SoftModeExitCardState();
}

class _SoftModeExitCardState extends ConsumerState<SoftModeExitCard> {
  var _leaving = false;
  var _failed = false;

  @override
  Widget build(BuildContext context) {
    // Demo history shares the tables, and leaving writes nothing there.
    final on =
        ref.watch(goalsEnabledProvider) &&
        !ref.watch(demoModeProvider) &&
        (ref.watch(softModeProvider).value ?? false);
    if (!on) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            header: true,
            child: Text(
              l10n.goalsSoftExitTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 6),
          BodyText(l10n.goalsSoftExitBody),
          const SizedBox(height: 14),
          SecondaryButton(
            buttonKey: SoftModeExitKeys.leave,
            label: l10n.goalsSoftExitLeave,
            onPressed: _leaving ? null : () => unawaited(_ask()),
          ),
          if (_failed) ...[
            const SizedBox(height: 8),
            Semantics(
              key: SoftModeExitKeys.failed,
              liveRegion: true,
              child: CaptionText(
                l10n.goalsSoftExitFailed,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _ask() => showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _LeaveDialog(onConfirm: () => unawaited(_leave(dialogContext))),
  );

  Future<void> _leave(BuildContext dialogContext) async {
    // A second tap on the dialog can land before it closes.
    if (_leaving) return;
    _leaving = true;
    Navigator.of(dialogContext).pop();
    setState(() => _failed = false);
    try {
      final left = await ref.read(softModeControllerProvider).leave();
      if (!mounted) return;
      setState(() {
        _leaving = false;
        _failed = !left;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _leaving = false;
        _failed = true;
      });
    }
  }
}

class _LeaveDialog extends StatelessWidget {
  const new({required this.onConfirm});

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.goalsSoftExitConfirmTitle),
      content: Text(l10n.goalsSoftExitConfirmBody),
      actions: [
        TextButton(
          key: SoftModeExitKeys.cancel,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.goalsSoftExitCancel),
        ),
        FilledButton(
          key: SoftModeExitKeys.confirm,
          onPressed: onConfirm,
          child: Text(l10n.goalsSoftExitConfirm),
        ),
      ],
    );
  }
}
