import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:metrics/metrics.dart';
import 'package:open_ring/features/food/domain/exif.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';

enum SaveOutcome { saved, noSpace, failed }

enum TimeSource { photo, returned }

final class SaveResult {
  const new(this.outcome, this.time, [this.meal]);

  final SaveOutcome outcome;

  /// The row, also when only its photo is missing (noSpace).
  final Meal? meal;
  final TimeSource time;
}

const _photoAge = Duration(days: 7);
const _photoAhead = Duration(minutes: 2);
const _enospc = 28;

/// Strips the photo, writes the row, saves the file, then names the photo on
/// the row. A full disk (noSpace) keeps the row without a photo for
/// [retryPhoto]; any other failure deletes the row, and a photo that is not a
/// JPEG writes no row at all.
final class MealPhotoSaver {
  new(
    this._meals,
    this._photos, {
    DateTime Function()? now,
    Random? random,
    int Function(DateTime)? offsetAt,
  }) : _now = now ?? DateTime.now,
       _random = random ?? Random.secure(),
       _offsetAt = offsetAt ?? _deviceOffset;

  final MealStore _meals;
  final PhotoStore _photos;
  final DateTime Function() _now;
  final Random _random;
  final int Function(DateTime) _offsetAt;

  Future<SaveResult> save(Uint8List bytes) async {
    final now = _now();
    final (draft, source) = _draftFor(bytes, now);
    final stripped = _strip(bytes);
    if (stripped == null) return SaveResult(SaveOutcome.failed, source);
    final Meal meal;
    try {
      meal = await _meals.add(draft, now: now);
    } on Object {
      return SaveResult(SaveOutcome.failed, source);
    }
    final result = await _attach(meal, stripped, source);
    if (result.outcome != SaveOutcome.failed) return result;
    await _forget(meal.id);
    return result;
  }

  /// Attaches a photo to a row that a full disk left without one.
  Future<SaveResult> retryPhoto(int id, Uint8List bytes) async {
    final meal = await _find(id);
    final (_, source) = _draftFor(bytes, meal?.createdAt ?? _now());
    final stripped = _strip(bytes);
    if (meal == null || meal.photo != null || stripped == null) {
      return SaveResult(SaveOutcome.failed, source);
    }
    return await _attach(meal, stripped, source);
  }

  Future<SaveResult> _attach(
    Meal meal,
    Uint8List stripped,
    TimeSource source,
  ) async {
    final name = _nameFor(meal.at);
    try {
      await _photos.save(name, stripped);
      final attached = await _meals.attachPhoto(meal.id, name);
      if (attached) {
        return SaveResult(SaveOutcome.saved, source, _withPhoto(meal, name));
      }
    } on Object catch (error) {
      await _discard(name);
      if (!_isNoSpace(error)) return SaveResult(SaveOutcome.failed, source);
      return SaveResult(SaveOutcome.noSpace, source, meal);
    }
    await _discard(name);
    return SaveResult(SaveOutcome.failed, source);
  }

  (MealDraft, TimeSource) _draftFor(Uint8List bytes, DateTime now) {
    final photo = _instantOf(exifCaptureTime(bytes));
    final earliest = now.subtract(_photoAge);
    final latest = now.add(_photoAhead);
    if (photo == null ||
        photo.at.isBefore(earliest) ||
        photo.at.isAfter(latest)) {
      final draft = MealDraft(at: now, offsetMinutes: _offsetAt(now));
      return (draft, TimeSource.returned);
    }
    final draft = MealDraft(at: photo.at, offsetMinutes: photo.offset);
    return (draft, TimeSource.photo);
  }

  ({DateTime at, int offset})? _instantOf(ExifTime? time) {
    if (time == null) return null;
    final wall = time.wallClock;
    // The device offset is asked twice: first near the instant, then at it.
    final offset =
        time.offsetMinutes ?? _offsetAt(_shift(wall, _offsetAt(wall)));
    return (at: _shift(wall, offset), offset: offset);
  }

  String _nameFor(DateTime at) {
    final suffix = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return 'meal_${at.millisecondsSinceEpoch}_$suffix.jpg';
  }

  // MealStore reads by food day only; a retry is rare enough for a scan.
  Future<Meal?> _find(int id) async {
    try {
      final meals = await _meals.between(
        const LocalDate(1970, 1, 1),
        const LocalDate(9999, 12, 31),
      );
      return meals.where((meal) => meal.id == id).firstOrNull;
    } on Object {
      return null;
    }
  }

  Future<void> _discard(String name) async {
    try {
      await _photos.delete(name);
    } on Object {
      return;
    }
  }

  Future<void> _forget(int id) async {
    try {
      await _meals.delete(id);
    } on Object {
      return;
    }
  }
}

Uint8List? _strip(Uint8List bytes) {
  try {
    return stripExif(bytes);
  } on FormatException {
    return null;
  }
}

bool _isNoSpace(Object error) =>
    error is FileSystemException && error.osError?.errorCode == _enospc;

DateTime _shift(DateTime wall, int offsetMinutes) =>
    DateTime.fromMillisecondsSinceEpoch(
      wall.millisecondsSinceEpoch -
          offsetMinutes * Duration.millisecondsPerMinute,
      isUtc: true,
    );

int _deviceOffset(DateTime at) => at.toLocal().timeZoneOffset.inMinutes;

Meal _withPhoto(Meal meal, String name) => Meal(
  id: meal.id,
  at: meal.at,
  offsetMinutes: meal.offsetMinutes,
  createdAt: meal.createdAt,
  kind: meal.kind,
  tags: meal.tags,
  last: meal.last,
  photo: name,
);
