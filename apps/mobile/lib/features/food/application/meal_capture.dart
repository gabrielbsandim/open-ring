import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/meal_photo_saver.dart';
import 'package:open_ring/features/food/application/meal_recovery.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';

final class CaptureState {
  const new({this.saving = false, this.result, this.recovered = false});

  final bool saving;
  final SaveResult? result;

  /// Whether [result] is a photo lost to a killed app and saved at start.
  final bool recovered;
}

final NotifierProvider<MealCapture, CaptureState> mealCaptureProvider =
    NotifierProvider(MealCapture.new);

/// Takes a meal photo and saves it, then holds the result until the sheet
/// that shows it is closed.
class MealCapture extends Notifier<CaptureState> {
  // A full disk keeps the bytes here, for retry.
  Uint8List? _bytes;

  @override
  CaptureState build() {
    ref.listen(mealRecoveryProvider, (_, next) => _recovered(next));
    final pending = ref.read(mealRecoveryProvider);
    if (pending == null) return const CaptureState();
    return CaptureState(result: pending, recovered: true);
  }

  Future<void> capture() async {
    if (state.saving) return;
    state = const CaptureState(saving: true);
    final result = await _shoot();
    if (!ref.mounted) return;
    state = CaptureState(result: result);
    if (result?.meal != null) _bump();
  }

  /// Tries again to attach the photo a full disk kept off its row.
  Future<void> retry() async {
    if (state.recovered) {
      await ref.read(mealRecoveryProvider.notifier).retry();
      return;
    }
    final bytes = _bytes;
    final meal = state.result?.meal;
    if (bytes == null || meal == null) return;
    final result = await ref
        .read(mealPhotoSaverProvider)
        .retryPhoto(meal.id, bytes);
    if (!ref.mounted) return;
    _bytes = result.outcome == SaveOutcome.noSpace ? bytes : null;
    state = CaptureState(result: result);
    if (result.outcome == SaveOutcome.saved) _bump();
  }

  /// Deletes the row a full disk left without a photo.
  Future<void> discard() async {
    final meal = state.result?.meal;
    final removed = meal != null && await _deletePhotoless(meal);
    _settle();
    if (removed) _bump();
  }

  /// Writes the last meal switch when it changed, then lets the result go.
  Future<void> finish({required bool last}) async {
    final meal = state.result?.meal;
    final changed =
        meal != null && meal.last != last && await _write(meal, last);
    _settle();
    if (changed) _bump();
  }

  Future<SaveResult?> _shoot() async {
    try {
      final bytes = await ref.read(mealCameraProvider).takePhoto();
      if (bytes == null) return null;
      final result = await ref.read(mealPhotoSaverProvider).save(bytes);
      _bytes = result.outcome == SaveOutcome.noSpace ? bytes : null;
      return result;
    } on Object {
      // A new object per failure: the row opens one sheet per result.
      // ignore: prefer_const_constructors
      return SaveResult(SaveOutcome.failed, TimeSource.returned);
    }
  }

  void _recovered(SaveResult? next) {
    if (next == null) return;
    _bytes = null;
    state = CaptureState(result: next, recovered: true);
    if (next.meal != null) _bump();
  }

  // The photo may have landed since the sheet opened; such a row stays.
  Future<bool> _deletePhotoless(Meal meal) async {
    final store = ref.read(mealStoreProvider);
    final day = foodDay(meal.entry.at);
    try {
      final rows = await store.between(day, day);
      final current = rows.where((row) => row.id == meal.id).firstOrNull;
      if (current == null || current.photo != null) return false;
      return await store.delete(meal.id) != null;
    } on Object {
      return false;
    }
  }

  Future<bool> _write(Meal meal, bool last) async {
    final draft = MealDraft(
      at: meal.at,
      offsetMinutes: meal.offsetMinutes,
      kind: meal.kind,
      tags: meal.tags,
      last: last,
    );
    try {
      return await ref.read(mealStoreProvider).update(meal.id, draft);
    } on Object {
      return false;
    }
  }

  void _settle() {
    if (!ref.mounted) return;
    if (state.recovered) ref.read(mealRecoveryProvider.notifier).clear();
    _bytes = null;
    state = const CaptureState();
  }

  void _bump() {
    if (!ref.mounted) return;
    ref.read(dataRevisionProvider.notifier).bump();
  }
}
