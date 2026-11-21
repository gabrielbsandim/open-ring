import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';

const photoOldThreeMonthsDays = 90;
const photoOldOneYearDays = 365;
const photoPaceMinDays = 7;
const _bytesPerKb = 1000;
const int _bytesPerMb = _bytesPerKb * 1000;

enum PhotoPurgeRange {
  olderThanThreeMonths(photoOldThreeMonthsDays),
  olderThanOneYear(photoOldOneYearDays),
  all(0);

  new(this.days);

  final int days;

  DateTime cutoff(DateTime nowUtc) => nowUtc.subtract(Duration(days: days));
}

@immutable
final class PhotoPurgePreview {
  const new({required this.count, required this.bytes});

  final int count;
  final int bytes;

  @override
  bool operator ==(Object other) =>
      other is PhotoPurgePreview &&
      other.count == count &&
      other.bytes == bytes;

  @override
  int get hashCode => Object.hash(count, bytes);
}

@immutable
final class FoodPhotoStorageView {
  const new({
    required this.asOf,
    required this.photoCount,
    required this.totalBytes,
    required this.averageBytes,
    required this.earliestDay,
    required this.projectedBytesPerYear,
    required this.previews,
  });

  final DateTime asOf;
  final int photoCount;
  final int totalBytes;
  final int? averageBytes;
  final LocalDate? earliestDay;
  final int? projectedBytesPerYear;
  final Map<PhotoPurgeRange, PhotoPurgePreview> previews;

  bool get canDeleteAny => photoCount > 0 || totalBytes > 0;
}

@immutable
final class PhotoPurgeResult {
  const new({required this.removedPhotos, required this.freedBytes});

  final int removedPhotos;
  final int freedBytes;
}

String formatPhotoBytes(MetricFormat format, int bytes) {
  if (bytes <= 0) {
    return format.l10n.foodPhotosSizeMb(format.decimal(0, digits: 1));
  }
  if (bytes < _bytesPerMb) {
    return format.l10n.foodPhotosSizeKb(
      format.integer(max(1, (bytes / _bytesPerKb).round())),
    );
  }
  return format.l10n.foodPhotosSizeMb(
    format.decimal(bytes / _bytesPerMb, digits: 1),
  );
}

FoodPhotoStorageView buildFoodPhotoStorageView({
  required DateTime now,
  required List<MealPhotoRef> refs,
  required Map<String, int> fileSizes,
  required int totalBytes,
}) {
  final nowUtc = now.toUtc();
  final ordered = [...refs]..sort((a, b) => a.at.compareTo(b.at));
  var referencedBytes = 0;
  var present = 0;
  MealPhotoRef? firstPresent;
  for (final ref in ordered) {
    final size = fileSizes[ref.photo];
    if (size == null) continue;
    firstPresent ??= ref;
    referencedBytes += size;
    present++;
  }
  final spanDays = firstPresent == null
      ? 0
      : max(0, nowUtc.difference(firstPresent.at).inDays);

  PhotoPurgePreview before(PhotoPurgeRange range) {
    final limit = range.cutoff(nowUtc);
    var count = 0;
    var bytes = 0;
    for (final ref in ordered) {
      if (!ref.at.isBefore(limit)) continue;
      count++;
      bytes += fileSizes[ref.photo] ?? 0;
    }
    return PhotoPurgePreview(count: count, bytes: bytes);
  }

  return FoodPhotoStorageView(
    asOf: nowUtc,
    photoCount: ordered.length,
    totalBytes: totalBytes,
    averageBytes: present == 0 ? null : (referencedBytes / present).round(),
    earliestDay: firstPresent == null ? null : foodDay(firstPresent.wallClock),
    projectedBytesPerYear: present >= 2 && spanDays >= photoPaceMinDays
        ? (referencedBytes * 365 / spanDays).round()
        : null,
    previews: {
      PhotoPurgeRange.olderThanThreeMonths: before(
        PhotoPurgeRange.olderThanThreeMonths,
      ),
      PhotoPurgeRange.olderThanOneYear: before(
        PhotoPurgeRange.olderThanOneYear,
      ),
      PhotoPurgeRange.all: PhotoPurgePreview(
        count: ordered.length,
        bytes: totalBytes,
      ),
    },
  );
}

// Not gated on the module so stored photos can still be freed while Food is off.
final foodPhotoStorageProvider = FutureProvider<FoodPhotoStorageView>((
  ref,
) async {
  ref.watch(dataRevisionProvider);
  final now = ref.watch(clockProvider)();
  final meals = ref.watch(mealStoreProvider);
  final photos = ref.watch(photoStoreProvider);
  return buildFoodPhotoStorageView(
    now: now,
    refs: await meals.photoRefs(),
    fileSizes: await photos.fileBytes(),
    totalBytes: await photos.totalBytes(),
  );
});

final foodPhotoPurgerProvider = Provider<FoodPhotoPurger>(FoodPhotoPurger.new);

class FoodPhotoPurger {
  const new(this._ref);

  final Ref _ref;

  /// Clears DB photo columns first, then deletes files on disk and bumps the
  /// revision so no row ever points at a missing file.
  Future<PhotoPurgeResult?> purge(
    PhotoPurgeRange range, {
    DateTime? asOf,
  }) async {
    final nowUtc = (asOf ?? _ref.read(clockProvider)()).toUtc();
    final meals = _ref.read(mealStoreProvider);
    final photos = _ref.read(photoStoreProvider);
    final Map<String, int> sizesBefore;
    final int totalBefore;
    final List<String> released;
    try {
      sizesBefore = await photos.fileBytes();
      totalBefore = await photos.totalBytes();
      released = range == PhotoPurgeRange.all
          ? await meals.deleteAllPhotos()
          : await meals.deletePhotosBefore(range.cutoff(nowUtc));
    } on Object catch (error) {
      debugPrint('Food photos were not deleted: $error');
      return null;
    }
    final freed = await _deleteFiles(
      photos,
      range,
      released,
      sizesBefore,
      totalBefore,
    );
    if (_ref.mounted) _ref.read(dataRevisionProvider.notifier).bump();
    return PhotoPurgeResult(removedPhotos: released.length, freedBytes: freed);
  }

  Future<int> _deleteFiles(
    PhotoStore photos,
    PhotoPurgeRange range,
    List<String> released,
    Map<String, int> sizesBefore,
    int totalBefore,
  ) async {
    if (range == PhotoPurgeRange.all) {
      var remaining = totalBefore;
      try {
        await photos.deleteAll();
        remaining = await photos.totalBytes();
      } on Object catch (error) {
        debugPrint('Failed to empty meal photo directory: $error');
      }
      return max(0, totalBefore - remaining);
    }
    var freed = 0;
    for (final name in released) {
      try {
        if (await photos.delete(name)) freed += sizesBefore[name] ?? 0;
      } on Object catch (error) {
        debugPrint('Failed to delete meal photo $name: $error');
      }
    }
    return freed;
  }
}
