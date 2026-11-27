import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/food/application/meal_photo_saver.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';

import 'jpeg_fixture.dart';

// Instants are built as local wall clocks with the host offset, so a meal's
// own offset and the device offset agree on any test host.
int localOffset(DateTime at) => at.toLocal().timeZoneOffset.inMinutes;

/// No capture time inside, so the saver keeps the time it came back.
final Uint8List returnedPhoto = photoJpeg(
  exif: exifApp1(dateTimeOriginal: null, offsetTimeOriginal: null),
);

/// A capture time at [local], read with the device offset.
Uint8List photoTakenAt(DateTime local) => photoJpeg(
  exif: exifApp1(dateTimeOriginal: exifDate(local), offsetTimeOriginal: null),
);

final Uint8List notAJpeg = Uint8List.fromList(pngBytes);

/// A MealStore in memory that reads by food day like DriftMealStore.
final class TestMealStore implements MealStore {
  final List<Meal> _rows = [];
  var _nextId = 1;

  /// How many times [update] was called.
  int updates = 0;

  /// Thrown by [update] after it counts the call, when set.
  Exception? updateError;

  /// How many times [delete] was called.
  int deletes = 0;

  /// Thrown by [delete] after it counts the call, when set.
  Exception? deleteError;

  /// Thrown by [deletePhotosBefore] and [deleteAllPhotos] when set.
  Exception? deletePhotosError;

  List<Meal> get rows => List.unmodifiable(_rows);

  Meal seed(
    DateTime local, {
    MealKind? kind,
    MealTags tags = const MealTags(),
    bool last = false,
    String? photo,
  }) {
    final meal = Meal(
      id: _nextId++,
      at: local.toUtc(),
      offsetMinutes: localOffset(local),
      createdAt: local.toUtc(),
      kind: kind,
      tags: tags,
      last: last,
      photo: photo,
    );
    _rows.add(meal);
    return meal;
  }

  @override
  Future<Meal> add(
    MealDraft draft, {
    required DateTime now,
    String? photo,
  }) async {
    final meal = Meal(
      id: _nextId++,
      at: draft.at.toUtc(),
      offsetMinutes: draft.offsetMinutes,
      createdAt: now,
      kind: draft.kind,
      tags: draft.tags,
      last: draft.last,
      photo: photo,
    );
    _rows.add(meal);
    return meal;
  }

  @override
  Future<bool> update(int id, MealDraft draft) async {
    updates++;
    final error = updateError;
    if (error != null) throw error;
    final index = _rows.indexWhere((meal) => meal.id == id);
    if (index < 0) return false;
    final old = _rows[index];
    _rows[index] = Meal(
      id: id,
      at: draft.at.toUtc(),
      offsetMinutes: draft.offsetMinutes,
      createdAt: old.createdAt,
      kind: draft.kind,
      tags: draft.tags,
      last: draft.last,
      photo: old.photo,
    );
    return true;
  }

  @override
  Future<bool> attachPhoto(int id, String name) async {
    if (_rows.any((meal) => meal.photo == name && meal.id != id)) {
      throw StateError('another row holds $name');
    }
    final index = _rows.indexWhere((meal) => meal.id == id);
    if (index < 0) return false;
    final old = _rows[index];
    _rows[index] = Meal(
      id: id,
      at: old.at,
      offsetMinutes: old.offsetMinutes,
      createdAt: old.createdAt,
      kind: old.kind,
      tags: old.tags,
      last: old.last,
      photo: name,
    );
    return true;
  }

  @override
  Future<Meal?> byId(int id) async {
    final index = _rows.indexWhere((meal) => meal.id == id);
    if (index < 0) return null;
    return _rows[index];
  }

  @override
  Future<Meal?> delete(int id) async {
    deletes++;
    final error = deleteError;
    if (error != null) throw error;
    final index = _rows.indexWhere((meal) => meal.id == id);
    if (index < 0) return null;
    return _rows.removeAt(index);
  }

  @override
  Future<List<Meal>> between(LocalDate from, LocalDate to) async {
    final found = [
      for (final meal in _rows)
        if (foodDay(meal.entry.at).compareTo(from) >= 0 &&
            foodDay(meal.entry.at).compareTo(to) <= 0)
          meal,
    ]..sort((a, b) => a.entry.at.compareTo(b.entry.at));
    return found;
  }

  @override
  Future<int> count() async => _rows.length;

  @override
  Future<int> clear() async {
    final removed = _rows.length;
    _rows.clear();
    return removed;
  }

  @override
  Future<List<MealPhotoRef>> photoRefs() async {
    final ordered = [
      for (final meal in _rows)
        if (meal.photo != null) meal,
    ]..sort(_byCaptureOrder);
    return [
      for (final meal in ordered)
        MealPhotoRef(
          at: meal.at,
          offsetMinutes: meal.offsetMinutes,
          photo: meal.photo!,
        ),
    ];
  }

