import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/food/application/meal_photo_saver.dart';
import 'package:open_ring/features/food/domain/exif.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/infrastructure/drift_meal_store.dart';

import '../../../helpers/database.dart';
import '../jpeg_fixture.dart';

/// 2026-12-10 19:32:05 at -03:00, the time inside [_photo].
final _instant = DateTime.utc(2026, 12, 10, 22, 32, 5);

final Uint8List _photo = photoJpeg();

final _namePattern = RegExp(r'^meal_(\d+)_[0-9a-fA-F]{8}\.jpg$');

const _noSpace = FileSystemException(
  'Cannot write file',
  'meal.jpg.tmp',
  OSError('No space left on device', 28),
);

Uint8List _jpegAt(DateTime wall, {String? offset}) => photoJpeg(
  exif: exifApp1(dateTimeOriginal: exifDate(wall), offsetTimeOriginal: offset),
);

final class _FailingPhotoStore implements PhotoStore {
  new(this.error);

  Object? error;
  final inner = InMemoryPhotoStore();

  @override
  Future<void> save(String name, Uint8List bytes) async {
    final failure = error;
    if (failure != null) Error.throwWithStackTrace(failure, StackTrace.current);
    await inner.save(name, bytes);
  }

  @override
  Future<Uint8List?> read(String name) => inner.read(name);

  @override
  Future<bool> delete(String name) => inner.delete(name);

  @override
  Future<int> deleteAll() => inner.deleteAll();

  @override
  Future<int> totalBytes() => inner.totalBytes();
}

final class _WatchingPhotoStore implements PhotoStore {
  new(this.meals);

  final MealStore meals;
  final inner = InMemoryPhotoStore();
  final seenAtSave = <List<String?>>[];

  @override
  Future<void> save(String name, Uint8List bytes) async {
    final rows = await meals.between(
      const LocalDate(2000, 1, 1),
      const LocalDate(2100, 1, 1),
    );
    seenAtSave.add([for (final row in rows) row.photo]);
    await inner.save(name, bytes);
  }

  @override
  Future<Uint8List?> read(String name) => inner.read(name);

  @override
  Future<bool> delete(String name) => inner.delete(name);

  @override
  Future<int> deleteAll() => inner.deleteAll();

  @override
  Future<int> totalBytes() => inner.totalBytes();
}

final class _BrokenMealStore implements MealStore {
  @override
  Future<Meal> add(MealDraft draft, {required DateTime now, String? photo}) =>
      throw StateError('database is locked');

  @override
  Future<bool> attachPhoto(int id, String name) =>
      throw StateError('database is locked');

  @override
  Future<bool> update(int id, MealDraft draft) =>
      throw StateError('database is locked');

  @override
  Future<Meal?> delete(int id) => throw StateError('database is locked');

  @override
  Future<List<Meal>> between(LocalDate from, LocalDate to) async => const [];

  @override
  Future<int> count() async => 0;

  @override
  Future<int> clear() async => 0;

  @override
  Future<List<String>> deletePhotosBefore(DateTime cutoff) async => const [];
}

