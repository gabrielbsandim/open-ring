import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/goal_reword_controller.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_consent_scope.dart';
import 'package:open_ring/features/ai/domain/ai_report_models.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/presentation/ai_consent_sheet.dart';
import 'package:open_ring/features/ai/presentation/ai_failure_message.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/open_score/presentation/day_tag_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class GoalRewordKeys {
  static const card = Key('goal_reword_card');
  static const send = Key('goal_reword_send');
  static const sending = Key('goal_reword_sending');
  static const cancel = Key('goal_reword_cancel');
  static const shown = Key('goal_reword_shown');
  static const rule = Key('goal_reword_rule');
  static const record = Key('goal_reword_record');
  static const dropped = Key('goal_reword_dropped');
  static const failed = Key('goal_reword_failed');
}

/// The optional "Reword with AI" card under a review decision. It never
/// sends by itself, and shows nothing with AI off, not ready or in demo.
class GoalRewordCard extends ConsumerStatefulWidget {
  const new({required this.payload, super.key});

  final BuiltAiPayload payload;

  @override
  ConsumerState<GoalRewordCard> createState() => _GoalRewordCardState();
}

class _GoalRewordCardState extends ConsumerState<GoalRewordCard> {
  bool _ruleOpen = false;

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(aiEnabledProvider) || ref.watch(demoModeProvider)) {
      return const SizedBox.shrink();
    }
    final ready = ref.watch(aiAvailabilityProvider).value;
    final config = ref.watch(aiConfigProvider).value;
    if (ready != AiAvailability.ready || config == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(goalRewordControllerProvider);
    final mine = state.key == widget.payload.cacheKey
        ? state
        : const GoalRewordIdle();
    return Padding(
      key: GoalRewordKeys.card,
      padding: const EdgeInsets.only(top: cardGap),
      child: switch (mine) {
        GoalRewordShown(:final text, :final model) => _shown(l10n, text, model),
        GoalRewordDropped(:final reason, :final model) => _dropped(
          l10n,
          reason,
          model,
        ),
        GoalRewordSending() => _sending(l10n, config),
        GoalRewordFailed(:final failure) => _offer(
          l10n,
          config,
          aiFailureMessage(l10n, failure, config),
        ),
        GoalRewordIdle() => _offer(l10n, config, null),
      },
    );
  }

  Widget _offer(AppLocalizations l10n, AiConfig config, String? failure) {
    final host = config.normalizedUrl?.asciiHost ?? '';
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          CaptionText(l10n.goalsRewordOptional),
          Text(
            l10n.goalsRewordTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          BodyText(l10n.goalsRewordInfo),
          if (failure != null) BodyText(failure, key: GoalRewordKeys.failed),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(
              key: GoalRewordKeys.send,
              onPressed: () => unawaited(_send(config)),
              child: Text(
                failure == null ? l10n.goalsRewordTitle : l10n.syncRetry,
              ),
            ),
          ),
          CaptionText(l10n.goalsRewordSends(host)),
        ],
      ),
    );
  }

  Widget _sending(AppLocalizations l10n, AiConfig config) => MetricCard(
    key: GoalRewordKeys.sending,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        BodyText(
          l10n.goalsRewordSending(config.normalizedUrl?.asciiHost ?? ''),
        ),
        const LinearProgressIndicator(),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton(
            key: GoalRewordKeys.cancel,
            onPressed: ref.read(goalRewordControllerProvider.notifier).cancel,
            child: Text(l10n.settingsDeleteCancel),
          ),
        ),
      ],
    ),
  );

  Widget _shown(AppLocalizations l10n, String text, String model) {
    final colors = AppColors.of(context);
    return CustomPaint(
      key: GoalRewordKeys.shown,
      painter: DashedBorderPainter(color: colors.strongBorder, radius: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            CaptionText(l10n.goalsRewordBy(model)),
            BodyText(text),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: GoalRewordKeys.rule,
                onPressed: () => setState(() => _ruleOpen = !_ruleOpen),
                child: Text(
                  _ruleOpen
                      ? l10n.goalsRewordHideRule
                      : l10n.goalsRewordSeeRule,
                ),
              ),
            ),
            if (_ruleOpen)
              CaptionText(l10n.goalsRewordRecord, key: GoalRewordKeys.record),
          ],
        ),
      ),
    );
  }

  Widget _dropped(
    AppLocalizations l10n,
    AiCardDropReason reason,
    String model,
  ) => MetricCard(
    key: GoalRewordKeys.dropped,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Text(
          l10n.goalsRewordDropped,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        BodyText(
          reason == AiCardDropReason.unverifiedNumber
              ? l10n.goalsRewordDroppedNumber(model)
              : l10n.goalsRewordDroppedOther(model),
        ),
      ],
    ),
  );

  // Nothing leaves the phone before a consent that covers this payload, the
  // goals category included.
  Future<void> _send(AiConfig config) async {
    final consent = await ref.read(aiConsentProvider.future);
    if (!mounted) return;
    final payload = widget.payload;
    final granted =
        aiConsentCoversPayload(consent, config, payload) ||
        await showAiConsentSheet(
          context,
          config: config,
          payload: payload,
          previous: consent,
        );
    if (!granted || !mounted) return;
    await ref.read(goalRewordControllerProvider.notifier).send(payload);
  }
}
