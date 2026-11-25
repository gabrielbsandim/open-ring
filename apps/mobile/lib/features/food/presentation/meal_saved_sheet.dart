import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/food/application/meal_photo_saver.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/open_score/presentation/day_tag_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class MealSavedSheetKeys {
  static const last = Key('meal_saved_last');
  static const done = Key('meal_saved_done');
  static const retry = Key('meal_no_space_retry');
  static const withoutPhoto = Key('meal_no_space_without_photo');
  static const discard = Key('meal_no_space_discard');

  static Key kind(MealKind kind) => Key('meal_saved_kind_${kind.name}');
  static Key flag(MealFlag flag) => Key('meal_saved_flag_${flag.name}');
  static Key veg(MealVeg veg) => Key('meal_saved_veg_${veg.name}');
  static Key alcohol(MealAlcohol alcohol) =>
      Key('meal_saved_alcohol_${alcohol.name}');
  static Key processed(MealProcessed processed) =>
      Key('meal_saved_processed_${processed.name}');
  static Key place(MealPlace place) => Key('meal_saved_place_${place.name}');
}

enum NoSpaceChoice { retry, withoutPhoto, discard }

/// The meal time, with its date when it is off the food day of [today].
String mealTime(MetricFormat format, Meal meal, LocalDate today) {
  final at = meal.entry.at;
  if (foodDay(at) == today) return format.clock(at, Duration.zero);
  return format.dayAndClock(at, Duration.zero);
}

/// The slot name of [meal] from its wall clock, or Drink when it is tagged as
/// a drink.
String mealSlotLabel(AppLocalizations l10n, Meal meal) {
  if (meal.kind == MealKind.drink) return l10n.foodKindDrink;
  return switch (mealSlot(meal.entry.at)) {
    MealSlot.breakfast => l10n.foodSlotBreakfast,
    MealSlot.lunch => l10n.foodSlotLunch,
    MealSlot.afternoonSnack => l10n.foodSlotAfternoonSnack,
    MealSlot.dinner => l10n.foodSlotDinner,
    MealSlot.supper => l10n.foodSlotSupper,
  };
}

/// What was saved, its kind and tags, and the last meal switch. The caller
/// writes [edit] however the sheet is closed.
class MealSavedSheet extends StatelessWidget {
  const new({
    required this.meal,
    required this.time,
    required this.recovered,
    required this.today,
    required this.edit,
    this.ai,
    super.key,
  });

  const new edit({
    required this.meal,
    required this.today,
    required this.edit,
    this.ai,
    super.key,
  }) : time = null,
       recovered = false;

  final Meal meal;
  final TimeSource? time;
  final bool recovered;
  final LocalDate today;
  final ValueNotifier<MealEdit> edit;

