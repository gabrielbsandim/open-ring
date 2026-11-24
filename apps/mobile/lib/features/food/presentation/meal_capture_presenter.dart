import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/application/meal_capture.dart';
import 'package:open_ring/features/food/application/meal_photo_saver.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/presentation/meal_analyze_flow.dart';
import 'package:open_ring/features/food/presentation/meal_keep_switch.dart';
import 'package:open_ring/features/food/presentation/meal_saved_sheet.dart';

final Provider<MealCaptureHosts> mealCaptureHostsProvider =
    Provider<MealCaptureHosts>((ref) => MealCaptureHosts());

/// Tracks mounted capture listeners so Today staying mounted under
/// `/today/food` never opens a second sheet for the same capture result.
final class MealCaptureHosts {
  final List<Object> _stack = [];
  final Expando<bool> _opened = Expando<bool>();

  void attach(Object token) => _stack.add(token);

  void detach(Object token) => _stack.remove(token);

  bool claim(SaveResult result, Object token) {
    if (_stack.isEmpty || !identical(_stack.last, token)) return false;
    if (_opened[result] ?? false) return false;
    _opened[result] = true;
    return true;
  }
}

Future<void> presentMealCapture({
  required BuildContext context,
  required WidgetRef ref,
  required Object hostToken,
  required SaveResult result,
  required bool recovered,
}) async {
  if (!context.mounted) return;
  if (!ref.read(mealCaptureHostsProvider).claim(result, hostToken)) return;
  final capture = ref.read(mealCaptureProvider.notifier);
  final today = foodDay(ref.read(clockProvider)().toLocal());
  await switch ((result.outcome, result.meal)) {
    (SaveOutcome.saved, final Meal meal) => _saved(
      context,
      ref,
      capture,
      meal,
      today,
      time: result.time,
      recovered: recovered,
    ),
    (SaveOutcome.noSpace, final Meal meal) => _noSpace(
      context,
      capture,
      meal,
      today,
    ),
    _ => _failed(context, capture),
  };
}

Future<void> _saved(
  BuildContext context,
  WidgetRef ref,
  MealCapture capture,
  Meal meal,
  LocalDate today, {
  required TimeSource time,
  required bool recovered,
}) async {
  final edit = ValueNotifier(MealEdit.of(meal));
  final action = await _sheet<MealSavedAction>(
    context,
    MealSavedSheet(
      meal: meal,
      time: time,
      recovered: recovered,
      today: today,
      edit: edit,
      ai: _photoAi(ref, meal) ? MealSavedAiSlot(mealId: meal.id) : null,
    ),
  );
  final next = edit.value;
  edit.dispose();
  final saved = await capture.finish(next);
  if (!context.mounted) return;
  final failed = MetricFormat.of(context).l10n.foodTagsFailed;
  if (!saved) return _snack(context, failed);
  if (action != MealSavedAction.analyze) return;
  await analyzeMealPhotos(context, ref, [meal.id]);
}

bool _photoAi(WidgetRef ref, Meal meal) =>
    meal.photo != null &&
    ref.read(aiEnabledProvider) &&
    ref.read(foodEnabledProvider) &&
    !ref.read(demoModeProvider);

Future<void> _noSpace(
  BuildContext context,
  MealCapture capture,
  Meal meal,
  LocalDate today,
) async {
  final choice = await _sheet<NoSpaceChoice>(
    context,
    MealNoSpaceSheet(meal: meal, today: today),
  );
  await switch (choice) {
    NoSpaceChoice.retry => capture.retry(),
    NoSpaceChoice.discard => capture.discard(),
    NoSpaceChoice.withoutPhoto || null => capture.finish(),
  };
}

Future<void> _failed(BuildContext context, MealCapture capture) {
  _snack(context, MetricFormat.of(context).l10n.foodNoSpaceTitle);
  return capture.finish();
}

void _snack(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..clearSnackBars()
  ..showSnackBar(SnackBar(content: Text(text)));

Future<T?> _sheet<T>(BuildContext context, Widget sheet) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.of(context).surface,
      builder: (context) => SafeArea(child: sheet),
    );