void main() {
  late MealStore meals;
  late InMemoryPhotoStore photos;

  setUp(() {
    meals = DriftMealStore(memoryDatabase());
    photos = InMemoryPhotoStore();
  });

  Future<List<Meal>> rows() =>
      meals.between(const LocalDate(2000, 1, 1), const LocalDate(2100, 1, 1));

  MealPhotoSaver saverAt(
    DateTime now, {
    PhotoStore? store,
    MealStore? mealStore,
    int Function(DateTime)? offsetAt,
  }) => MealPhotoSaver(
    mealStore ?? meals,
    store ?? photos,
    now: () => now,
    random: Random(7),
    offsetAt: offsetAt ?? (_) => -180,
  );

  group('criterion 3: save stores the stripped photo under a valid name', () {
    final now = _instant.add(const Duration(minutes: 20));

    test(
      'the name is meal_<atUtcMs>_<8 hex>.jpg and passes isMealPhotoName',
      () async {
        final result = await saverAt(now).save(_photo);

        expect(result.outcome, SaveOutcome.saved);
        final meal = result.meal!;
        final name = meal.photo!;
        expect(name, matches(_namePattern));
        expect(isMealPhotoName(name), isTrue);
        expect(
          _namePattern.firstMatch(name)!.group(1),
          '${meal.at.millisecondsSinceEpoch}',
        );
      },
    );

    test('the stored file equals stripExif(input)', () async {
      final result = await saverAt(now).save(_photo);

      expect(await photos.read(result.meal!.photo!), stripExif(_photo));
      expect(await photos.totalBytes(), stripExif(_photo).length);
    });

    test('the stored row names that file', () async {
      final result = await saverAt(now).save(_photo);

      final stored = (await rows()).single;
      expect(stored.id, result.meal!.id);
      expect(stored.photo, result.meal!.photo);
      expect(stored.createdAt, now);
    });

    test('two photos in the same second get two names and two rows', () async {
      final saver = saverAt(now);
      final first = await saver.save(_photo);
      final second = await saver.save(_photo);

      expect(second.outcome, SaveOutcome.saved);
      expect(second.meal!.photo, isNot(first.meal!.photo));
      expect(await meals.count(), 2);
    });

    test('the row names its photo only after the file exists', () async {
      final watching = _WatchingPhotoStore(meals);

      final result = await saverAt(now, store: watching).save(_photo);

      expect(result.outcome, SaveOutcome.saved);
      expect(
        watching.seenAtSave,
        [
          [null],
        ],
        reason: 'D4: the row exists, without its photo, when the file is saved',
      );
      expect((await rows()).single.photo, result.meal!.photo);
    });
  });

  group('criterion 3: the meal time is the photo time inside the window', () {
    Future<(Meal, TimeSource)> saveAt(DateTime now, Uint8List bytes) async {
      final result = await saverAt(now, offsetAt: (_) => -120).save(bytes);
      expect(result.outcome, SaveOutcome.saved);
      return (result.meal!, result.time);
    }

    test('20 minutes old: the photo time and its own offset', () async {
      final (meal, source) = await saveAt(
        _instant.add(const Duration(minutes: 20)),
        _photo,
      );

      expect(source, TimeSource.photo);
      expect(meal.at, _instant);
      expect(meal.offsetMinutes, -180);
      expect(meal.entry.at, DateTime.utc(2026, 12, 10, 19, 32, 5));
    });

    test('exactly 7 days old is still the photo time', () async {
      final (meal, source) = await saveAt(
        _instant.add(const Duration(days: 7)),
        _photo,
      );

      expect((source, meal.at), (TimeSource.photo, _instant));
    });

    test('exactly 2 minutes ahead is still the photo time', () async {
      final (meal, source) = await saveAt(
        _instant.subtract(const Duration(minutes: 2)),
        _photo,
      );

      expect((source, meal.at), (TimeSource.photo, _instant));
    });

    test('recovered 3 days later it keeps the photo time', () async {
      final (meal, source) = await saveAt(
        _instant.add(const Duration(days: 3)),
        _photo,
      );

      expect(
        (source, meal.at, meal.offsetMinutes),
        (TimeSource.photo, _instant, -180),
      );
    });
  });

  group('criterion 3: outside the window the meal takes now', () {
    Future<void> expectNow(DateTime now, Uint8List bytes) async {
      final result = await saverAt(now, offsetAt: (_) => -120).save(bytes);

      expect(result.outcome, SaveOutcome.saved);
      expect(result.time, TimeSource.returned);
      expect(result.meal!.at, now);
      expect(result.meal!.offsetMinutes, -120);
    }

    test('8 days old', () async {
      await expectNow(_instant.add(const Duration(days: 8)), _photo);
    });

    test('one second past 7 days', () async {
      await expectNow(
        _instant.add(const Duration(days: 7, seconds: 1)),
        _photo,
      );
    });

    test('10 minutes ahead', () async {
      await expectNow(_instant.subtract(const Duration(minutes: 10)), _photo);
    });

    test('one second past 2 minutes ahead', () async {
      await expectNow(
        _instant.subtract(const Duration(minutes: 2, seconds: 1)),
        _photo,
      );
    });

    test('no capture time in the photo', () async {
      await expectNow(
        _instant,
        photoJpeg(
          exif: exifApp1(dateTimeOriginal: null, offsetTimeOriginal: null),
        ),
      );
    });

    test('a zero date in the photo', () async {
      await expectNow(
        _instant,
        photoJpeg(exif: exifApp1(dateTimeOriginal: '0000:00:00 00:00:00')),
      );
    });
  });

  group('D2: no offset tag takes the device offset at the photo instant', () {
    // A zone at -03:00 until 8 December and -02:00 after, so now and the
    // photo sit on different sides of a DST change.
    int offsetAt(DateTime at) =>
        at.isBefore(DateTime.utc(2026, 12, 8)) ? -180 : -120;

    test('a photo from before the change keeps the old offset', () async {
      final now = DateTime.utc(2026, 12, 10, 12);
      final bytes = _jpegAt(DateTime.utc(2026, 12, 5, 12));

      final result = await saverAt(now, offsetAt: offsetAt).save(bytes);

      expect(result.time, TimeSource.photo);
      expect(result.meal!.offsetMinutes, -180);
      expect(result.meal!.at, DateTime.utc(2026, 12, 5, 15));
      expect(result.meal!.entry.at, DateTime.utc(2026, 12, 5, 12));
    });

    test('a photo after the change takes the new offset', () async {
      final now = DateTime.utc(2026, 12, 10, 12);
      final bytes = _jpegAt(DateTime.utc(2026, 12, 9, 12));

      final result = await saverAt(now, offsetAt: offsetAt).save(bytes);

      expect(result.meal!.offsetMinutes, -120);
      expect(result.meal!.at, DateTime.utc(2026, 12, 9, 14));
    });
  });

  group('criterion 4: errno 28 keeps the row without a photo', () {
    final now = _instant.add(const Duration(minutes: 20));

    test('outcome noSpace, one row, no photo on it, no file', () async {
      final full = _FailingPhotoStore(_noSpace);

      final result = await saverAt(now, store: full).save(_photo);

      expect(result.outcome, SaveOutcome.noSpace);
      expect(result.meal, isNotNull);
      expect(result.meal!.photo, isNull);
      expect(result.meal!.at, _instant, reason: 'the time is already kept');
      expect(await meals.count(), 1);
      expect((await rows()).single.photo, isNull);
      expect(await full.inner.totalBytes(), 0);
    });

    test('retryPhoto attaches the photo once there is space', () async {
      final full = _FailingPhotoStore(_noSpace);
      final saver = saverAt(now, store: full);
      final first = await saver.save(_photo);
      full.error = null;

      final retry = await saver.retryPhoto(first.meal!.id, _photo);

      expect(retry.outcome, SaveOutcome.saved);
      final name = retry.meal!.photo!;
      expect(isMealPhotoName(name), isTrue);
      expect(await full.inner.read(name), stripExif(_photo));
      expect(await meals.count(), 1);
      expect((await rows()).single.photo, name);
    });

    test(
      'retryPhoto while still full is noSpace and attaches nothing',
      () async {
        final full = _FailingPhotoStore(_noSpace);
        final saver = saverAt(now, store: full);
        final first = await saver.save(_photo);

        final retry = await saver.retryPhoto(first.meal!.id, _photo);

        expect(retry.outcome, SaveOutcome.noSpace);
        expect((await rows()).single.photo, isNull);
      },
    );

    test('retryPhoto for an unknown id is failed', () async {
      final retry = await saverAt(now).retryPhoto(404, _photo);

      expect(retry.outcome, SaveOutcome.failed);
      expect(await meals.count(), 0);
    });
  });

  group('criterion 4: any other error, or non JPEG input, is failed', () {
    final now = _instant.add(const Duration(minutes: 20));

    final otherErrors = <String, Object>{
      'errno 13': const FileSystemException(
        'Cannot write file',
        'meal.jpg.tmp',
        OSError('Permission denied', 13),
      ),
      'a FileSystemException without an OS error': const FileSystemException(
        'Cannot write file',
      ),
      'a StateError': StateError('boom'),
    };

    for (final MapEntry(key: name, value: error) in otherErrors.entries) {
      test('$name from the photo save', () async {
        final failing = _FailingPhotoStore(error);

        final result = await saverAt(now, store: failing).save(_photo);

        expect(result.outcome, SaveOutcome.failed);
        expect(await failing.inner.totalBytes(), 0);
        expect([for (final m in await rows()) m.photo], everyElement(isNull));
      });
    }

    test('a row write error saves no file', () async {
      final result = await saverAt(
        now,
        mealStore: _BrokenMealStore(),
      ).save(_photo);

      expect(result.outcome, SaveOutcome.failed);
      expect(await photos.totalBytes(), 0);
    });

    final notJpeg = <String, List<int>>{
      'PNG': pngBytes,
      'HEIC': heicBytes,
      'empty': const [],
    };

    for (final MapEntry(key: name, value: bytes) in notJpeg.entries) {
      test('$name input', () async {
        final result = await saverAt(now).save(Uint8List.fromList(bytes));

        expect(result.outcome, SaveOutcome.failed);
        expect(await photos.totalBytes(), 0);
        expect([for (final m in await rows()) m.photo], everyElement(isNull));
      });
    }

    test('a JPEG whose APP1 runs past the end', () async {
      final bytes = bytesOf([soi, app0, exifApp1()]);
      bytes[soi.length + app0.length + 2] = 0xFF;

      final result = await saverAt(now).save(bytes);

      expect(result.outcome, SaveOutcome.failed);
      expect(await photos.totalBytes(), 0);
    });
  });
}