  /// The keep switch and Analyze, present only while AI photo analysis can
  /// run for this meal.
  final Widget? ai;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final saved = time != null;
    return _SheetBody(
      children: [
        if (saved && recovered) ...[
          _Note(text: l10n.foodRecovered),
          const SizedBox(height: 12),
        ],
        _Title(saved ? l10n.foodSavedTitle : mealSlotLabel(l10n, meal)),
        const SizedBox(height: 2),
        CaptionText(mealTime(format, meal, today)),
        if (time == TimeSource.returned) ...[
          const SizedBox(height: 6),
          CaptionText(l10n.foodSavedReturned),
        ],
        if (saved) ...[
          const SizedBox(height: 10),
          BodyText(l10n.foodSavedNote),
        ],
        ValueListenableBuilder<MealEdit>(
          valueListenable: edit,
          builder: (context, value, _) => MealTagsEditor(
            value: value,
            onChanged: (next) => edit.value = next,
          ),
        ),
        const SizedBox(height: 4),
        ValueListenableBuilder<MealEdit>(
          valueListenable: edit,
          builder: (context, value, _) => SwitchListTile(
            key: MealSavedSheetKeys.last,
            contentPadding: EdgeInsets.zero,
            value: value.last,
            onChanged: (on) => edit.value = value.withLast(on),
            title: Text(l10n.foodLastTitle),
            subtitle: Text(l10n.foodLastHint),
          ),
        ),
        ?ai,
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

/// The kind and the nine tag groups, in the prototype's order, none chosen
/// by default.
class MealTagsEditor extends StatelessWidget {
  const new({
    required this.value,
    required this.onChanged,
    this.suggested,
    super.key,
  });

  final MealEdit value;
  final ValueChanged<MealEdit>? onChanged;

  /// Drawn dashed while not chosen; a tap sets it through [onChanged].
  final Set<Object>? suggested;

  @override
  Widget build(BuildContext context) {
    final l10n = MetricFormat.of(context).l10n;
    final colors = AppColors.of(context);
    final edit = value;
    final onChanged = this.onChanged;
    final suggested = this.suggested ?? const <Object>{};
    String? hint(Object value, String text) =>
        suggested.contains(value) ? l10n.foodAiSuggestedChip(text) : null;
    ValueChanged<T?>? maybe<T extends Enum>(MealEdit Function(T?) apply) =>
        onChanged == null ? null : (picked) => onChanged(apply(picked));
    Widget flag(MealFlag flag, String label, String text) => _Group(
      label: label,
      chips: [
        _TagChip(
          key: MealSavedSheetKeys.flag(flag),
          text: text,
          selected: edit.flag(flag),
          suggestedLabel: hint(flag, text),
          filter: true,
          onSelected: onChanged == null
              ? null
              : (on) => onChanged(edit.withFlag(flag, on)),
        ),
      ],
    );
    return ChipTheme(
      data: ChipTheme.of(context).copyWith(
        showCheckmark: false,
        selectedColor: colors.textPrimary,
        backgroundColor: colors.surfaceInner,
        side: BorderSide(color: colors.strongBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OneOf(
            label: l10n.foodKindLabel,
            values: MealKind.values,
            selected: edit.kind,
            keyOf: MealSavedSheetKeys.kind,
            text: (kind) => switch (kind) {
              MealKind.main => l10n.foodKindMain,
              MealKind.snack => l10n.foodKindSnack,
              MealKind.drink => l10n.foodKindDrink,
            },
            hint: hint,
            onChanged: maybe(edit.withKind),
          ),
          flag(MealFlag.protein, l10n.foodProteinLabel, l10n.foodProtein),
          _OneOf(
            label: l10n.foodVegLabel,
            values: MealVeg.values,
            selected: edit.tags.veg,
            keyOf: MealSavedSheetKeys.veg,
            text: (veg) => switch (veg) {
              MealVeg.some => l10n.foodVegSome,
              MealVeg.halfOrMore => l10n.foodVegHalf,
            },
            hint: hint,
            onChanged: maybe(edit.withVeg),
          ),
          _OneOf(
            label: l10n.foodAlcoholLabel,
            values: MealAlcohol.values,
            selected: edit.tags.alcohol,
            keyOf: MealSavedSheetKeys.alcohol,
            text: (alcohol) => switch (alcohol) {
              MealAlcohol.oneToTwo => l10n.foodAlcoholOneToTwo,
              MealAlcohol.threeOrMore => l10n.foodAlcoholThreeOrMore,
            },
            hint: hint,
            onChanged: maybe(edit.withAlcohol),
          ),
          flag(MealFlag.caffeine, l10n.foodCaffeineLabel, l10n.foodCaffeine),
          flag(MealFlag.heavy, l10n.foodHeavyLabel, l10n.foodHeavy),
          flag(MealFlag.fried, l10n.foodFriedLabel, l10n.foodFried),
          flag(MealFlag.sugar, l10n.foodSugarLabel, l10n.foodSugar),
          _OneOf(
            label: l10n.foodProcessedLabel,
            values: MealProcessed.values,
            selected: edit.tags.processed,
            keyOf: MealSavedSheetKeys.processed,
            text: (processed) => switch (processed) {
              MealProcessed.mostly => l10n.foodProcessedMostly,
              MealProcessed.unsure => l10n.foodProcessedUnsure,
            },
            hint: hint,
            onChanged: maybe(edit.withProcessed),
          ),
          _OneOf(
            label: l10n.foodPlaceLabel,
            values: MealPlace.values,
            selected: edit.tags.place,
            keyOf: MealSavedSheetKeys.place,
            text: (place) => switch (place) {
              MealPlace.home => l10n.foodPlaceHome,
              MealPlace.restaurant => l10n.foodPlaceRestaurant,
              MealPlace.packaged => l10n.foodPlacePackaged,
            },
            onChanged: maybe(edit.withPlace),
          ),
        ],
      ),
    );
  }
}

/// A single choice group: tapping the chosen chip clears it.
class _OneOf<T extends Enum> extends StatelessWidget {
  const new({
    required this.label,
    required this.values,
    required this.selected,
    required this.keyOf,
    required this.text,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final List<T> values;
  final T? selected;
  final Key Function(T value) keyOf;
  final String Function(T value) text;
  final ValueChanged<T?>? onChanged;

  /// The suggested chip's semantics label, null when it is no suggestion.
  final String? Function(T value, String text)? hint;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return _Group(
      label: label,
      chips: [
        for (final value in values)
          _TagChip(
            key: keyOf(value),
            text: text(value),
            selected: value == selected,
            suggestedLabel: hint?.call(value, text(value)),
            onSelected: onChanged == null
                ? null
                : (on) => onChanged(on ? value : null),
          ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const new({required this.label, required this.chips});

  final String label;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    child: Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: CaptionText(label)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    ),
  );
}

class _TagChip extends StatelessWidget {
  const new({
    required this.text,
    required this.selected,
    required this.onSelected,
    this.filter = false,
    this.suggestedLabel,
    super.key,
  });

  final String text;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  /// A yes or no tag, rather than one choice of a group.
  final bool filter;

  /// Set while the model suggests this chip; it is read in place of [text].
  final String? suggestedLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final suggestedLabel = this.suggestedLabel;
    if (suggestedLabel != null && !selected) {
      return _SuggestedChip(
        text: text,
        semanticsLabel: suggestedLabel,
        onSelected: onSelected,
      );
    }
    final label = Text(
      text,
      style: TextStyle(
        color: selected ? colors.background : colors.textPrimary,
      ),
    );
    if (filter) {
      return FilterChip(
        label: label,
        selected: selected,
        onSelected: onSelected,
      );
    }
    return ChoiceChip(label: label, selected: selected, onSelected: onSelected);
  }
}

// The dashes trace the chip itself, so it drops the padded tap margin and a
// box keeps the 48 dp row height around it.
class _SuggestedChip extends StatelessWidget {
  const new({
    required this.text,
    required this.semanticsLabel,
    required this.onSelected,
  });

  final String text;
  final String semanticsLabel;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final onSelected = this.onSelected;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
      child: Center(
        widthFactor: 1,
        child: CustomPaint(
          foregroundPainter: DashedBorderPainter(
            color: colors.textLabel,
            radius: 8,
          ),
          child: ActionChip(
            avatar: Icon(Icons.auto_awesome_outlined, color: colors.textLabel),
            label: Text(
              text,
              semanticsLabel: semanticsLabel,
              style: TextStyle(color: colors.textSecondary),
            ),
            side: BorderSide.none,
            backgroundColor: Colors.transparent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onPressed: onSelected == null ? null : () => onSelected(true),
          ),
        ),
      ),
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
