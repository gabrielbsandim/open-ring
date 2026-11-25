import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/vision_probe_controller.dart';
import 'package:open_ring/features/ai/application/vision_probe_runner.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/food/presentation/meal_photo_consent_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

const Set<EnqueueOutcome> _goesOn = {
  EnqueueOutcome.queued,
  EnqueueOutcome.cached,
  EnqueueOutcome.keptOnPhone,
  EnqueueOutcome.noPhoto,
};

/// Sends [mealIds] to the queue on a tap. The consent and probe steps run
/// once, for the first meal; the rest are enqueued without a sheet and stop
/// at the daily limit, and a batch reports how many it queued.
Future<void> analyzeMealPhotos(
  BuildContext context,
  WidgetRef ref,
  List<int> mealIds,
) async {
  if (mealIds.isEmpty) return;
  final queue = ref.read(mealAnalysisQueueProvider.notifier);
  final config = await ref.read(aiConfigProvider.future);
  final vision = await ref.read(aiPhotoVisionProvider.future);
  if (!context.mounted) return;
  // A model that cannot see is never offered a consent to send to it.
  if (vision == AiVisionSupport.no) {
    _textOnly(context, config);
    return;
  }
  final first = mealIds.first;
  var outcome = await queue.enqueue(first);
  if (!context.mounted) return;
  if (outcome == EnqueueOutcome.noPhotoConsent ||
      outcome == EnqueueOutcome.visionUntested) {
    final granted = await showMealPhotoConsentSheet(
      context,
      MealPhotoConsentSheet(
        config: config,
        mealId: first,
        consent: outcome == EnqueueOutcome.noPhotoConsent,
        probe: vision == AiVisionSupport.unknown,
      ),
    );
    if (!granted || !context.mounted) return;
    outcome = await queue.enqueue(first);
    if (!context.mounted) return;
  }
  if (mealIds.length == 1 || !_goesOn.contains(outcome)) {
    _report(context, config, outcome);
    return;
  }
  var queued = outcome == EnqueueOutcome.queued ? 1 : 0;
  var limited = false;
  for (final id in mealIds.skip(1)) {
    final next = await queue.enqueue(id);
    if (next == EnqueueOutcome.queued) queued++;
    limited = next == EnqueueOutcome.dailyLimit;
    if (limited) break;
  }
  if (context.mounted) _reportBatch(context, config, queued, limited: limited);
}

void _reportBatch(
  BuildContext context,
  AiConfig config,
  int queued, {
  required bool limited,
}) {
  final l10n = AppLocalizations.of(context);
  if (queued == 0 && limited) {
    _report(context, config, EnqueueOutcome.dailyLimit);
    return;
  }
  if (queued == 0) return;
  final text = limited
      ? l10n.foodAiBatchPartial(queued)
      : l10n.foodAiBatchQueued(queued);
  _snack(context, text);
}

void _report(BuildContext context, AiConfig config, EnqueueOutcome outcome) {
  final l10n = AppLocalizations.of(context);
  switch (outcome) {
    case EnqueueOutcome.queued:
      _snack(context, l10n.foodAiQueued);
    case EnqueueOutcome.dailyLimit:
      _snack(context, l10n.foodAiLimit(config.photoDailyLimit));
    case EnqueueOutcome.visionNo:
      _textOnly(context, config);
    case EnqueueOutcome.unavailable:
      _snack(context, l10n.foodAiUnavailable, (
        label: l10n.aiGuideOpen,
        path: AppPaths.settingsAiConnection,
      ));
    case _:
      break;
  }
}

void _textOnly(BuildContext context, AiConfig config) {
  final l10n = AppLocalizations.of(context);
  _snack(context, l10n.foodAiProbeTextOnly(aiPhotoTarget(config)), (
    label: l10n.foodAiOpenPhotos,
    path: AppPaths.settingsAiPhotos,
  ));
}

void _snack(
  BuildContext context,
  String text, [
  ({String label, String path})? link,
]) {
  final router = GoRouter.maybeOf(context);
  final action = link == null || router == null
      ? null
      : SnackBarAction(
          label: link.label,
          onPressed: () => unawaited(router.push(link.path)),
        );
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text), action: action));
}
