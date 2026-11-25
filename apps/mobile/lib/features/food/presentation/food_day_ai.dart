import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/vision_probe_runner.dart';
import 'package:open_ring/features/ai/domain/meal_photo_prompt.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/food/application/food_day.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/food/application/meal_analysis_view.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/domain/meal_suggestion.dart';
import 'package:open_ring/features/food/presentation/meal_analyze_flow.dart';
import 'package:open_ring/features/food/presentation/meal_photo_pause_card.dart';
import 'package:open_ring/features/open_score/presentation/day_tag_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class FoodDayAiKeys {
  static const batch = Key('food_day_ai_batch');

  static Key badge(int mealId) => Key('food_day_ai_badge_$mealId');
}

/// Every analysis row of one meal, the latest first, and its keep switch.
typedef FoodDayAnalysis = ({List<MealAnalysis> rows, bool keep});

/// The analyses of one day's photo meals, by meal id.
final FutureProviderFamily<Map<int, FoodDayAnalysis>, LocalDate>
foodDayAnalysesProvider = FutureProvider.family((ref, day) async {
  final meals = await ref.watch(foodDayMealsProvider(day).future);
  return {
    for (final meal in meals)
      if (meal.photo != null)
        meal.id: (
          rows: await ref.watch(mealAnalysesProvider(meal.id).future),
          keep: await ref.watch(mealKeepOnPhoneProvider(meal.id).future),
        ),
  };
});

const Set<MealAnalysisStatus> _settled = {
  MealAnalysisStatus.queued,
  MealAnalysisStatus.sending,
  MealAnalysisStatus.done,
  MealAnalysisStatus.notFood,
};

/// The photo meals a batch would send: keep off and no row of the current
/// target waiting or answered. Failed and rejected rows stay a single tap.
List<int> mealsToAnalyze(
  List<Meal> meals,
  Map<int, FoodDayAnalysis> analyses, {
  required String host,
  required String model,
}) {
  bool current(MealAnalysis row) =>
      (row.target.providerHost, row.target.model, row.target.promptVersion) ==
      (host, model, aiMealPromptVersion);
  bool open(FoodDayAnalysis? a) =>
      a != null &&
      !a.keep &&
      !a.rows.any((row) => current(row) && _settled.contains(row.status));
  return [
    for (final meal in meals)
      if (open(analyses[meal.id])) meal.id,
  ];
}

/// The select case of the meal's day badge, or null for none. Suggestions
/// show only while the meal has no tag of the person's own.
String? foodAiBadgeState(
  Meal meal,
  FoodDayAnalysis? analysis, {
  required int? sendingId,
}) {
  final row = analysis?.rows.firstOrNull;
  if (analysis == null || analysis.keep || row == null) return null;
  if (row.id == sendingId) return 'sending';
  return switch (row.status) {
    MealAnalysisStatus.queued => 'queued',
    MealAnalysisStatus.sending => 'sending',
    MealAnalysisStatus.failed => 'failed',
    MealAnalysisStatus.done when _onlySuggested(meal, row) => 'suggestions',
    _ => null,
  };
}

bool _onlySuggested(Meal meal, MealAnalysis row) {
  final suggestion = row.suggestion;
  if (meal.kind != null || !meal.tags.isEmpty || suggestion == null) {
    return false;
  }
  return suggestedTags(suggestion, MealEdit.of(meal)).isNotEmpty;
}

bool _aiOn(WidgetRef ref) =>
    ref.watch(aiEnabledProvider) &&
    ref.watch(foodEnabledProvider) &&
    !ref.watch(demoModeProvider);

class FoodDayAiBadge extends ConsumerWidget {
  const new({required this.meal, required this.date, super.key});

  final Meal meal;
  final LocalDate date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_aiOn(ref)) return const SizedBox.shrink();
    final analyses = ref.watch(foodDayAnalysesProvider(date)).value;
    final sendingId = ref.watch(
      mealAnalysisQueueProvider.select((s) => s.sendingId),
    );
    final state = foodAiBadgeState(
      meal,
      analyses?[meal.id],
      sendingId: sendingId,
    );
    if (state == null) return const SizedBox.shrink();
    final colors = AppColors.of(context);
    final icon = switch (state) {
      'suggestions' => Icons.auto_awesome_outlined,
      'queued' => Icons.schedule_rounded,
      'sending' => Icons.send_outlined,
      _ => Icons.warning_amber_rounded,
    };
    final dashed = state == 'suggestions';
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: dashed ? null : colors.surfaceInner,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.textSecondary),
          const SizedBox(width: 4),
          Flexible(
            child: CaptionText(AppLocalizations.of(context).foodAiBadge(state)),
          ),
        ],
      ),
    );
    return Padding(
      key: FoodDayAiKeys.badge(meal.id),
      padding: const EdgeInsets.only(top: 6),
      child: CustomPaint(
        foregroundPainter: dashed
            ? DashedBorderPainter(color: colors.textLabel, radius: 8)
            : null,
        child: badge,
      ),
    );
  }
}

/// "Analyze N photos" under the add row, with the paused queue card above
/// it while a pause holds.
class FoodDayAiBatch extends ConsumerStatefulWidget {
  const new({required this.date, required this.meals, super.key});

  final LocalDate date;
  final List<Meal> meals;

  @override
  ConsumerState<FoodDayAiBatch> createState() => _FoodDayAiBatchState();
}

class _FoodDayAiBatchState extends ConsumerState<FoodDayAiBatch> {
  bool _busy = false;

  Future<void> _analyze(List<int> ids) async {
    setState(() => _busy = true);
    await analyzeMealPhotos(context, ref, ids);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_aiOn(ref)) return const SizedBox.shrink();
    final config = ref.watch(aiConfigProvider).value;
    final analyses = ref.watch(foodDayAnalysesProvider(widget.date)).value;
    if (config == null || analyses == null) return const SizedBox.shrink();
    final ids = mealsToAnalyze(
      widget.meals,
      analyses,
      host: config.hostKey ?? '',
      model: aiPhotoTarget(config),
    );
    if (ids.isEmpty) return const SizedBox.shrink();
    final paused = ref.watch(aiPhotoQueuePauseProvider).value != null;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: cardGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (paused) ...[
            MealPhotoPauseCard(
              onTest: () => unawaited(
                GoRouter.maybeOf(context)?.push(AppPaths.settingsAiPhotos),
              ),
            ),
            const SizedBox(height: cardGap),
          ],
          SecondaryButton(
            buttonKey: FoodDayAiKeys.batch,
            label: l10n.foodAiBatch(ids.length),
            onPressed: _busy ? null : () => unawaited(_analyze(ids)),
          ),
        ],
      ),
    );
  }
}
