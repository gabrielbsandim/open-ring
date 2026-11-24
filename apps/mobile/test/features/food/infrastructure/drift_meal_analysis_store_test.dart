import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/database/app_database_provider.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/meal_photo_result.dart';
import 'package:open_ring/features/food/application/food_data.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/infrastructure/drift_meal_analysis_store.dart';
import 'package:open_ring/features/food/infrastructure/drift_meal_store.dart';
import 'package:open_ring/features/settings/infrastructure/device_local_data_eraser.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/database.dart';

final _now = DateTime.utc(2026, 11, 24, 12);

const MealAnalysisTarget _target = (
  providerHost: 'api.example.com',
  model: 'vision-1',
  promptVersion: 1,
  outputSchema: 1,
);

const MealAnalysisTarget _otherModel = (
  providerHost: 'api.example.com',
  model: 'vision-2',
  promptVersion: 1,
  outputSchema: 1,
);

const MealAnalysisTarget _withItems = (
  providerHost: 'api.example.com',
  model: 'vision-1',
  promptVersion: 1,
  outputSchema: 2,
);

const MealSentPhoto _sent = (
  sha256: 'abc123',
  width: 768,
  height: 576,
  bytes: 41000,
);

const _rice = MealPhotoItem(
  name: 'rice',
  measure: MealPhotoMeasure.servingSpoon,
  countX2: 4,
  grams: 180,
);

const _suggestion = MealPhotoSuggestion(
  isFood: MealPhotoFlag.yes,
  kind: MealPhotoKind.main,
  protein: MealPhotoFlag.yes,
  caffeine: MealPhotoFlag.no,
  fried: MealPhotoFlag.no,
  sugaryDrink: MealPhotoFlag.no,
  veg: MealPhotoVeg.some,
  alcohol: MealPhotoAlcohol.none,
  processed: MealPhotoProcessed.notMostly,
  items: [_rice],
);

MealAnalysisAnswer _done({
  MealPhotoSuggestion suggestion = _suggestion,
  String raw = '{"is_food":"yes"}',
}) => (
  status: MealAnalysisStatus.done,
  sent: _sent,
  suggestion: suggestion,
  confidence: MealPhotoConfidence.medium,
  rawText: raw,
  usage: const AiTokenUsage(promptTokens: 900, completionTokens: 60),
  cost: (cost: 0.002, currency: 'credits', source: AiCostSource.provider),
  errorKind: null,
);

Future<int> _meal(AppDatabase db, {String photo = 'meal_1.jpg'}) async {
  final meal = await DriftMealStore(db).add(
    MealDraft(at: _now, offsetMinutes: -180),
    now: _now,
    photo: photo,
  );
  return meal.id;
}

Future<void> _userItem(AppDatabase db, int analysisId, String name) => db
    .into(db.mealItems)
    .insert(
      MealItemsCompanion.insert(
        analysisId: analysisId,
        position: 9,
        name: name,
        measure: 'cup',
        countX2: 2,
        grams: 200,
        origin: 'user',
      ),
    );

Future<int> _analysisAt(
  DriftMealAnalysisStore store,
  int mealId,
  MealAnalysisTarget target,
  DateTime at,
) async => (await store.enqueue(mealId, 'meal_1.jpg', target, now: at)).id;

Future<int> _doneRow(DriftMealAnalysisStore store, int mealId) async {
  final id = await _analysisAt(store, mealId, _target, _now);
  await store.markSending(id, now: _now);
  await store.complete(id, _done(), now: _now);
  return id;
}

