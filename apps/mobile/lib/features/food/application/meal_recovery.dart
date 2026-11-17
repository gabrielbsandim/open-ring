import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/food/application/meal_photo_saver.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';

final NotifierProvider<MealRecovery, SaveResult?> mealRecoveryProvider =
    NotifierProvider(MealRecovery.new);

/// Saves the photo Android took while it killed the app, once per start.
class MealRecovery extends Notifier<SaveResult?> {
  Future<void>? _run;

  // The platform hands a lost photo out once, so a full disk keeps it here.
  Uint8List? _pending;

  @override
  SaveResult? build() => null;

  Future<void> run() => _run ??= _recover();

  /// Attaches the photo a full disk kept off its row; a no op otherwise.
  Future<void> retry() async {
    final bytes = _pending;
    final meal = state?.meal;
    if (bytes == null || meal == null) return;
    final result = await ref
        .read(mealPhotoSaverProvider)
        .retryPhoto(meal.id, bytes);
    _keep(result, bytes);
  }

  /// Forgets the result once its sheet is closed, so it does not open again.
  void clear() {
    _pending = null;
    state = null;
  }

  Future<void> _recover() async {
    final Uint8List? lost;
    try {
      lost = await ref.read(mealCameraProvider).retrieveLost();
    } on Exception {
      return;
    }
    if (lost == null) return;
    _keep(await ref.read(mealPhotoSaverProvider).save(lost), lost);
  }

  void _keep(SaveResult result, Uint8List bytes) {
    _pending = result.outcome == SaveOutcome.noSpace ? bytes : null;
    if (!ref.mounted) return;
    state = result;
  }
}