  @override
  Future<List<String>> deletePhotosBefore(DateTime cutoff) =>
      _releasePhotosWhere(
        (meal) => meal.photo != null && meal.at.isBefore(cutoff),
      );

  @override
  Future<List<String>> deleteAllPhotos() =>
      _releasePhotosWhere((meal) => meal.photo != null);

  Future<List<String>> _releasePhotosWhere(
    bool Function(Meal meal) test,
  ) async {
    final error = deletePhotosError;
    if (error != null) throw error;
    final matched = [
      for (var index = 0; index < _rows.length; index++)
        if (test(_rows[index])) index,
    ]..sort((a, b) => _byCaptureOrder(_rows[a], _rows[b]));
    final released = <String>[];
    for (final index in matched) {
      final old = _rows[index];
      released.add(old.photo!);
      _rows[index] = Meal(
        id: old.id,
        at: old.at,
        offsetMinutes: old.offsetMinutes,
        createdAt: old.createdAt,
        kind: old.kind,
        tags: old.tags,
        last: old.last,
      );
    }
    return released;
  }

  int _byCaptureOrder(Meal a, Meal b) {
    final byAt = a.at.compareTo(b.at);
    return byAt != 0 ? byAt : a.id.compareTo(b.id);
  }
}

/// Fails every save with errno 28 until [full] is cleared.
final class FullPhotoStore implements PhotoStore {
  bool full = true;
  final inner = InMemoryPhotoStore();

  @override
  Future<void> save(String name, Uint8List bytes) async {
    if (full) {
      throw const FileSystemException(
        'Cannot write file',
        'meal.jpg.tmp',
        OSError('No space left on device', 28),
      );
    }
    await inner.save(name, bytes);
  }

  @override
  Future<Uint8List?> read(String name) => inner.read(name);

  @override
  Future<bool> delete(String name) => inner.delete(name);

  @override
  Future<int> deleteAll() => inner.deleteAll();

  @override
  Future<Map<String, int>> fileBytes() => inner.fileBytes();

  @override
  Future<int> totalBytes() => inner.totalBytes();
}

/// Holds the shutter open until [open] is called.
final class GatedMealCamera implements MealCamera {
  final _shot = Completer<Uint8List?>();
  int takes = 0;

  void open(Uint8List? bytes) => _shot.complete(bytes);

  @override
  Future<Uint8List?> takePhoto() {
    takes++;
    return _shot.future;
  }

  @override
  Future<Uint8List?> retrieveLost() async => null;
}

/// Throws as image_picker does when the camera cannot open.
final class ThrowingMealCamera implements MealCamera {
  @override
  Future<Uint8List?> takePhoto() async =>
      throw PlatformException(code: 'camera_access_denied');

  @override
  Future<Uint8List?> retrieveLost() async => null;
}

/// Records whether any food store was built, each one throwing as unset.
final class StoreReads {
  bool meals = false;
  bool photos = false;
  bool camera = false;

  bool get any => meals || photos || camera;

  List<Override> overrides() => [
    mealStoreProvider.overrideWith((ref) {
      meals = true;
      throw UnimplementedError('Override mealStoreProvider.');
    }),
    photoStoreProvider.overrideWith((ref) {
      photos = true;
      throw UnimplementedError('Override photoStoreProvider.');
    }),
    mealCameraProvider.overrideWith((ref) {
      camera = true;
      throw UnimplementedError('Override mealCameraProvider.');
    }),
  ];
}

List<Override> foodOverrides({
  required TestMealStore meals,
  required MealCamera camera,
  required DateTime Function() clock,
  PhotoStore? photos,
  bool foodOn = true,
}) => [
  moduleStoreProvider.overrideWithValue(
    InMemoryModuleStore({if (foodOn) ModuleId.food}),
  ),
  clockProvider.overrideWithValue(clock),
  ...foodStoreOverrides(
    meals: meals,
    camera: camera,
    clock: clock,
    photos: photos,
  ),
];

/// The stores, camera and saver alone, for screens that set the clock and
/// the modules themselves.
List<Override> foodStoreOverrides({
  required TestMealStore meals,
  required MealCamera camera,
  required DateTime Function() clock,
  PhotoStore? photos,
}) => [
  mealStoreProvider.overrideWithValue(meals),
  photoStoreProvider.overrideWithValue(photos ?? InMemoryPhotoStore()),
  mealCameraProvider.overrideWithValue(camera),
  mealPhotoSaverProvider.overrideWith(
    (ref) => MealPhotoSaver(
      ref.watch(mealStoreProvider),
      ref.watch(photoStoreProvider),
      now: clock,
      random: Random(7),
      offsetAt: localOffset,
    ),
  ),
];