void main() {
  late AppDatabase db;
  late DriftMealAnalysisStore store;
  late int mealId;

  setUp(() async {
    db = memoryDatabase();
    store = DriftMealAnalysisStore(db);
    mealId = await _meal(db);
  });

  group('enqueue', () {
    test('the same meal, host, model and prompt twice gives one row', () async {
      final first = await store.enqueue(
        mealId,
        'meal_1.jpg',
        _target,
        now: _now,
      );
      final second = await store.enqueue(
        mealId,
        'meal_1.jpg',
        _target,
        now: _now.add(const Duration(minutes: 1)),
      );

      expect(second.id, first.id);
      expect(second.status, MealAnalysisStatus.queued);
      expect(second.queuedAt, _now);
      expect(await rowCount(db, 'meal_analyses'), 1);
    });

    test('a done row comes back cached with its items', () async {
      final id = await _doneRow(store, mealId);

      final cached = await store.enqueue(
        mealId,
        'meal_1.jpg',
        _target,
        now: _now.add(const Duration(hours: 1)),
      );

      expect(cached.id, id);
      expect(cached.status, MealAnalysisStatus.done);
      expect(cached.attempts, 1);
      expect(cached.items.single.name, 'rice');
    });

    test('a not_food row comes back cached without a new queue', () async {
      final id = await _analysisAt(store, mealId, _target, _now);
      await store.markSending(id, now: _now);
      await store.complete(id, (
        status: MealAnalysisStatus.notFood,
        sent: _sent,
        suggestion: null,
        confidence: null,
        rawText: '{"is_food":"no"}',
        usage: null,
        cost: null,
        errorKind: null,
      ), now: _now);

      final cached = await store.enqueue(
        mealId,
        'meal_1.jpg',
        _target,
        now: _now.add(const Duration(hours: 1)),
      );

      expect(cached.id, id);
      expect(cached.status, MealAnalysisStatus.notFood);
      expect(cached.queuedAt, _now);
      expect(await store.next(), isNull);
    });

    test('a different photo name resets a done row to queued', () async {
      final id = await _doneRow(store, mealId);
      final later = _now.add(const Duration(hours: 1));

      final reset = await store.enqueue(
        mealId,
        'meal_9.jpg',
        _target,
        now: later,
      );

      expect(reset.id, id);
      expect(reset.status, MealAnalysisStatus.queued);
      expect(reset.photoName, 'meal_9.jpg');
      expect(reset.queuedAt, later);
      expect(reset.items, isEmpty);
    });

    for (final (label, target, again) in [
      ('a different output schema', _withItems, false),
      ('again', _target, true),
    ]) {
      test('$label resets a done row to queued, keeping user items and hidden '
          'chips', () async {
        final id = await _doneRow(store, mealId);
        await _userItem(db, id, 'juice');
        await (db.update(db.mealAnalyses)..where((r) => r.id.equals(id))).write(
          const MealAnalysesCompanion(hiddenOil: Value(true)),
        );
        final later = _now.add(const Duration(hours: 2));

        final reset = await store.enqueue(
          mealId,
          'meal_1.jpg',
          target,
          now: later,
          again: again,
        );

        expect(reset.id, id);
        expect(reset.status, MealAnalysisStatus.queued);
        expect(reset.target.outputSchema, target.outputSchema);
        expect(reset.queuedAt, later);
        expect(reset.attempts, 0);
        expect(reset.sent, isNull);
        expect(reset.resultJson, isNull);
        expect(reset.rawText, isNull);
        expect(reset.hiddenOil, isTrue);
        expect(reset.items.map((i) => (i.name, i.origin)), [
          ('juice', MealItemOrigin.user),
        ]);
        expect(await rowCount(db, 'meal_analyses'), 1);
      });
    }
  });

  group('send cycle', () {
    test(
      'next is the oldest queued row and markSending counts the attempt',
      () async {
        final second = await _meal(db, photo: 'meal_2.jpg');
        final later = await _analysisAt(
          store,
          mealId,
          _target,
          _now.add(const Duration(minutes: 5)),
        );
        final early = await _analysisAt(store, second, _target, _now);

        expect((await store.next())!.id, early);
        expect(await store.markSending(early, now: _now), isTrue);
        expect(await store.markSending(early, now: _now), isFalse);
        expect((await store.next())!.id, later);
        expect((await store.byMeal(second)).single.attempts, 1);
      },
    );

    test(
      'requeue moves only a sending row back and undoes its attempt',
      () async {
        final id = await _analysisAt(store, mealId, _target, _now);
        await store.markSending(id, now: _now);

        expect(await store.requeue(id, now: _now), isTrue);
        expect(await store.requeue(id, now: _now), isFalse);

        final row = (await store.byMeal(mealId)).single;
        expect((row.status, row.attempts), (MealAnalysisStatus.queued, 0));
        expect((await store.next())!.id, id);
      },
    );

    test('complete stores the answer and replaces only model items', () async {
      final id = await _doneRow(store, mealId);
      await _userItem(db, id, 'juice');
      await store.enqueue(
        mealId,
        'meal_1.jpg',
        _target,
        now: _now,
        again: true,
      );
      await store.markSending(id, now: _now);
      const bread = MealPhotoItem(
        name: 'bread',
        measure: MealPhotoMeasure.slice,
        countX2: 2,
        grams: 50,
      );

      final written = await store.complete(
        id,
        _done(suggestion: _suggestion.withItems([bread])),
        now: _now,
      );

      final row = (await store.byMeal(mealId)).single;
      expect(written, isTrue);
      expect(row.status, MealAnalysisStatus.done);
      expect(row.sent, _sent);
      expect(row.confidence, MealPhotoConfidence.medium);
      final stored = await db.select(db.mealAnalyses).getSingle();
      expect(
        (stored.promptTokens, stored.cost, stored.costSource),
        (900, 0.002, 'provider'),
      );
      expect(row.suggestion?.kind, MealPhotoKind.main);
      expect(row.items.map((i) => i.name), ['bread', 'juice']);
      expect(await rowCount(db, 'meal_items'), 2);
    });

    test('complete refuses a row that is not sending', () async {
      final id = await _analysisAt(store, mealId, _target, _now);

      expect(await store.complete(id, _done(), now: _now), isFalse);
      expect(await rowCount(db, 'meal_items'), 0);
    });

    test('fail and skip write the status and reason', () async {
      final second = await _meal(db, photo: 'meal_2.jpg');
      final failed = await _analysisAt(store, mealId, _target, _now);
      final skipped = await _analysisAt(store, second, _target, _now);
      await store.markSending(failed, now: _now);

      expect(await store.fail(failed, 'timeout', now: _now), isTrue);
      expect(await store.skip(skipped, 'cancelled', now: _now), isTrue);
      expect(await store.skip(failed, 'cancelled', now: _now), isFalse);

      final a = (await store.byMeal(mealId)).single;
      final b = (await store.byMeal(second)).single;
      expect((a.status, a.errorKind), (MealAnalysisStatus.failed, 'timeout'));
      expect(
        (b.status, b.errorKind),
        (MealAnalysisStatus.skipped, 'cancelled'),
      );
    });
  });

  group('resend and retry', () {
    test('countResend adds an attempt to a sending row only', () async {
      final id = await _analysisAt(store, mealId, _target, _now);
      expect(await store.countResend(id, now: _now), isFalse);
      await store.markSending(id, now: _now);

      expect(await store.countResend(id, now: _now), isTrue);
      expect((await store.byId(id))!.attempts, 2);
    });

    test('retry moves failed or rejected to queued, keeping attempts and '
        'queued_at', () async {
      final id = await _analysisAt(store, mealId, _target, _now);
      await store.markSending(id, now: _now);
      await store.fail(id, 'serverError', now: _now);
      final later = _now.add(const Duration(hours: 2));

      expect(await store.retry(id, now: later), isTrue);
      final row = (await store.byId(id))!;
      expect(
        (row.status, row.errorKind, row.attempts),
        (MealAnalysisStatus.queued, null, 1),
      );
      expect(row.queuedAt, _now);
      expect(await store.retry(id, now: later), isFalse);
    });

    test('retry refuses a done row', () async {
      final id = await _doneRow(store, mealId);

      expect(await store.retry(id, now: _now), isFalse);
    });
  });

  group('maintenance', () {
    test('purgeRawBefore nulls raw_text only', () async {
      await _doneRow(store, mealId);

      final purged = await store.purgeRawBefore(
        _now.add(const Duration(days: 30)),
      );

      final row = (await store.byMeal(mealId)).single;
      expect(purged, 1);
      expect(row.rawText, isNull);
      expect(row.resultJson, isNotNull);
      expect(row.status, MealAnalysisStatus.done);
      expect(row.items, hasLength(1));
      expect(await store.purgeRawBefore(_now), 0);
    });

    test('expireBefore skips only queued rows older than the cutoff', () async {
      final second = await _meal(db, photo: 'meal_2.jpg');
      final third = await _meal(db, photo: 'meal_3.jpg');
      final old = await _analysisAt(store, mealId, _target, _now);
      await _analysisAt(
        store,
        second,
        _target,
        _now.add(const Duration(days: 2)),
      );
      final sending = await _analysisAt(store, third, _target, _now);
      await store.markSending(sending, now: _now);
      final now = _now.add(const Duration(days: 7, minutes: 1));

      final expired = await store.expireBefore(
        now.subtract(const Duration(days: 7)),
        now: now,
      );

      final row = (await store.byMeal(mealId)).single;
      expect(expired, 1);
      expect(row.id, old);
      expect(
        (row.status, row.errorKind),
        (MealAnalysisStatus.skipped, 'expired'),
      );
      expect(
        (await store.byMeal(second)).single.status,
        MealAnalysisStatus.queued,
      );
      expect(
        (await store.byMeal(third)).single.status,
        MealAnalysisStatus.sending,
      );
    });

    test('skipOffTarget skips only queued rows of another target', () async {
      final second = await _meal(db, photo: 'meal_2.jpg');
      final third = await _meal(db, photo: 'meal_3.jpg');
      await _analysisAt(store, mealId, _target, _now);
      await _analysisAt(store, second, _otherModel, _now);
      final sending = await _analysisAt(store, third, _otherModel, _now);
      await store.markSending(sending, now: _now);

      final skipped = await store.skipOffTarget(
        'api.example.com',
        'vision-1',
        now: _now,
      );

      final off = (await store.byMeal(second)).single;
      expect(skipped, 1);
      expect(
        (await store.byMeal(mealId)).single.status,
        MealAnalysisStatus.queued,
      );
      expect(
        (off.status, off.errorKind),
        (MealAnalysisStatus.skipped, 'target_changed'),
      );
      expect(
        (await store.byMeal(third)).single.status,
        MealAnalysisStatus.sending,
      );
    });

    test('skipOffTarget skips a queued row of another host with the same '
        'model', () async {
      const otherHost = (
        providerHost: 'other.example.com',
        model: 'vision-1',
        promptVersion: 1,
        outputSchema: 1,
      );
      final id = await _analysisAt(store, mealId, otherHost, _now);

      final skipped = await store.skipOffTarget(
        'api.example.com',
        'vision-1',
        now: _now,
      );

      final row = (await store.byMeal(mealId)).single;
      expect(skipped, 1);
      expect(row.id, id);
      expect(
        (row.status, row.errorKind),
        (MealAnalysisStatus.skipped, 'target_changed'),
      );
    });

    test('recoverInterrupted fails sending rows as interrupted', () async {
      final second = await _meal(db, photo: 'meal_2.jpg');
      final sending = await _analysisAt(store, mealId, _target, _now);
      await _analysisAt(store, second, _target, _now);
      await store.markSending(sending, now: _now);

      expect(await store.recoverInterrupted(now: _now), 1);

      final row = (await store.byMeal(mealId)).single;
      expect(
        (row.status, row.errorKind),
        (MealAnalysisStatus.failed, 'interrupted'),
      );
      expect(
        (await store.byMeal(second)).single.status,
        MealAnalysisStatus.queued,
      );
    });

    test('countQueuedSince counts every status but skipped', () async {
      final second = await _meal(db, photo: 'meal_2.jpg');
      final third = await _meal(db, photo: 'meal_3.jpg');
      final midnight = DateTime.utc(2026, 11, 24);
      await _analysisAt(
        store,
        mealId,
        _target,
        midnight.subtract(const Duration(minutes: 1)),
      );
      final skipped = await _analysisAt(store, second, _target, _now);
      await _analysisAt(store, third, _target, _now);
      await store.skip(skipped, 'cancelled', now: _now);

      expect(await store.countQueuedSince(midnight), 1);
    });
  });

  group('keep on phone', () {
    test('reads false by default and survives deleteAll', () async {
      await _doneRow(store, mealId);
      expect(await store.keepOnPhone(mealId), isFalse);

      expect(await store.setKeepOnPhone(mealId, keep: true), isTrue);
      await store.deleteAll();

      expect(await store.keepOnPhone(mealId), isTrue);
      expect(await rowCount(db, 'meal_analyses'), 0);
      expect(await rowCount(db, 'meal_items'), 0);
      expect(await store.setKeepOnPhone(999, keep: true), isFalse);
    });
  });

  group('deletion', () {
    test('deleting a meal deletes its analyses and items', () async {
      final second = await _meal(db, photo: 'meal_2.jpg');
      await _doneRow(store, mealId);
      await _analysisAt(store, second, _target, _now);

      await DriftMealStore(db).delete(mealId);

      expect(await store.byMeal(mealId), isEmpty);
      expect(await rowCount(db, 'meal_analyses'), 1);
      expect(await rowCount(db, 'meal_items'), 0);
    });

    test('FoodDataEraser.clear leaves both tables empty', () async {
      await _doneRow(store, mealId);
      final container = ProviderContainer(
        overrides: [
          mealStoreProvider.overrideWithValue(DriftMealStore(db)),
          photoStoreProvider.overrideWithValue(InMemoryPhotoStore()),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(foodDataEraserProvider).clear(), isTrue);

      expect(await rowCount(db, 'meal_analyses'), 0);
      expect(await rowCount(db, 'meal_items'), 0);
    });

    test('DeviceLocalDataEraser.eraseAll leaves both tables empty', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      await _doneRow(store, mealId);

      await DeviceLocalDataEraser(
        db,
        InMemoryPhotoStore(),
        secrets: InMemorySecretStore(),
      ).eraseAll();

      expect(await rowCount(db, 'meal_analyses'), 0);
      expect(await rowCount(db, 'meal_items'), 0);
    });
  });

  test('the production wiring bumps the analysis revision on each write, '
      'never dataRevision', () async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        driftMealAnalysisStoreOverride,
      ],
    );
    addTearDown(container.dispose);
    final analyses = container.read(mealAnalysisStoreProvider);

    final id = (await analyses.enqueue(
      mealId,
      'meal_1.jpg',
      _target,
      now: _now,
    )).id;
    await analyses.markSending(id, now: _now);
    await analyses.complete(id, _done(), now: _now);
    await analyses.setKeepOnPhone(mealId, keep: true);
    await analyses.purgeRawBefore(_now.add(const Duration(days: 31)));
    await analyses.deleteAll();
    await analyses.recoverInterrupted(now: _now);

    expect(container.read(mealAnalysisRevisionProvider), 6);
    expect(container.read(dataRevisionProvider), 0);
  });
}
