import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ai/application/vision_probe_controller.dart';
import 'package:open_ring/features/ai/application/vision_probe_runner.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/presentation/ai_failure_message.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class AiVisionTestKeys {
  static const card = Key('ai_vision_test_card');
  static const run = Key('ai_vision_test_run');
  static const running = Key('ai_vision_test_running');
  static const cancel = Key('ai_vision_test_cancel');
  static const result = Key('ai_vision_test_result');
}

/// The runner draws the grid at random and never returns it, so the card
/// describes the test instead of showing an image that was not sent.
class AiVisionTestCard extends ConsumerWidget {
  const new({required this.config, required this.locked, super.key});

  final AiConfig config;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final probe = ref.watch(visionProbeControllerProvider);
    final controller = ref.read(visionProbeControllerProvider.notifier);
    final line = _resultLine(l10n, probe);
    final tested = line != null;
    return MetricCard(
      key: AiVisionTestKeys.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BodyText(l10n.aiPhotosVisionBody),
          const SizedBox(height: 8),
          CaptionText(l10n.aiPhotosVisionChance),
          const SizedBox(height: 12),
          if (probe.running)
            _running(l10n, controller)
          else
            OutlinedButton(
              key: AiVisionTestKeys.run,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: locked ? null : () => unawaited(controller.run()),
              child: Text(tested ? l10n.aiTestAgain : l10n.aiPhotosVisionTest),
            ),
          if (line != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: BodyText(key: AiVisionTestKeys.result, line),
            ),
          ],
        ],
      ),
    );
  }

  Widget _running(AppLocalizations l10n, VisionProbeController controller) {
    final host = config.normalizedUrl?.asciiHost ?? config.baseUrl;
    return Row(
      key: AiVisionTestKeys.running,
      children: [
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Expanded(child: BodyText(l10n.aiPhotosVisionRunning(host))),
        TextButton(
          key: AiVisionTestKeys.cancel,
          onPressed: controller.cancel,
          child: Text(l10n.settingsDeleteCancel),
        ),
      ],
    );
  }

  String? _resultLine(AppLocalizations l10n, VisionProbeState probe) {
    final failure = probe.failure;
    if (failure != null) {
      final target = config.copyWith(model: aiPhotoTarget(config));
      return aiFailureMessage(l10n, failure, target);
    }
    return switch (probe.result) {
      null => null,
      AiVisionSupport.unknown => l10n.aiPhotosVisionUnreadable,
      final AiVisionSupport seen => l10n.aiPhotosVisionState(
        seen.name,
        aiPhotoTarget(config),
      ),
    };
  }
}
