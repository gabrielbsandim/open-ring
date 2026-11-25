import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/food/application/food_day.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/domain/meal_suggestion.dart';
import 'package:open_ring/features/food/presentation/food_day_screen.dart';
import 'package:open_ring/features/food/presentation/meal_analysis_section.dart';
import 'package:open_ring/features/food/presentation/meal_saved_sheet.dart';

abstract final class FoodMealKeys {
  static const photo = Key('food_meal_photo');
  static const noPhoto = Key('food_meal_no_photo');
  static const missingPhoto = Key('food_meal_missing_photo');
  static const timeTile = Key('food_meal_time');
  static const lastMeal = Key('food_meal_last_meal');
  static const kcalTile = Key('food_meal_kcal_tile');
  static const kcalSheet = Key('food_meal_kcal_sheet');
  static const kcalClose = Key('food_meal_kcal_close');
  static const deleteTile = Key('food_meal_delete_tile');
  static const deleteSheet = Key('food_meal_delete_sheet');
  static const deleteConfirm = Key('food_meal_delete_confirm');
  static const deleteCancel = Key('food_meal_delete_cancel');
  static const notFound = Key('food_meal_not_found');
}

const _radius = BorderRadius.all(Radius.circular(14));

Meal _copyMeal(Meal m, {DateTime? at, int? offset, MealEdit? edit}) => Meal(
  id: m.id,
  at: at ?? m.at,
  offsetMinutes: offset ?? m.offsetMinutes,
  kind: edit == null ? m.kind : edit.kind,
  tags: edit == null ? m.tags : edit.tags,
  last: edit == null ? m.last : edit.last,
  photo: m.photo,
  createdAt: m.createdAt,
);

class FoodMealScreen extends ConsumerWidget {
  const new({required this.mealId, super.key});

  final int? mealId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = MetricFormat.of(context).l10n;
    if (!ref.watch(foodEnabledProvider)) {
      return AppPage(title: l10n.foodTitle, children: const []);
    }
    final id = mealId;
    final meal = id == null ? null : ref.watch(mealByIdProvider(id));
    if (meal != null && meal.hasValue && !meal.hasError) {
      final loaded = meal.requireValue;
      if (loaded != null) return _MealBody(meal: loaded);
    }
    if (meal != null && meal.isLoading) {
      return AppPage(
        title: l10n.foodTitle,
        children: const [Center(child: CircularProgressIndicator())],
      );
    }
    return AppPage(
      title: l10n.foodTitle,
      children: [
        EmptyStateCard(
          key: FoodMealKeys.notFound,
          icon: Icons.restaurant_outlined,
          accent: AppColors.of(context).textLabel,
          message: l10n.foodMealNotFound,
        ),
      ],
    );
  }
}

Future<T?> _showSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.of(context).surface,
      builder: (_) => SafeArea(child: child),
    );

class _MealBody extends ConsumerStatefulWidget {
  const new({required this.meal});

  final Meal meal;

  @override
  ConsumerState<_MealBody> createState() => _MealBodyState();
}

class _MealBodyState extends ConsumerState<_MealBody> {
  late Meal _persisted = widget.meal;
  late MealEdit _edit = MealEdit.of(widget.meal);
  bool _savingTags = false;
  bool _dirtyTags = false;
  bool _changingTime = false;
  bool _deleting = false;
  String? _brokenPhoto;

