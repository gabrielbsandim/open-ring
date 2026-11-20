import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/gallery_backfill.dart';
import 'package:open_ring/features/food/application/meal_photo_saver.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/exif.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/meal_gallery.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';

import '../food_fakes.dart';
import '../jpeg_fixture.dart';

final Matcher _unimplemented = predicate<Object>(
  (error) =>
      error is UnimplementedError ||
      (error is ProviderException && error.exception is UnimplementedError),
  'UnimplementedError',
);

Uint8List _jpegUtc(DateTime utcWall, {String offset = '+00:00'}) => photoJpeg(
  exif: exifApp1(
    dateTimeOriginal: exifDate(utcWall),
    offsetTimeOriginal: offset,
  ),
);

final class _GatedMealGallery implements MealGallery {
  final _picked = Completer<List<Uint8List>>();
  int calls = 0;

  void complete(List<Uint8List> photos) => _picked.complete(photos);

  @override
  Future<List<Uint8List>> pickPhotos({int limit = galleryPickLimit}) {
    calls++;
    return _picked.future;
  }
}

final class _CountingNoSpacePhotoStore implements PhotoStore {
  new({required this.failOnCall});

  final int failOnCall;
  int saves = 0;
  final inner = InMemoryPhotoStore();

  @override
  Future<void> save(String name, Uint8List bytes) async {
    saves++;
    if (saves == failOnCall) {
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
  Future<int> totalBytes() => inner.totalBytes();
}

final class _GatedPhotoStore implements PhotoStore {
  final _gate = Completer<void>();
  int saves = 0;
  final inner = InMemoryPhotoStore();

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<void> save(String name, Uint8List bytes) async {
    saves++;
    await _gate.future;
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

final class _BrokenPhotoStore implements PhotoStore {
  final inner = InMemoryPhotoStore();

  @override
  Future<void> save(String name, Uint8List bytes) async {
    throw const FileSystemException(
      'Cannot write file',
      'meal.jpg.tmp',
      OSError('Permission denied', 13),
    );
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

final class _SpyMealStore implements MealStore {
  new(this._inner);

  final TestMealStore _inner;
  final betweenCalls = <(LocalDate, LocalDate)>[];

  @override
  Future<Meal> add(MealDraft draft, {required DateTime now, String? photo}) =>
      _inner.add(draft, now: now, photo: photo);

  @override
  Future<bool> attachPhoto(int id, String name) => _inner.attachPhoto(id, name);

  @override
  Future<List<Meal>> between(LocalDate from, LocalDate to) {
    betweenCalls.add((from, to));
    return _inner.between(from, to);
  }

  @override
  Future<int> clear() => _inner.clear();

  @override
  Future<int> count() => _inner.count();

  @override
  Future<Meal?> delete(int id) => _inner.delete(id);

  @override
  Future<List<String>> deletePhotosBefore(DateTime cutoff) =>
      _inner.deletePhotosBefore(cutoff);

  @override
  Future<bool> update(int id, MealDraft draft) => _inner.update(id, draft);
}

void main() {
  final nowUtc = DateTime.utc(2026, 11, 20, 14);
  final nowLocal = DateTime(2026, 11, 20, 14);
  late TestMealStore meals;
  late InMemoryPhotoStore photos;

  setUp(() {
    meals = TestMealStore();
    photos = InMemoryPhotoStore();
  });

  Future<ProviderContainer> containerWith({
    required MealGallery gallery,
    MealStore? mealStore,
    PhotoStore? photoStore,
    DateTime Function()? clock,
    bool foodOn = true,
  }) async {
    final effectiveClock = clock ?? () => nowUtc;
    final effectivePhotos = photoStore ?? photos;
    final container = ProviderContainer(
      overrides: [
        if (mealStore == null)
          ...foodOverrides(
            meals: meals,
            camera: FakeMealCamera(),
            clock: effectiveClock,
            photos: effectivePhotos,
            foodOn: foodOn,
          )
        else ...[
          moduleStoreProvider.overrideWithValue(
            InMemoryModuleStore({if (foodOn) ModuleId.food}),
          ),
          clockProvider.overrideWithValue(effectiveClock),
          mealStoreProvider.overrideWithValue(mealStore),
          photoStoreProvider.overrideWithValue(effectivePhotos),
          mealCameraProvider.overrideWithValue(FakeMealCamera()),
          mealPhotoSaverProvider.overrideWith(
            (ref) => MealPhotoSaver(
              ref.watch(mealStoreProvider),
              ref.watch(photoStoreProvider),
              now: effectiveClock,
              offsetAt: localOffset,
            ),
          ),
        ],
        mealGalleryProvider.overrideWithValue(gallery),
      ],
    );
    addTearDown(container.dispose);
    container.listen(galleryBackfillProvider, (_, _) {});
    await container.read(enabledModulesProvider.future);
    return container;
  }

  GalleryBackfill backfillOf(ProviderContainer container) =>
      container.read(galleryBackfillProvider.notifier);

  GalleryImportState stateOf(ProviderContainer container) =>
      container.read(galleryBackfillProvider);

  int revisionOf(ProviderContainer container) =>
      container.read(dataRevisionProvider);

  group('mealGalleryProvider and FakeMealGallery', () {
    test('unoverridden mealGalleryProvider throws UnimplementedError', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(mealGalleryProvider),
        throwsA(_unimplemented),
      );
    });

    test(
      'FakeMealGallery records calls and lastLimit, and throws error',
      () async {
        final fake = FakeMealGallery(photos: [returnedPhoto]);
        expect(await fake.pickPhotos(limit: 7), [returnedPhoto]);
        expect(fake.calls, 1);
        expect(fake.lastLimit, 7);

        final failing = FakeMealGallery(error: StateError('denied'));
        await expectLater(failing.pickPhotos(), throwsStateError);
        expect(failing.calls, 1);
        expect(failing.lastLimit, galleryPickLimit);
      },
    );
  });

  group('Food module gate', () {
    test(
      'Food off: pick() does not read mealGalleryProvider or mealStoreProvider',
      () async {
        final reads = StoreReads();
        var galleryRead = false;
        final container = ProviderContainer(
          overrides: [
            moduleStoreProvider.overrideWithValue(InMemoryModuleStore()),
            clockProvider.overrideWithValue(() => nowUtc),
            ...reads.overrides(),
            mealGalleryProvider.overrideWith((ref) {
              galleryRead = true;
              throw UnimplementedError('Override mealGalleryProvider.');
            }),
          ],
        );
        addTearDown(container.dispose);
        container.listen(galleryBackfillProvider, (_, _) {});
        await container.read(enabledModulesProvider.future);

        await backfillOf(container).pick();

        expect(galleryRead, isFalse);
        expect(reads.any, isFalse);
        expect(stateOf(container).phase, GalleryImportPhase.idle);
        expect(stateOf(container).items, isEmpty);
      },
    );

    test(
      'while modules are loading, pick() treats Food as off and reads nothing',
      () async {
        final reads = StoreReads();
        var galleryRead = false;
        final container = ProviderContainer(
          overrides: [
            moduleStoreProvider.overrideWithValue(
              InMemoryModuleStore(const {ModuleId.food}),
            ),
            clockProvider.overrideWithValue(() => nowUtc),
            ...reads.overrides(),
            mealGalleryProvider.overrideWith((ref) {
              galleryRead = true;
              throw UnimplementedError('Override mealGalleryProvider.');
            }),
          ],
        );
        addTearDown(container.dispose);
        container.listen(galleryBackfillProvider, (_, _) {});

        await backfillOf(container).pick();

        expect(galleryRead, isFalse);
        expect(reads.any, isFalse);
        expect(stateOf(container).phase, GalleryImportPhase.idle);
      },
    );
  });

  group('pick() lifecycle, failure, and empty pick', () {
    test('pick() failure leaves phase idle with pickFailed true', () async {
      final container = await containerWith(
        gallery: FakeMealGallery(error: StateError('picker error')),
      );

      await backfillOf(container).pick();

      final state = stateOf(container);
      expect(state.phase, GalleryImportPhase.idle);
      expect(state.pickFailed, isTrue);
      expect(state.items, isEmpty);
    });

    test('empty pick leaves phase idle with pickFailed false', () async {
      final gallery = FakeMealGallery();
      final container = await containerWith(gallery: gallery);

      await backfillOf(container).pick();

      final state = stateOf(container);
      expect(gallery.calls, 1);
      expect(gallery.lastLimit, galleryPickLimit);
      expect(state.phase, GalleryImportPhase.idle);
      expect(state.pickFailed, isFalse);
      expect(state.items, isEmpty);
    });

    test(
      'enters picking during pickPhotos and ignores re-entrant pick()',
      () async {
        final gallery = _GatedMealGallery();
        final container = await containerWith(gallery: gallery);

        final first = backfillOf(container).pick();
        expect(stateOf(container).phase, GalleryImportPhase.picking);
        final second = backfillOf(container).pick();

        gallery.complete([_jpegUtc(nowUtc.subtract(const Duration(hours: 1)))]);
        await Future.wait<void>([first, second]);

        expect(gallery.calls, 1);
        expect(stateOf(container).phase, GalleryImportPhase.review);
      },
    );
  });

  group('pick() EXIF stripping and item classification', () {
    test(
      'strips EXIF/GPS upfront and keeps EXIF timestamps older than 7 days',
      () async {
        final thirtyDaysAgo = nowUtc.subtract(const Duration(days: 30));
        final raw = _jpegUtc(thirtyDaysAgo, offset: '-03:00');
        final container = await containerWith(
          gallery: FakeMealGallery(photos: [raw]),
        );

        await backfillOf(container).pick();

        final item = stateOf(container).items.single;
        expect(item.index, 0);
        expect(item.status, GalleryItemStatus.ready);
        expect(item.timeFromPhoto, isTrue);
        expect(item.offsetMinutes, -180);
        expect(
          item.captureAt,
          DateTime.fromMillisecondsSinceEpoch(
            thirtyDaysAgo.millisecondsSinceEpoch +
                180 * Duration.millisecondsPerMinute,
            isUtc: true,
          ),
        );
        expect(exifCaptureTime(item.strippedBytes), isNull);
        expect(containsAscii(item.strippedBytes, gpsSecret), isFalse);
        expect(containsAscii(item.strippedBytes, 'XMPSECRET'), isFalse);
        expect(item.strippedBytes, stripExif(raw));
      },
    );

    test('missing EXIF, zero date, and EXIF > now + 2 min become needsTime; '
        'exact now + 2 min stays ready; non-JPEG becomes unreadable', () async {
      final exactAhead = _jpegUtc(nowUtc.add(const Duration(minutes: 2)));
      final tooFarAhead = _jpegUtc(
        nowUtc.add(const Duration(minutes: 2, seconds: 1)),
      );
      final zeroDate = photoJpeg(
        exif: exifApp1(
          dateTimeOriginal: '0000:00:00 00:00:00',
          offsetTimeOriginal: '+00:00',
        ),
      );
      final container = await containerWith(
        gallery: FakeMealGallery(
          photos: [
            returnedPhoto,
            zeroDate,
            tooFarAhead,
            exactAhead,
            Uint8List.fromList(pngBytes),
          ],
        ),
      );

      await backfillOf(container).pick();

      final items = stateOf(container).items;
      expect(items, hasLength(5));
      expect(items[0].status, GalleryItemStatus.needsTime);
      expect(items[0].captureAt, isNull);
      expect(items[0].timeFromPhoto, isFalse);
      expect(items[1].status, GalleryItemStatus.needsTime);
      expect(items[2].status, GalleryItemStatus.needsTime);
      expect(items[3].status, GalleryItemStatus.ready);
      expect(items[3].timeFromPhoto, isTrue);
      expect(items[4].status, GalleryItemStatus.unreadable);
      expect(stateOf(container).readyCount, 1);
      expect(stateOf(container).openCount, 3);
    });

    test('flags <= 2 min abs diff against saved DB meals ([day-1, day+1]) and '
        'earlier ready batch items as nearDuplicate', () async {
      final dbMealAt = nowUtc.subtract(const Duration(hours: 4));
      await meals.add(MealDraft(at: dbMealAt, offsetMinutes: 0), now: nowUtc);
      final batchBase = nowUtc.subtract(const Duration(hours: 1));
      final container = await containerWith(
        gallery: FakeMealGallery(
          photos: [
            _jpegUtc(dbMealAt.add(const Duration(minutes: 2))),
            _jpegUtc(dbMealAt.subtract(const Duration(minutes: 2))),
            _jpegUtc(dbMealAt.add(const Duration(minutes: 2, seconds: 1))),
            _jpegUtc(batchBase),
            _jpegUtc(batchBase.add(const Duration(seconds: 90))),
            _jpegUtc(batchBase.add(const Duration(minutes: 2, seconds: 30))),
          ],
        ),
      );

      await backfillOf(container).pick();

      final items = stateOf(container).items;
      expect(items[0].status, GalleryItemStatus.nearDuplicate);
      expect(items[0].duplicateOfAt, dbMealAt);
      expect(items[0].duplicateOfOffsetMinutes, 0);
      expect(items[1].status, GalleryItemStatus.nearDuplicate);
      expect(items[2].status, GalleryItemStatus.ready);
      expect(items[3].status, GalleryItemStatus.ready);
      expect(items[4].status, GalleryItemStatus.nearDuplicate);
      expect(items[4].duplicateOfAt, batchBase);
      expect(items[4].duplicateOfOffsetMinutes, 0);
      // Item 4 is nearDuplicate (not ready), so item 5 is > 2 min from item 3.
      expect(items[5].status, GalleryItemStatus.ready);
    });

    test('adjacent foodDay boundary ([day-1, day+1]) catches DB meal 2 min earlier '
        'across the 05:00 foodDay turn', () async {
      final beforeFive = DateTime(2026, 11, 17, 4, 59);
      final afterFive = DateTime(2026, 11, 17, 5, 1);
      meals.seed(beforeFive);
      final photo = photoJpeg(
        exif: exifApp1(
          dateTimeOriginal: exifDate(afterFive),
          offsetTimeOriginal: null,
        ),
      );
      final container = await containerWith(
        gallery: FakeMealGallery(photos: [photo]),
        clock: () => nowLocal,
      );

      await backfillOf(container).pick();

      final item = stateOf(container).items.single;
      expect(item.status, GalleryItemStatus.nearDuplicate);
      expect(item.duplicateOfAt, beforeFive.toUtc());
    });

    test('boundary: exactly 365 days is ready; > 365 days is tooOld', () async {
      final exact365 = _jpegUtc(nowUtc.subtract(const Duration(days: 365)));
      final over365 = _jpegUtc(
        nowUtc.subtract(const Duration(days: 365, seconds: 1)),
      );
      final gallery = FakeMealGallery(photos: [exact365]);
      final container = await containerWith(gallery: gallery);

      await backfillOf(container).pick();
      expect(stateOf(container).items.single.status, GalleryItemStatus.ready);

      backfillOf(container).reset();
      gallery.photos = [over365];
      await backfillOf(container).pick();
      expect(stateOf(container).items.single.status, GalleryItemStatus.tooOld);
    });
  });

  group('confirmAnotherMeal and confirmOld', () {
    test(
      'item both > 365 days old and near a DB meal requires both confirmations '
      'before becoming ready (both orders)',
      () async {
        final ancientAt = nowUtc.subtract(const Duration(days: 400));
        await meals.add(
          MealDraft(at: ancientAt, offsetMinutes: 0),
          now: nowUtc,
        );
        final raw = _jpegUtc(ancientAt.add(const Duration(minutes: 1)));

        // Order A: confirmAnotherMeal first, then confirmOld.
        final c1 = await containerWith(
          gallery: FakeMealGallery(photos: [raw, raw]),
        );
        await backfillOf(c1).pick();
        expect(stateOf(c1).items[0].status, GalleryItemStatus.nearDuplicate);

        backfillOf(c1).confirmAnotherMeal(0);
        var item = stateOf(c1).items[0];
        expect(item.duplicateConfirmed, isTrue);
        expect(item.oldConfirmed, isFalse);
        expect(item.status, GalleryItemStatus.tooOld);

        backfillOf(c1).confirmOld(0);
        item = stateOf(c1).items[0];
        expect(item.duplicateConfirmed, isTrue);
        expect(item.oldConfirmed, isTrue);
        expect(item.status, GalleryItemStatus.ready);

        // Order B: confirmOld first, then confirmAnotherMeal (using item 1).
        backfillOf(c1).confirmOld(1);
        item = stateOf(c1).items[1];
        expect(item.oldConfirmed, isTrue);
        expect(item.duplicateConfirmed, isFalse);
        expect(item.status, GalleryItemStatus.nearDuplicate);

        backfillOf(c1).confirmAnotherMeal(1);
        item = stateOf(c1).items[1];
        expect(item.oldConfirmed, isTrue);
        expect(item.duplicateConfirmed, isTrue);
        expect(item.status, GalleryItemStatus.ready);
      },
    );
  });

  group('setManualTime', () {
    test('refuses future DateTime and leaves item unchanged', () async {
      final container = await containerWith(
        gallery: FakeMealGallery(photos: [returnedPhoto]),
        clock: () => nowLocal,
      );
      await backfillOf(container).pick();

      final ok = await backfillOf(container)
          .setManualTime(0, nowLocal.add(const Duration(seconds: 1)));

      expect(ok, isFalse);
      final item = stateOf(container).items.single;
      expect(item.status, GalleryItemStatus.needsTime);
      expect(item.captureAt, isNull);
    });

    test('valid past/present time queries [day-1, day+1] for new day, flags '
        'nearDuplicate against previously unloaded DB meal, and resets flags', () async {
      final otherDayLocal = DateTime(2025, 6, 10, 13);
      meals.seed(otherDayLocal);
      final spy = _SpyMealStore(meals);
      final ancientAt = nowUtc.subtract(const Duration(days: 400));
      await meals.add(MealDraft(at: ancientAt, offsetMinutes: 0), now: nowUtc);

      final container = await containerWith(
        gallery: FakeMealGallery(
          photos: [
            returnedPhoto,
            _jpegUtc(ancientAt.add(const Duration(seconds: 30))),
          ],
        ),
        mealStore: spy,
        clock: () => nowLocal,
      );
      await backfillOf(container).pick();
      spy.betweenCalls.clear();

      // Item 0: set manual time near previously unloaded DB meal on 2025-06-10.
      final ok0 = await backfillOf(container)
          .setManualTime(0, otherDayLocal.add(const Duration(minutes: 1)));
      expect(ok0, isTrue);
      final expectedDay = foodDay(otherDayLocal);
      expect(
        spy.betweenCalls,
        contains((expectedDay.addDays(-1), expectedDay.addDays(1))),
      );
      final item0 = stateOf(container).items[0];
      expect(item0.status, GalleryItemStatus.nearDuplicate);
      expect(item0.timeFromPhoto, isFalse);
      expect(item0.duplicateOfAt, otherDayLocal.toUtc());

      // Item 1: confirm both flags, then change manual time to another >365d time.
      backfillOf(container).confirmAnotherMeal(1);
      backfillOf(container).confirmOld(1);
      expect(stateOf(container).items[1].status, GalleryItemStatus.ready);

      final oldManual = nowLocal.subtract(const Duration(days: 450));
      final ok1 = await backfillOf(container).setManualTime(1, oldManual);
      expect(ok1, isTrue);
      final item1 = stateOf(container).items[1];
      expect(item1.duplicateConfirmed, isFalse);
      expect(item1.oldConfirmed, isFalse);
      expect(item1.status, GalleryItemStatus.tooOld);

      // Exact now boundary succeeds as ready.
      final okNow = await backfillOf(container).setManualTime(0, nowLocal);
      expect(okNow, isTrue);
      expect(stateOf(container).items[0].status, GalleryItemStatus.ready);
      expect(stateOf(container).items[0].captureAt, nowLocal.toUtc());
    });

    test('setManualTime re-evaluates downstream batch duplicates', () async {
      final lunchLocal = DateTime(2026, 11, 19, 12, 30);
      final container = await containerWith(
        gallery: FakeMealGallery(
          photos: [returnedPhoto, photoTakenAt(lunchLocal)],
        ),
        clock: () => nowLocal,
      );
      await backfillOf(container).pick();
      expect(stateOf(container).items[0].status, GalleryItemStatus.needsTime);
      expect(stateOf(container).items[1].status, GalleryItemStatus.ready);

      final ok = await backfillOf(container).setManualTime(0, lunchLocal);

      expect(ok, isTrue);
      expect(stateOf(container).items[0].status, GalleryItemStatus.ready);
      expect(
        stateOf(container).items[1].status,
        GalleryItemStatus.nearDuplicate,
      );
      expect(stateOf(container).items[1].duplicateOfAt, lunchLocal.toUtc());
    });
  });

  group('skip()', () {
    test(
      'sets skipped status, updates counts, and re-evaluates downstream batch '
      'duplicates',
      () async {
        final t0 = nowUtc.subtract(const Duration(hours: 3));
        final container = await containerWith(
          gallery: FakeMealGallery(
            photos: [
              _jpegUtc(t0),
              _jpegUtc(t0.add(const Duration(minutes: 1))),
              _jpegUtc(t0.add(const Duration(minutes: 2, seconds: 30))),
              returnedPhoto,
            ],
          ),
        );
        await backfillOf(container).pick();
        expect(stateOf(container).readyCount, 2);
        expect(stateOf(container).openCount, 2);

        backfillOf(container).skip(0);

        final state = stateOf(container);
        expect(state.items[0].skipped, isTrue);
        expect(state.items[0].status, GalleryItemStatus.skipped);
        expect(state.items[1].status, GalleryItemStatus.ready);
        expect(state.items[2].status, GalleryItemStatus.nearDuplicate);
        expect(
          state.items[2].duplicateOfAt,
          t0.add(const Duration(minutes: 1)),
        );
        expect(state.readyCount, 1);
        expect(state.openCount, 2);
      },
    );
  });

  group('saveReady()', () {
    test('saves only ready items, preserves exact captureAt, sets done, and '
        'bumps dataRevisionProvider once when savedCount > 0', () async {
      final old30d = nowUtc.subtract(const Duration(days: 30));
      final old400d = nowUtc.subtract(const Duration(days: 400));
      final duplicateT = nowUtc.subtract(const Duration(hours: 2));
      await meals.add(MealDraft(at: duplicateT, offsetMinutes: 0), now: nowUtc);
      final rawOld30d = _jpegUtc(old30d, offset: '-03:00');
      final rawOld400d = _jpegUtc(old400d);
      final container = await containerWith(
        gallery: FakeMealGallery(
          photos: [
            rawOld30d,
            rawOld400d,
            _jpegUtc(duplicateT.add(const Duration(minutes: 1))),
            returnedPhoto,
            Uint8List.fromList(pngBytes),
            _jpegUtc(nowUtc.subtract(const Duration(hours: 5))),
          ],
        ),
      );
      await backfillOf(container).pick();
      backfillOf(container).confirmOld(1);
      backfillOf(container).skip(5);

      await backfillOf(container).saveReady();

      final state = stateOf(container);
      expect(state.phase, GalleryImportPhase.done);
      expect(state.savedCount, 2);
      expect(state.noSpace, isFalse);
      expect(state.saveFailed, isFalse);
      expect(revisionOf(container), 1);
      expect(meals.rows, hasLength(3));
      expect(meals.rows[1].at, state.items[0].captureAt);
      expect(meals.rows[1].offsetMinutes, -180);
      expect(await photos.read(meals.rows[1].photo!), stripExif(rawOld30d));
      expect(meals.rows[2].at, old400d);
      expect(await photos.read(meals.rows[2].photo!), stripExif(rawOld400d));
    });

    test(
      '0 ready items saves nothing and does not bump dataRevisionProvider',
      () async {
        final container = await containerWith(
          gallery: FakeMealGallery(
            photos: [returnedPhoto, Uint8List.fromList(pngBytes)],
          ),
        );
        await backfillOf(container).pick();

        await backfillOf(container).saveReady();

        final state = stateOf(container);
        expect(state.phase, GalleryImportPhase.done);
        expect(state.savedCount, 0);
        expect(revisionOf(container), 0);
        expect(meals.rows, isEmpty);
      },
    );

    test('error path: non-ENOSPC save failure sets saveFailed true', () async {
      final container = await containerWith(
        gallery: FakeMealGallery(
          photos: [_jpegUtc(nowUtc.subtract(const Duration(hours: 1)))],
        ),
        photoStore: _BrokenPhotoStore(),
      );
      await backfillOf(container).pick();

      await backfillOf(container).saveReady();

      final state = stateOf(container);
      expect(state.phase, GalleryImportPhase.done);
      expect(state.savedCount, 0);
      expect(state.saveFailed, isTrue);
      expect(state.noSpace, isFalse);
      expect(meals.rows, isEmpty);
    });

    test(
      'noSpace on photo 2 of 3 keeps photo 1, deletes photo 2 row/file, '
      'skips photo 3, sets noSpace true and savedCount 1, and bumps once',
      () async {
        final countingStore = _CountingNoSpacePhotoStore(failOnCall: 2);
        final raw1 = _jpegUtc(nowUtc.subtract(const Duration(hours: 6)));
        final raw2 = _jpegUtc(nowUtc.subtract(const Duration(hours: 4)));
        final raw3 = _jpegUtc(nowUtc.subtract(const Duration(hours: 2)));
        final container = await containerWith(
          gallery: FakeMealGallery(photos: [raw1, raw2, raw3]),
          photoStore: countingStore,
        );
        await backfillOf(container).pick();

        await backfillOf(container).saveReady();

        final state = stateOf(container);
        expect(state.phase, GalleryImportPhase.done);
        expect(state.noSpace, isTrue);
        expect(state.savedCount, 1);
        expect(countingStore.saves, 2);
        expect(meals.rows, hasLength(1));
        expect(meals.rows.single.photo, isNotNull);
        expect(await countingStore.inner.totalBytes(), stripExif(raw1).length);
        expect(revisionOf(container), 1);
      },
    );
  });

  group('reset(), dispose(), and Food disabled mid-operation', () {
    test('reset() in review clears state back to idle', () async {
      final container = await containerWith(
        gallery: FakeMealGallery(
          photos: [_jpegUtc(nowUtc.subtract(const Duration(hours: 1)))],
        ),
      );
      await backfillOf(container).pick();
      expect(stateOf(container).phase, GalleryImportPhase.review);

      backfillOf(container).reset();

      final state = stateOf(container);
      expect(state.phase, GalleryImportPhase.idle);
      expect(state.items, isEmpty);
      expect(state.savedCount, 0);
      expect(state.noSpace, isFalse);
      expect(state.pickFailed, isFalse);
      expect(state.saveFailed, isFalse);
    });

    test('reset() mid-pick() ignores late picker result', () async {
      final gallery = _GatedMealGallery();
      final container = await containerWith(gallery: gallery);

      final pending = backfillOf(container).pick();
      backfillOf(container).reset();
      gallery.complete([_jpegUtc(nowUtc.subtract(const Duration(hours: 1)))]);
      await pending;

      expect(stateOf(container).phase, GalleryImportPhase.idle);
      expect(stateOf(container).items, isEmpty);
    });

    test(
      'ProviderContainer.dispose() mid-pick() completes without error',
      () async {
        final gallery = _GatedMealGallery();
        final container = await containerWith(gallery: gallery);

        final pending = backfillOf(container).pick();
        container.dispose();
        gallery.complete([_jpegUtc(nowUtc.subtract(const Duration(hours: 1)))]);

        await expectLater(pending, completes);
      },
    );

    test(
      'Food disabled mid-pick() stops cleanly with idle empty state',
      () async {
        final gallery = _GatedMealGallery();
        final container = await containerWith(gallery: gallery);

        final pending = backfillOf(container).pick();
        await container
            .read(enabledModulesProvider.notifier)
            .disable(ModuleId.food);
        gallery.complete([_jpegUtc(nowUtc.subtract(const Duration(hours: 1)))]);
        await pending;

        expect(stateOf(container).phase, GalleryImportPhase.idle);
        expect(stateOf(container).items, isEmpty);
      },
    );

    test(
      'reset() mid-saveReady() stops remaining saves and stays idle',
      () async {
        final gatedStore = _GatedPhotoStore();
        final container = await containerWith(
          gallery: FakeMealGallery(
            photos: [
              _jpegUtc(nowUtc.subtract(const Duration(hours: 4))),
              _jpegUtc(nowUtc.subtract(const Duration(hours: 2))),
            ],
          ),
          photoStore: gatedStore,
        );
        await backfillOf(container).pick();

        final saving = backfillOf(container).saveReady();
        await pumpEventQueue();
        expect(gatedStore.saves, 1);

        backfillOf(container).reset();
        gatedStore.release();
        await saving;

        expect(gatedStore.saves, 1);
        expect(meals.rows, hasLength(1));
        expect(revisionOf(container), 1);
        expect(stateOf(container).phase, GalleryImportPhase.idle);
        expect(stateOf(container).items, isEmpty);
      },
    );

    test(
      'ProviderContainer.dispose() mid-saveReady() stops cleanly without error',
      () async {
        final gatedStore = _GatedPhotoStore();
        final container = await containerWith(
          gallery: FakeMealGallery(
            photos: [
              _jpegUtc(nowUtc.subtract(const Duration(hours: 4))),
              _jpegUtc(nowUtc.subtract(const Duration(hours: 2))),
            ],
          ),
          photoStore: gatedStore,
        );
        await backfillOf(container).pick();

        final saving = backfillOf(container).saveReady();
        await pumpEventQueue();
        expect(gatedStore.saves, 1);

        container.dispose();
        gatedStore.release();

        await expectLater(saving, completes);
        expect(gatedStore.saves, 1);
      },
    );

    test(
      'Food disabled mid-saveReady() stops remaining saves without overwriting '
      'state to done',
      () async {
        final gatedStore = _GatedPhotoStore();
        final container = await containerWith(
          gallery: FakeMealGallery(
            photos: [
              _jpegUtc(nowUtc.subtract(const Duration(hours: 4))),
              _jpegUtc(nowUtc.subtract(const Duration(hours: 2))),
            ],
          ),
          photoStore: gatedStore,
        );
        await backfillOf(container).pick();

        final saving = backfillOf(container).saveReady();
        await pumpEventQueue();
        expect(gatedStore.saves, 1);

        await container
            .read(enabledModulesProvider.notifier)
            .disable(ModuleId.food);
        gatedStore.release();
        await saving;

        expect(gatedStore.saves, 1);
        expect(meals.rows, hasLength(1));
        expect(revisionOf(container), 1);
        expect(stateOf(container).phase, isNot(GalleryImportPhase.done));
      },
    );
  });
}
