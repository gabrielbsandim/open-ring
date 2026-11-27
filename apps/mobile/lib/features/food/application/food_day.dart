import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';

/// The food day of now, which turns at 05:00 local time.
final currentFoodDayProvider = Provider<LocalDate>((ref) {
  final now = ref.watch(clockProvider)().toLocal();
  final today = foodDay(now);
  final next = today.addDays(1);
  final wait = DateTime(
    next.year,
    next.month,
    next.day,
    foodDayStartHour,
  ).difference(now);
  final roll = Timer(
    wait.isNegative ? Duration.zero : wait,
    ref.invalidateSelf,
  );
  ref.onDispose(roll.cancel);
  return today;
});

final FutureProviderFamily<List<Meal>, LocalDate> foodDayMealsProvider =
    FutureProvider.family<List<Meal>, LocalDate>((ref, day) {
      ref.watch(dataRevisionProvider);
      return ref.watch(mealStoreProvider).between(day, day);
    });

final FutureProviderFamily<Meal?, int> mealByIdProvider = FutureProvider
    .autoDispose
    .family<Meal?, int>((ref, id) {
      ref.watch(dataRevisionProvider);
      return ref.watch(mealStoreProvider).byId(id);
    });

/// Reads a photo file by bare name, returning null when the file is missing or
/// cannot be read so a broken photo never hides its meal row.
final FutureProviderFamily<Uint8List?, String> mealPhotoProvider =
    FutureProvider.autoDispose.family<Uint8List?, String>((ref, name) async {
      try {
        return await ref.watch(photoStoreProvider).read(name);
      } on Object {
        return null;
      }
    });

final class DayWindow {
  const new({required this.from, required this.to, required this.open});

  /// Wall clock of the first meal that opens the eating window.
  final DateTime from;

  /// Wall clock of the last window meal, or of now while today's window is
  /// open.
  final DateTime to;
  final bool open;
}

DayWindow? dayWindow(
  List<Meal> meals, {
  required LocalDate day,
  required DateTime now,
}) {
  final opening = [
    for (final meal in meals)
      if (opensWindow(meal.entry)) meal.entry.at,
  ]..sort();
  if (opening.isEmpty) return null;
  final from = opening.first;
  final open = !meals.any((meal) => meal.last) && day == foodDay(now);
  if (!open) return DayWindow(from: from, to: opening.last, open: false);
  final wallNow = DateTime.utc(
    now.year,
    now.month,
    now.day,
    now.hour,
    now.minute,
    now.second,
    now.millisecond,
    now.microsecond,
  );
  final to = wallNow.isBefore(from) ? from : wallNow;
  return DayWindow(from: from, to: to, open: true);
}

/// Maps ([hour], [minute]) on food [day] to local calendar time: hours before
/// [foodDayStartHour] belong to the following calendar morning.
DateTime mealTimeOnFoodDay(
  LocalDate day, {
  required int hour,
  required int minute,
}) {
  final calendar = hour < foodDayStartHour ? day.addDays(1) : day;
  return DateTime(calendar.year, calendar.month, calendar.day, hour, minute);
}

sealed class AddMealResult {
  const new();
}

final class AddMealSaved extends AddMealResult {
  const new(this.meal);

  final Meal meal;
}

final class AddMealFuture extends AddMealResult {
  const new();
}

final class AddMealFailed extends AddMealResult {
  const new();
}

sealed class EditTimeResult {
  const new();
}

final class EditTimeSaved extends EditTimeResult {
  const new();
}

final class EditTimeFuture extends EditTimeResult {
  const new();
}

final class EditTimeFailed extends EditTimeResult {
  const new();
}

final mealEditorProvider = Provider<MealEditor>(MealEditor.new);

final class MealEditor {
  const new(this._ref);

  final Ref _ref;

  Future<bool> save(Meal meal, MealEdit edit) async {
    if (edit.sameAs(meal)) return true;
    try {
      final saved = await _ref
          .read(mealStoreProvider)
          .update(meal.id, edit.draftOf(meal));
      if (saved) _ref.read(dataRevisionProvider.notifier).bump();
      return saved;
    } on Object {
      return false;
    }
  }

  Future<EditTimeResult> setTime(
    Meal meal, {
    required int hour,
    required int minute,
  }) async {
    final current = meal.entry.at;
    if (current.hour == hour && current.minute == minute) {
      return const EditTimeSaved();
    }
    final now = _ref.read(clockProvider)().toLocal();
    final at = mealTimeOnFoodDay(foodDay(current), hour: hour, minute: minute);
    if (at.isAfter(now)) return const EditTimeFuture();
    try {
      final saved = await _ref
          .read(mealStoreProvider)
          .update(
            meal.id,
            MealDraft(
              at: at.toUtc(),
              offsetMinutes: at.timeZoneOffset.inMinutes,
              kind: meal.kind,
              tags: meal.tags,
              last: meal.last,
            ),
          );
      if (!saved) return const EditTimeFailed();
      _ref.read(dataRevisionProvider.notifier).bump();
      return const EditTimeSaved();
    } on Object {
      return const EditTimeFailed();
    }
  }

  Future<bool> delete(int id) async {
    final Meal? removed;
    try {
      removed = await _ref.read(mealStoreProvider).delete(id);
    } on Object {
      return false;
    }
    if (removed == null) return false;
    if (removed.photo case final name?) {
      try {
        await _ref.read(photoStoreProvider).delete(name);
      } on Object {
        // Row is already gone; an orphaned photo cannot return to the UI.
      }
    }
    _ref.read(dataRevisionProvider.notifier).bump();
    return true;
  }

  Future<AddMealResult> addWithoutPhoto(
    LocalDate day, {
    required int hour,
    required int minute,
  }) async {
    final now = _ref.read(clockProvider)().toLocal();
    final at = mealTimeOnFoodDay(day, hour: hour, minute: minute);
    if (at.isAfter(now)) return const AddMealFuture();
    try {
      final meal = await _ref
          .read(mealStoreProvider)
          .add(
            MealDraft(
              at: at.toUtc(),
              offsetMinutes: at.timeZoneOffset.inMinutes,
            ),
            now: now.toUtc(),
          );
      _ref.read(dataRevisionProvider.notifier).bump();
      return AddMealSaved(meal);
    } on Object {
      return const AddMealFailed();
    }
  }
}
