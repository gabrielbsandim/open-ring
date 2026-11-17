import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/application/meal_capture.dart';
import 'package:open_ring/features/food/application/meal_photo_saver.dart';
import 'package:open_ring/features/food/application/today_meals.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/presentation/meal_saved_sheet.dart';

abstract final class FoodRowKeys {
  static const row = Key('today_food_row');
  static const camera = Key('today_food_camera');
  static const saving = Key('today_food_saving');
}

// Marks a result whose sheet has opened, so a rebuilt row does not open it
// again.
final _opened = Expando<bool>();

/// The Food entry of Today: today's meals and a camera button. It shows in
/// every state of Today while the module is on, ring or no ring.
class FoodRowSlot extends ConsumerWidget {
  const new({this.padding = const EdgeInsets.only(bottom: cardGap), super.key});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(foodEnabledProvider)) return const SizedBox.shrink();
    return Padding(padding: padding, child: const _FoodRow());
  }
}

class _FoodRow extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_FoodRow> createState() => _FoodRowState();
}

class _FoodRowState extends ConsumerState<_FoodRow> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(todayMealsProvider),
    );
    ref.listenManual(mealCaptureProvider, _onCapture, fireImmediately: true);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _onCapture(CaptureState? previous, CaptureState next) {
    final result = next.result;
    if (next.saving || result == null) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_open(result, recovered: next.recovered)),
    );
  }

  Future<void> _open(SaveResult result, {required bool recovered}) async {
    if (!mounted || (_opened[result] ?? false)) return;
    _opened[result] = true;
    final capture = ref.read(mealCaptureProvider.notifier);
    final today = foodDay(ref.read(clockProvider)().toLocal());
    await switch ((result.outcome, result.meal)) {
      (SaveOutcome.saved, final Meal meal) => _saved(
        capture,
        meal,
        today,
        time: result.time,
        recovered: recovered,
      ),
      (SaveOutcome.noSpace, final Meal meal) => _noSpace(capture, meal, today),
      _ => _failed(capture),
    };
  }

  Future<void> _saved(
    MealCapture capture,
    Meal meal,
    LocalDate today, {
    required TimeSource time,
    required bool recovered,
  }) async {
    final edit = ValueNotifier(MealEdit.of(meal));
    await _sheet<void>(
      MealSavedSheet(
        meal: meal,
        time: time,
        recovered: recovered,
        today: today,
        edit: edit,
      ),
    );
    await capture.finish(edit.value);
    edit.dispose();
  }

  Future<void> _noSpace(MealCapture capture, Meal meal, LocalDate today) async {
    final choice = await _sheet<NoSpaceChoice>(
      MealNoSpaceSheet(meal: meal, today: today),
    );
    await switch (choice) {
      NoSpaceChoice.retry => capture.retry(),
      NoSpaceChoice.discard => capture.discard(),
      NoSpaceChoice.withoutPhoto || null => capture.finish(),
    };
  }

  Future<void> _failed(MealCapture capture) {
    final l10n = MetricFormat.of(context).l10n;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.foodNoSpaceTitle)));
    return capture.finish();
  }

  Future<T?> _sheet<T>(Widget sheet) => showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.of(context).surface,
    builder: (context) => SafeArea(child: sheet),
  );

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final capture = ref.watch(mealCaptureProvider);
    final meals = ref.watch(todayMealsProvider).value;
    final note = _note(format, saving: capture.saving, meals: meals);
    return MetricCard(
      key: FoodRowKeys.row,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.foodTitle,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (note != null) ...[const SizedBox(height: 2), note],
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: FoodRowKeys.camera,
            tooltip: l10n.foodCamera,
            icon: const Icon(Icons.photo_camera_outlined),
            onPressed: capture.saving
                ? null
                : () => unawaited(
                    ref.read(mealCaptureProvider.notifier).capture(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget? _note(
    MetricFormat format, {
    required bool saving,
    required List<Meal>? meals,
  }) {
    final l10n = format.l10n;
    if (saving) return CaptionText(l10n.foodRowSaving, key: FoodRowKeys.saving);
    if (meals == null) return null;
    final today = foodToday(meals);
    final from = today.windowFrom;
    final count = format.integer(today.count);
    if (today.count == 0) return CaptionText(l10n.foodRowNone);
    if (from == null) return CaptionText(l10n.foodRowCount(count));
    return CaptionText(
      l10n.foodRowWindow(count, format.clock(from, Duration.zero)),
    );
  }
}