  @override
  void didUpdateWidget(_MealBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_savingTags && !_dirtyTags && widget.meal != oldWidget.meal) {
      _persisted = widget.meal;
      _edit = MealEdit.of(widget.meal);
    }
  }

  void _onEditChanged(MealEdit next) {
    if (_deleting || _changingTime) return;
    setState(() => _edit = next);
    _dirtyTags = true;
    if (_savingTags) return;
    unawaited(_flushEdits());
  }

  Future<void> _flushEdits() async {
    _savingTags = true;
    final editor = ref.read(mealEditorProvider);
    while (mounted && _dirtyTags && !_deleting) {
      _dirtyTags = false;
      final target = _edit;
      final saved = await editor.save(_persisted, target);
      if (!mounted) return;
      if (!saved) {
        _dirtyTags = false;
        setState(() => _edit = MealEdit.of(_persisted));
        _snack(MetricFormat.of(context).l10n.foodTagsFailed);
        break;
      }
      _persisted = _copyMeal(_persisted, edit: target);
    }
    _savingTags = false;
  }

  Future<void> _pickTime() async {
    if (_deleting || _changingTime || _savingTags) return;
    setState(() => _changingTime = true);
    final picker = ref.read(mealTimePickerProvider);
    final editor = ref.read(mealEditorProvider);
    final wall = _persisted.entry.at;
    final picked = await picker(
      context,
      TimeOfDay(hour: wall.hour, minute: wall.minute),
    );
    if (!mounted) return;
    if (picked == null) {
      setState(() => _changingTime = false);
      return;
    }
    final base = _persisted;
    final result = await editor.setTime(
      base,
      hour: picked.hour,
      minute: picked.minute,
    );
    if (!mounted) return;
    final baseWall = base.entry.at;
    if (result is EditTimeSaved &&
        (baseWall.hour != picked.hour || baseWall.minute != picked.minute)) {
      final at = mealTimeOnFoodDay(
        foodDay(baseWall),
        hour: picked.hour,
        minute: picked.minute,
      );
      _persisted = _copyMeal(
        base,
        at: at.toUtc(),
        offset: at.timeZoneOffset.inMinutes,
      );
    }
    setState(() => _changingTime = false);
    final l10n = MetricFormat.of(context).l10n;
    if (result is EditTimeFuture) _snack(l10n.foodAddFutureError);
    if (result is EditTimeFailed) _snack(l10n.foodMealTimeFailed);
  }

  Future<void> _confirmDelete() async {
    if (_deleting) return;
    final editor = ref.read(mealEditorProvider);
    var confirmed = false;
    final go = await _showSheet<bool>(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setSheet) => _deleteSheet(sheetCtx, confirmed, () {
          if (confirmed) return;
          setSheet(() => confirmed = true);
          Navigator.of(sheetCtx).pop(true);
        }),
      ),
    );
    if (!mounted || go != true || _deleting) return;
    setState(() => _deleting = true);
    final deleted = await editor.delete(_persisted.id);
    if (!mounted) return;
    if (!deleted) {
      setState(() => _deleting = false);
      _snack(MetricFormat.of(context).l10n.foodMealDeleteFailed);
      return;
    }
    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) router.pop();
  }

  void _confirmAll(Set<Object> values) {
    _onEditChanged(applySuggested(_edit, values));
    _snack(MetricFormat.of(context).l10n.foodAiConfirmed);
  }

  // Demo draws its own read only sample, so its chips stay plain.
  Set<Object> _suggested(int mealId) {
    if (ref.watch(demoModeProvider)) return const {};
    final keep = ref.watch(mealKeepOnPhoneProvider(mealId)).value ?? true;
    final row = ref.watch(mealAnalysesProvider(mealId)).value?.firstOrNull;
    if (keep || row == null || row.status != MealAnalysisStatus.done) {
      return const {};
    }
    final suggestion = row.suggestion;
    if (suggestion == null) return const {};
    return suggestedTags(suggestion, _edit);
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    final meal = _persisted;
    final locked = _deleting || _changingTime;
    final ai = ref.watch(aiEnabledProvider) && ref.watch(foodEnabledProvider);
    final analyzed = ai && meal.photo != null;
    final suggested = analyzed ? _suggested(meal.id) : const <Object>{};
    return AppPage(
      title: mealSlotLabel(l10n, meal),
      children: [
        _buildPhoto(context, meal.photo),
        const SizedBox(height: cardGap),
        MetricCard(
          child: _tile(
            context,
            FoodMealKeys.timeTile,
            Icons.schedule_outlined,
            format.clock(meal.entry.at, Duration.zero),
            l10n.foodMealTimeHint,
            locked ? null : () => unawaited(_pickTime()),
          ),
        ),
        const SizedBox(height: cardGap),
        MetricCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.foodMealTagsTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 2),
              CaptionText(l10n.foodMealTagsHint),
              MealTagsEditor(
                value: _edit,
                onChanged: locked ? null : _onEditChanged,
                suggested: suggested,
              ),
            ],
          ),
        ),
        if (analyzed) ...[
          const SizedBox(height: cardGap),
          MealAnalysisSection(
            mealId: meal.id,
            pending: suggested,
            onConfirmAll: locked ? null : () => _confirmAll(suggested),
          ),
        ],
        const SizedBox(height: cardGap),
        MetricCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                key: FoodMealKeys.lastMeal,
                contentPadding: EdgeInsets.zero,
                value: _edit.last,
                onChanged: locked
                    ? null
                    : (on) => _onEditChanged(_edit.withLast(on)),
                title: Text(l10n.foodLastTitle),
                subtitle: CaptionText(l10n.foodLastHint),
              ),
              const Divider(height: 1),
              _tile(
                context,
                FoodMealKeys.kcalTile,
                Icons.local_fire_department_outlined,
                l10n.foodMealKcalTile,
                l10n.foodMealKcalTileHint,
                () => unawaited(_showSheet<void>(context, _kcalSheet(context))),
              ),
              const Divider(height: 1),
              _tile(
                context,
                FoodMealKeys.deleteTile,
                Icons.delete_outline_rounded,
                l10n.foodMealDeleteTile,
                l10n.foodMealDeleteTileHint,
                locked ? null : () => unawaited(_confirmDelete()),
                colors.heart,
              ),
            ],
          ),
        ),
        const SizedBox(height: cardGap),
        CaptionText(l10n.foodMealFoot),
      ],
    );
  }

  Widget _buildPhoto(BuildContext context, String? name) {
    final l10n = MetricFormat.of(context).l10n;
    if (name == null) {
      return _photoBox(
        context,
        FoodMealKeys.noPhoto,
        Icons.restaurant_outlined,
        l10n.foodNoPhoto,
      );
    }
    Widget missing() => _photoBox(
      context,
      FoodMealKeys.missingPhoto,
      Icons.broken_image_outlined,
      l10n.foodPhotoMissing,
    );
    if (_brokenPhoto == name) return missing();
    final photo = ref.watch(mealPhotoProvider(name));
    if (photo.isLoading && !photo.hasValue) {
      return AspectRatio(
        aspectRatio: 4 / 3,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.of(context).surfaceInner,
            borderRadius: _radius,
          ),
        ),
      );
    }
    final bytes = photo.asData?.value;
    if (bytes == null) return missing();
    return ClipRRect(
      borderRadius: _radius,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Image(
          key: FoodMealKeys.photo,
          image: ResizeImage(MemoryImage(bytes), width: 1024),
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (_, _, _) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _brokenPhoto != name) {
                setState(() => _brokenPhoto = name);
              }
            });
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

