import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class MealAiKeys {
  static const keep = Key('meal_ai_keep');
  static const analyze = Key('meal_ai_analyze');
}

enum MealSavedAction { analyze }

/// The flag goes first, so a pass that wins the race skips the row as kept;
/// then each queued row is cancelled, which gives its use back.
Future<void> setMealKeepOnPhone(
  WidgetRef ref,
  int mealId, {
  required bool keep,
}) async {
  final store = ref.read(mealAnalysisStoreProvider);
  final queue = ref.read(mealAnalysisQueueProvider.notifier);
  await store.setKeepOnPhone(mealId, keep: keep);
  if (!keep) return;
  final rows = await store.byMeal(mealId);
  final queued = rows.where((r) => r.status == MealAnalysisStatus.queued);
  for (final row in queued) {
    await queue.cancel(row.id);
  }
}

/// Off while the meal's photo is being sent: that request is already billed.
class MealKeepOnPhoneSwitch extends ConsumerWidget {
  const new({required this.mealId, super.key});

  final int mealId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final keep = ref.watch(mealKeepOnPhoneProvider(mealId)).value;
    final rows = ref.watch(mealAnalysesProvider(mealId)).value ?? const [];
    final sendingId = ref.watch(
      mealAnalysisQueueProvider.select((s) => s.sendingId),
    );
    final sending = rows.any(
      (r) => r.id == sendingId || r.status == MealAnalysisStatus.sending,
    );
    return SwitchListTile(
      key: MealAiKeys.keep,
      contentPadding: EdgeInsets.zero,
      value: keep ?? false,
      onChanged: keep == null || sending
          ? null
          : (on) => unawaited(setMealKeepOnPhone(ref, mealId, keep: on)),
      title: Text(l10n.foodAiKeepTitle),
      subtitle: Text(l10n.foodAiKeepHint),
    );
  }
}

/// The saved sheet's AI slot: the keep switch, and Analyze while keep is off.
class MealSavedAiSlot extends ConsumerWidget {
  const new({required this.mealId, super.key});

  final int mealId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final keep = ref.watch(mealKeepOnPhoneProvider(mealId)).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MealKeepOnPhoneSwitch(mealId: mealId),
        if (keep == false) ...[
          const SizedBox(height: 8),
          SecondaryButton(
            buttonKey: MealAiKeys.analyze,
            label: l10n.foodAiAnalyze,
            onPressed: () => Navigator.of(context).pop(MealSavedAction.analyze),
          ),
        ],
      ],
    );
  }
}
