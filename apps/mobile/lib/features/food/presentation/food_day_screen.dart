import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/food/application/food_day.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/presentation/meal_saved_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class FoodDayKeys {
  static const previous = Key('food_day_previous');
  static const next = Key('food_day_next');
  static const window = Key('food_day_window');
  static const empty = Key('food_day_empty');

  static Key meal(int id) => Key('food_day_meal_$id');
  static Key noPhoto(int id) => Key('food_day_no_photo_$id');
  static Key missingPhoto(int id) => Key('food_day_missing_photo_$id');
}

class FoodDayScreen extends ConsumerStatefulWidget {
  const new({this.day, super.key});

  final LocalDate? day;

  @override
  ConsumerState<FoodDayScreen> createState() => _FoodDayScreenState();
}

class _FoodDayScreenState extends ConsumerState<FoodDayScreen> {
  late LocalDate? _picked = widget.day;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(currentFoodDayProvider),
    );
  }

  @override
  void didUpdateWidget(FoodDayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.day != oldWidget.day) _picked = widget.day;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final on = ref.watch(foodEnabledProvider);
    return AppPage(
      title: format.l10n.foodTitle,
      children: on
          ? [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _content(format),
              ),
            ]
          : const [],
    );
  }

  List<Widget> _content(MetricFormat format) {
    final today = ref.watch(currentFoodDayProvider);
    final picked = _picked;
    final date = picked != null && picked.compareTo(today) <= 0
        ? picked
        : today;
    final isToday = date == today;
    final meals = ref.watch(foodDayMealsProvider(date));
    return [
      _DayHeader(
        date: date,
        isToday: isToday,
        onPrevious: () => setState(() => _picked = date.addDays(-1)),
        onNext: isToday
            ? null
            : () => setState(() {
                final next = date.addDays(1);
                _picked = next == today ? null : next;
              }),
      ),
      const SizedBox(height: cardGap),
      ..._body(meals, format, date: date, today: today),
    ];
  }

  List<Widget> _body(
    AsyncValue<List<Meal>> meals,
    MetricFormat format, {
    required LocalDate date,
    required LocalDate today,
  }) {
    if (meals.hasValue) {
      return _meals(meals.requireValue, format, date: date, today: today);
    }
    if (meals.hasError) return [BodyText(format.l10n.metricLoadError)];
    return const [SizedBox(height: 96)];
  }

  List<Widget> _meals(
    List<Meal> meals,
    MetricFormat format, {
    required LocalDate date,
    required LocalDate today,
  }) {
    if (meals.isEmpty) return const [_EmptyDay()];
    final now = ref.watch(clockProvider)().toLocal();
    final window = dayWindow(meals, day: date, now: now);
    return [
      if (window != null) ...[
        _WindowCard(window: window),
        const SizedBox(height: cardGap),
      ],
      for (final meal in meals) ...[
        _MealCard(
          meal: meal,
          onTap: () => unawaited(_edit(meal, today: today)),
        ),
        const SizedBox(height: cardGap),
      ],
      CaptionText(format.l10n.foodDayCompleteNote),
    ];
  }

  Future<void> _edit(Meal meal, {required LocalDate today}) async {
    final editor = ref.read(mealEditorProvider);
    final edit = ValueNotifier(MealEdit.of(meal));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.of(context).surface,
      builder: (context) => SafeArea(
        child: MealSavedSheet.edit(meal: meal, today: today, edit: edit),
      ),
    );
    final next = edit.value;
    edit.dispose();
    final saved = await editor.save(meal, next);
    if (saved || !mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(MetricFormat.of(context).l10n.foodTagsFailed)),
      );
  }
}

class _DayHeader extends StatelessWidget {
  const new({
    required this.date,
    required this.isToday,
    required this.onPrevious,
    required this.onNext,
  });

