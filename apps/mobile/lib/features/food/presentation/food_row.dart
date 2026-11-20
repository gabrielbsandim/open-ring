import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/application/meal_capture.dart';
import 'package:open_ring/features/food/application/today_meals.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/presentation/meal_capture_presenter.dart';

abstract final class FoodRowKeys {
  static const row = Key('today_food_row');
  static const camera = Key('today_food_camera');
  static const saving = Key('today_food_saving');
}

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
  late final MealCaptureHosts _hosts;

  @override
  void initState() {
    super.initState();
    _hosts = ref.read(mealCaptureHostsProvider)..attach(this);
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(todayMealsProvider),
    );
    ref.listenManual(mealCaptureProvider, _onCapture, fireImmediately: true);
  }

  @override
  void dispose() {
    _hosts.detach(this);
    _lifecycle.dispose();
    super.dispose();
  }

  void _onCapture(CaptureState? previous, CaptureState next) {
    final result = next.result;
    if (next.saving || result == null) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(
        presentMealCapture(
          context: context,
          ref: ref,
          hostToken: this,
          result: result,
          recovered: next.recovered,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final capture = ref.watch(mealCaptureProvider);
    final meals = ref.watch(todayMealsProvider).value;
    final note = _note(format, saving: capture.saving, meals: meals);
    return MetricCard(
      key: FoodRowKeys.row,
      onTap: capture.saving ? null : () => context.go(AppPaths.food),
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
