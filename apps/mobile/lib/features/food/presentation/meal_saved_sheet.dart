import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/food/application/meal_photo_saver.dart';
import 'package:open_ring/features/food/domain/meal.dart';

abstract final class MealSavedSheetKeys {
  static const last = Key('meal_saved_last');
  static const done = Key('meal_saved_done');
  static const retry = Key('meal_no_space_retry');
  static const withoutPhoto = Key('meal_no_space_without_photo');
  static const discard = Key('meal_no_space_discard');
}

enum NoSpaceChoice { retry, withoutPhoto, discard }

/// The meal time, with its date when it is off the food day of [today].
String mealTime(MetricFormat format, Meal meal, LocalDate today) {
  final at = meal.entry.at;
  if (foodDay(at) == today) return format.clock(at, Duration.zero);
  return format.dayAndClock(at, Duration.zero);
}

/// What was saved, and the last meal switch. The caller writes [last]
/// however the sheet is closed.
class MealSavedSheet extends StatelessWidget {
  const new({
    required this.meal,
    required this.time,
    required this.recovered,
    required this.today,
    required this.last,
    super.key,
  });

  final Meal meal;
  final TimeSource time;
  final bool recovered;
  final LocalDate today;
  final ValueNotifier<bool> last;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    return _SheetBody(
      children: [
        if (recovered) ...[
          _Note(text: l10n.foodRecovered),
          const SizedBox(height: 12),
        ],
        _Title(l10n.foodSavedTitle),
        const SizedBox(height: 2),
        CaptionText(mealTime(format, meal, today)),
        if (time == TimeSource.returned) ...[
          const SizedBox(height: 6),
          CaptionText(l10n.foodSavedReturned),
        ],
        const SizedBox(height: 10),
        BodyText(l10n.foodSavedNote),
        const SizedBox(height: 4),
        ValueListenableBuilder<bool>(
          valueListenable: last,
          builder: (context, on, _) => SwitchListTile(
            key: MealSavedSheetKeys.last,
            contentPadding: EdgeInsets.zero,
            value: on,
            onChanged: (value) => last.value = value,
            title: Text(l10n.foodLastTitle),
            subtitle: Text(l10n.foodLastHint),
          ),
        ),
        const SizedBox(height: 12),
        ActionButton(
          buttonKey: MealSavedSheetKeys.done,
          label: l10n.foodDone,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// A full disk kept the row without its photo: retry, keep it photoless, or
/// discard it.
class MealNoSpaceSheet extends StatelessWidget {
  const new({required this.meal, required this.today, super.key});

  final Meal meal;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    void pick(NoSpaceChoice choice) => Navigator.of(context).pop(choice);
    return _SheetBody(
      children: [
        _Title(l10n.foodNoSpaceTitle),
        const SizedBox(height: 8),
        BodyText(l10n.foodNoSpaceBody(mealTime(format, meal, today))),
        const SizedBox(height: 16),
        SecondaryButton(
          buttonKey: MealSavedSheetKeys.retry,
          label: l10n.foodRetry,
          onPressed: () => pick(NoSpaceChoice.retry),
        ),
        const SizedBox(height: 8),
        ActionButton(
          buttonKey: MealSavedSheetKeys.withoutPhoto,
          label: l10n.foodWithoutPhoto,
          onPressed: () => pick(NoSpaceChoice.withoutPhoto),
        ),
        const SizedBox(height: 8),
        SecondaryButton(
          buttonKey: MealSavedSheetKeys.discard,
          label: l10n.foodDiscard,
          onPressed: () => pick(NoSpaceChoice.discard),
        ),
        const SizedBox(height: 10),
        CaptionText(l10n.foodNoSpaceNote),
      ],
    );
  }
}

class _SheetBody extends StatelessWidget {
  const new({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

class _Title extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}

class _Note extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceInner,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle_outline_rounded, color: colors.textPrimary),
            const SizedBox(width: 10),
            Expanded(child: BodyText(text)),
          ],
        ),
      ),
    );
  }
}