  final LocalDate date;
  final bool isToday;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          key: FoodDayKeys.previous,
          tooltip: l10n.foodDayPrevious,
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: MergeSemantics(
            child: Column(
              children: [
                Text(
                  format.date(date),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isToday) ...[
                  const SizedBox(height: 2),
                  CaptionText(l10n.foodDayToday, textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        ),
        IconButton(
          key: FoodDayKeys.next,
          tooltip: l10n.foodDayNext,
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _WindowCard extends StatelessWidget {
  const new({required this.window});

  final DayWindow window;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final from = format.clock(window.from, Duration.zero);
    final duration = format.duration(window.to.difference(window.from));
    final text = window.open
        ? l10n.foodWindowOpen(from, duration)
        : l10n.foodWindowSpan(
            from,
            format.clock(window.to, Duration.zero),
            duration,
          );
    return MetricCard(
      key: FoodDayKeys.window,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccentTitle(
            title: l10n.foodWindowTitle,
            accent: AppColors.of(context).activity,
          ),
          const SizedBox(height: 8),
          BodyText(text),
        ],
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = MetricFormat.of(context).l10n;
    return MetricCard(
      key: FoodDayKeys.empty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.foodDayEmptyTitle,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 6),
          BodyText(l10n.foodDayEmptyBody),
          const SizedBox(height: 10),
          CaptionText(l10n.foodDayBlankNote),
        ],
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const new({required this.meal, required this.onTap});

  final Meal meal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final time = format.clock(meal.entry.at, Duration.zero);
    final slot = mealSlotLabel(l10n, meal);
    final tags = _tagLine(l10n, meal);
    return MetricCard(
      key: FoodDayKeys.meal(meal.id),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MealThumbnail(meal: meal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      time,
                      style: numberStyle(
                        theme.textTheme.bodySmall,
                        color: colors.textLabel,
                      ),
                    ),
                    Text(
                      slot,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                CaptionText(tags),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MealThumbnail extends ConsumerWidget {
  const new({required this.meal});

  final Meal meal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = MetricFormat.of(context).l10n;
    final name = meal.photo;
    if (name == null) {
      return _PlaceholderThumb(
        key: FoodDayKeys.noPhoto(meal.id),
        icon: Icons.restaurant_outlined,
        label: l10n.foodNoPhoto,
      );
    }
    final photo = ref.watch(mealPhotoProvider(name));
    if (photo.hasValue && photo.requireValue != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          photo.requireValue!,
          width: 48,
          height: 48,
          cacheWidth: 96,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _PlaceholderThumb(
            key: FoodDayKeys.missingPhoto(meal.id),
            icon: Icons.broken_image_outlined,
            label: l10n.foodPhotoMissing,
          ),
        ),
      );
    }
    if (photo.hasValue || photo.hasError) {
      return _PlaceholderThumb(
        key: FoodDayKeys.missingPhoto(meal.id),
        icon: Icons.broken_image_outlined,
        label: l10n.foodPhotoMissing,
      );
    }
    return const SizedBox(width: 48, height: 48);
  }
}

class _PlaceholderThumb extends StatelessWidget {
  const new({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      label: label,
      child: SizedBox(
        width: 48,
        height: 48,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceInner,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: colors.textLabel),
        ),
      ),
    );
  }
}

String _tagLine(AppLocalizations l10n, Meal meal) {
  final words = _tagWords(l10n, meal);
  if (words.isEmpty) return l10n.foodMealNoTags;
  return words.join(' · ');
}

List<String> _tagWords(AppLocalizations l10n, Meal meal) {
  final tags = meal.tags;
  return [
    if (meal.kind case final kind? when kind != MealKind.drink)
      switch (kind) {
        MealKind.main => l10n.foodKindMain,
        MealKind.snack => l10n.foodKindSnack,
        MealKind.drink => l10n.foodKindDrink,
      },
    if (tags.protein) l10n.foodProtein,
    if (tags.veg case final veg?)
      switch (veg) {
        MealVeg.some => l10n.foodVegSome,
        MealVeg.halfOrMore => l10n.foodVegHalf,
      },
    if (tags.alcohol case final alcohol?)
      switch (alcohol) {
        MealAlcohol.oneToTwo => l10n.foodAlcoholOneToTwo,
        MealAlcohol.threeOrMore => l10n.foodAlcoholThreeOrMore,
      },
    if (tags.caffeine) l10n.foodCaffeine,
    if (tags.heavy) l10n.foodHeavy,
    if (tags.fried) l10n.foodFried,
    if (tags.sugar) l10n.foodSugar,
    if (tags.processed case final processed?)
      switch (processed) {
        MealProcessed.mostly => l10n.foodProcessedMostly,
        MealProcessed.unsure => l10n.foodProcessedUnsure,
      },
    if (tags.place case final place?)
      switch (place) {
        MealPlace.home => l10n.foodPlaceHome,
        MealPlace.restaurant => l10n.foodPlaceRestaurant,
        MealPlace.packaged => l10n.foodPlacePackaged,
      },
    if (meal.kind == MealKind.drink && tags.isEmpty) l10n.foodKindDrink,
  ];
}
