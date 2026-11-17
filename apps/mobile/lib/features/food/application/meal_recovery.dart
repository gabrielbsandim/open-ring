import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/food/application/meal_photo_saver.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';

final NotifierProvider<MealRecovery, SaveResult?> mealRecoveryProvider =
    NotifierProvider(MealRecovery.new);

/// Saves the photo Android took while it killed the app, once per start.
class MealRecovery extends Notifier<SaveResult?> {
  Future<void>? _run;

  @override
  SaveResult? build() => null;

  Future<void> run() => _run ??= _recover();

  Future<void> _recover() async {
    final Uint8List? lost;
    try {
      lost = await ref.read(mealCameraProvider).retrieveLost();
    } on Exception {
      return;
    }
    if (lost == null) return;
    final result = await ref.read(mealPhotoSaverProvider).save(lost);
    if (!ref.mounted) return;
    state = result;
  }
}