Widget _tile(
  BuildContext context,
  Key key,
  IconData icon,
  String title,
  String subtitle,
  VoidCallback? onTap, [
  Color? accent,
]) {
  final c = AppColors.of(context);
  return ListTile(
    key: key,
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: accent ?? c.textSecondary),
    title: Text(title, style: accent == null ? null : TextStyle(color: accent)),
    subtitle: CaptionText(subtitle),
    trailing: Icon(Icons.chevron_right_rounded, color: accent ?? c.textLabel),
    onTap: onTap,
  );
}

Widget _photoBox(BuildContext context, Key key, IconData icon, String label) =>
    MetricCard(
      key: key,
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppColors.of(context).textLabel),
          const SizedBox(height: 8),
          CaptionText(label),
        ],
      ),
    );

Widget _sheet(
  BuildContext context,
  Key key,
  String title,
  List<Widget> children,
) => SingleChildScrollView(
  key: key,
  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      const SizedBox(height: 10),
      ...children,
    ],
  ),
);

Widget _kcalSheet(BuildContext context) {
  final l10n = MetricFormat.of(context).l10n;
  return _sheet(context, FoodMealKeys.kcalSheet, l10n.foodMealKcalTitle, [
    BodyText(l10n.foodMealKcalBody),
    const SizedBox(height: 10),
    BodyText(l10n.foodMealKcalNoCount),
    const SizedBox(height: 12),
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.of(context).surfaceInner,
        borderRadius: _radius,
      ),
      child: BodyText(l10n.foodMealKcalInstead),
    ),
    const SizedBox(height: 16),
    ActionButton(
      buttonKey: FoodMealKeys.kcalClose,
      label: l10n.foodMealClose,
      onPressed: () => Navigator.of(context).pop(),
    ),
  ]);
}

Widget _deleteSheet(BuildContext ctx, bool confirmed, VoidCallback onConfirm) {
  final l10n = MetricFormat.of(ctx).l10n;
  final colors = AppColors.of(ctx);
  return _sheet(ctx, FoodMealKeys.deleteSheet, l10n.foodMealDeleteTitle, [
    BodyText(l10n.foodMealDeleteBody),
    const SizedBox(height: 16),
    FilledButton(
      key: FoodMealKeys.deleteConfirm,
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        backgroundColor: colors.heart,
        foregroundColor: colors.onAccent,
        shape: const RoundedRectangleBorder(borderRadius: _radius),
      ),
      onPressed: confirmed ? null : onConfirm,
      child: Text(l10n.foodMealDeleteConfirm, textAlign: TextAlign.center),
    ),
    const SizedBox(height: 8),
    SecondaryButton(
      buttonKey: FoodMealKeys.deleteCancel,
      label: l10n.foodMealDeleteCancel,
      onPressed: () => Navigator.of(ctx).pop(false),
    ),
  ]);
}
