import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/ai/domain/meal_photo_result.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/domain/meal_analysis_store.dart';

typedef _Where = Expression<bool> Function($MealAnalysesTable r);

const List<MealAnalysisStatus> _queued = [MealAnalysisStatus.queued];
const List<MealAnalysisStatus> _sending = [MealAnalysisStatus.sending];

final class DriftMealAnalysisStore implements MealAnalysisStore {
  new(this._db, {this.onWrite});

  final AppDatabase _db;
  final void Function()? onWrite;

  @override
  Future<MealAnalysis> enqueue(
    int mealId,
    String photoName,
    MealAnalysisTarget target, {
    required DateTime now,
    bool again = false,
  }) => _write(() async {
    final ms = now.millisecondsSinceEpoch;
    final found = await _read(
      (r) =>
          r.mealId.equals(mealId) &
          r.providerHost.equals(target.providerHost) &
          r.model.equals(target.model) &
          r.promptVersion.equals(target.promptVersion),
    );
    final row = found.firstOrNull;
    if (row == null) {
      final id = await _db
          .into(_db.mealAnalyses)
          .insert(
            MealAnalysesCompanion.insert(
              mealId: mealId,
              photoName: photoName,
              status: MealAnalysisStatus.queued.wire,
              providerHost: target.providerHost,
              model: target.model,
              promptVersion: target.promptVersion,
              outputSchema: target.outputSchema,
              queuedAtUtcMs: ms,
              updatedAtUtcMs: ms,
            ),
          );
      return await _load(id);
    }
    final same = row.photoName == photoName && row.target == target;
    final reuse =
        row.status == MealAnalysisStatus.queued ||
        row.status.isAnswer && !again;
    if (row.status == MealAnalysisStatus.sending || same && reuse) return row;
    // Keeps user items and hidden chips; everything the last request wrote
    // goes, so a reset row reads as never sent.
    await _db.customStatement(
      "UPDATE meal_analyses SET status = 'queued', photo_name = ?, "
      'output_schema = ?, sent_sha256 = NULL, sent_width = NULL, '
      'sent_height = NULL, sent_bytes = NULL, result_json = NULL, '
      'raw_text = NULL, confidence = NULL, prompt_tokens = NULL, '
      'completion_tokens = NULL, reasoning_tokens = NULL, cost = NULL, '
      'cost_currency = NULL, cost_source = NULL, attempts = 0, '
      'error_kind = NULL, queued_at_utc_ms = ?, updated_at_utc_ms = ? '
      'WHERE id = ?',
      [photoName, target.outputSchema, ms, ms, row.id],
    );
    await _deleteModelItems(row.id);
    return await _load(row.id);
  });

  @override
  Future<List<MealAnalysis>> byMeal(int mealId) =>
      _read((r) => r.mealId.equals(mealId));

  @override
  Future<MealAnalysis?> byId(int id) async =>
      (await _read(_id(id))).firstOrNull;

  @override
  Future<MealAnalysis?> next() async => (await _read(
    (r) => r.status.equals(MealAnalysisStatus.queued.wire),
    limit: 1,
  )).firstOrNull;

  @override
  Future<bool> markSending(int id, {required DateTime now}) => _moveOne(
    id,
    _queued,
    MealAnalysesCompanion.custom(
      status: Constant(MealAnalysisStatus.sending.wire),
      attempts: _db.mealAnalyses.attempts + const Constant(1),
      updatedAtUtcMs: Constant(now.millisecondsSinceEpoch),
    ),
  );

  @override
  Future<bool> requeue(int id, {required DateTime now}) => _moveOne(
    id,
    _sending,
    MealAnalysesCompanion.custom(
      status: Constant(MealAnalysisStatus.queued.wire),
      attempts: _db.mealAnalyses.attempts - const Constant(1),
      updatedAtUtcMs: Constant(now.millisecondsSinceEpoch),
    ),
  );

  @override
  Future<bool> countResend(int id, {required DateTime now}) => _moveOne(
    id,
    _sending,
    MealAnalysesCompanion.custom(
      attempts: _db.mealAnalyses.attempts + const Constant(1),
      updatedAtUtcMs: Constant(now.millisecondsSinceEpoch),
    ),
  );

  @override
  Future<bool> retry(int id, {required DateTime now}) => _moveOne(
    id,
    const [MealAnalysisStatus.failed, MealAnalysisStatus.rejected],
    MealAnalysesCompanion(
      status: Value(MealAnalysisStatus.queued.wire),
      errorKind: const Value(null),
      updatedAtUtcMs: Value(now.millisecondsSinceEpoch),
    ),
  );

  @override
  Future<bool> complete(
    int id,
    MealAnalysisAnswer answer, {
    required DateTime now,
  }) => _write(() async {
    final written = await _move(_sending, _answer(answer, now), _id(id));
    if (written == 0) return false;
    await _deleteModelItems(id);
    final items = answer.suggestion?.items ?? const <MealPhotoItem>[];
    await _db.batch(
      (batch) => batch.insertAll(_db.mealItems, [
        for (final (i, item) in items.indexed)
          MealItemsCompanion.insert(
            analysisId: id,
            position: i,
            name: item.name,
            measure: mealWireName(item.measure),
            countX2: item.countX2,
            grams: item.grams,
            origin: MealItemOrigin.model.name,
          ),
      ]),
    );
    return true;
  });

  @override
  Future<bool> fail(int id, String errorKind, {required DateTime now}) =>
      _moveOne(id, const [
        MealAnalysisStatus.queued,
        MealAnalysisStatus.sending,
      ], _stop(MealAnalysisStatus.failed, errorKind, now));

  @override
  Future<bool> skip(int id, String reason, {required DateTime now}) =>
      _moveOne(id, _queued, _stop(MealAnalysisStatus.skipped, reason, now));

  @override
  Future<int> countQueuedSince(DateTime since) => _db.mealAnalyses
      .count(
        where: (r) =>
            r.queuedAtUtcMs.isBiggerOrEqualValue(since.millisecondsSinceEpoch) &
            r.status.equals(MealAnalysisStatus.skipped.wire).not(),
      )
      .getSingle();

  @override
  Future<int> countQueued() => _db.mealAnalyses
      .count(where: (r) => r.status.equals(MealAnalysisStatus.queued.wire))
      .getSingle();

  @override
  Future<int> expireBefore(DateTime cutoff, {required DateTime now}) => _write(
    () => _move(
      _queued,
      _stop(MealAnalysisStatus.skipped, MealAnalysisErrorKind.expired, now),
      (r) => r.queuedAtUtcMs.isSmallerThanValue(cutoff.millisecondsSinceEpoch),
    ),
  );

  @override
  Future<int> skipOffTarget(
    String providerHost,
    String model, {
    required DateTime now,
  }) => _write(
    () => _move(
      _queued,
      _stop(
        MealAnalysisStatus.skipped,
        MealAnalysisErrorKind.targetChanged,
        now,
      ),
      (r) =>
          r.providerHost.equals(providerHost).not() |
          r.model.equals(model).not(),
    ),
  );

  @override
  Future<int> recoverInterrupted({required DateTime now}) => _write(
    () => _move(
      _sending,
      _stop(MealAnalysisStatus.failed, MealAnalysisErrorKind.interrupted, now),
    ),
  );

  @override
  Future<int> purgeRawBefore(DateTime cutoff) => _write(
    () => _db.customUpdate(
      'UPDATE meal_analyses SET raw_text = NULL '
      'WHERE raw_text IS NOT NULL AND updated_at_utc_ms < ?',
      variables: [Variable.withInt(cutoff.millisecondsSinceEpoch)],
      updates: {_db.mealAnalyses},
    ),
  );

  @override
  Future<bool> keepOnPhone(int mealId) async {
    final query = _db.select(_db.meals)..where((m) => m.id.equals(mealId));
    return (await query.getSingleOrNull())?.keepOnPhone ?? false;
  }

  @override
  Future<bool> setKeepOnPhone(int mealId, {required bool keep}) => _write(
    () async =>
        await (_db.update(_db.meals)..where((m) => m.id.equals(mealId))).write(
          MealsCompanion(keepOnPhone: Value(keep)),
        ) >
        0,
  );

  @override
  Future<void> deleteAll() => _write(() => _db.delete(_db.mealAnalyses).go());

  Future<T> _write<T>(Future<T> Function() body) async {
    final result = await _db.transaction(body);
    if (result != false && result != 0) onWrite?.call();
    return result;
  }

  Future<int> _move(
    List<MealAnalysisStatus> from,
    Insertable<MealAnalysisRow> to, [
    _Where? where,
  ]) {
    final query = _db.update(_db.mealAnalyses)
      ..where((r) => r.status.isIn([for (final s in from) s.wire]));
    if (where != null) query.where(where);
    return query.write(to);
  }

  Future<bool> _moveOne(
    int id,
    List<MealAnalysisStatus> from,
    Insertable<MealAnalysisRow> to,
  ) => _write(() async => await _move(from, to, _id(id)) > 0);

  static _Where _id(int id) =>
      (r) => r.id.equals(id);

  Future<void> _deleteModelItems(int id) =>
      (_db.delete(_db.mealItems)..where(
            (i) =>
                i.analysisId.equals(id) &
                i.origin.equals(MealItemOrigin.model.name),
          ))
          .go();

  Future<MealAnalysis> _load(int id) async => (await _read(_id(id))).single;

  Future<List<MealAnalysis>> _read(_Where where, {int? limit}) async {
    final query = _db.select(_db.mealAnalyses)
      ..where(where)
      ..orderBy([
        (r) => OrderingTerm.asc(r.queuedAtUtcMs),
        (r) => OrderingTerm.asc(r.id),
      ]);
    if (limit != null) query.limit(limit);
    final rows = await query.get();
    final items =
        await (_db.select(_db.mealItems)
              ..where((i) => i.analysisId.isIn([for (final r in rows) r.id]))
              ..orderBy([
                (i) => OrderingTerm.asc(i.position),
                (i) => OrderingTerm.asc(i.id),
              ]))
            .get();
    return [
      for (final r in rows)
        _analysis(r, [
          for (final i in items)
            if (i.analysisId == r.id) _item(i),
        ]),
    ];
  }

  static MealAnalysesCompanion _stop(
    MealAnalysisStatus status,
    String errorKind,
    DateTime now,
  ) => MealAnalysesCompanion(
    status: Value(status.wire),
    errorKind: Value(errorKind),
    updatedAtUtcMs: Value(now.millisecondsSinceEpoch),
  );

  static MealAnalysesCompanion _answer(MealAnalysisAnswer a, DateTime now) {
    final json = a.suggestion?.toJson();
    return MealAnalysesCompanion(
      status: Value(a.status.wire),
      sentSha256: Value(a.sent.sha256),
      sentWidth: Value(a.sent.width),
      sentHeight: Value(a.sent.height),
      sentBytes: Value(a.sent.bytes),
      resultJson: Value(json == null ? null : jsonEncode(json)),
      rawText: Value(a.rawText),
      confidence: Value(a.confidence?.name),
      promptTokens: Value(a.usage?.promptTokens),
      completionTokens: Value(a.usage?.completionTokens),
      reasoningTokens: Value(a.usage?.reasoningTokens),
      cost: Value(a.cost?.cost),
      costCurrency: Value(a.cost?.currency),
      costSource: Value(a.cost?.source.wire),
      errorKind: Value(a.errorKind),
      updatedAtUtcMs: Value(now.millisecondsSinceEpoch),
    );
  }

  static MealAnalysis _analysis(
    MealAnalysisRow r,
    List<MealAnalysisItem> items,
  ) => (
    id: r.id,
    mealId: r.mealId,
    photoName: r.photoName,
    status: MealAnalysisStatus.fromWire(r.status),
    target: (
      providerHost: r.providerHost,
      model: r.model,
      promptVersion: r.promptVersion,
      outputSchema: r.outputSchema,
    ),
    queuedAt: _utc(r.queuedAtUtcMs),
    updatedAt: _utc(r.updatedAtUtcMs),
    sent: switch ((r.sentSha256, r.sentWidth, r.sentHeight, r.sentBytes)) {
      (final String sha, final int w, final int h, final int b) => (
        sha256: sha,
        width: w,
        height: h,
        bytes: b,
      ),
      _ => null,
    },
    resultJson: r.resultJson,
    rawText: r.rawText,
    confidence: mealEnumFromWire(MealPhotoConfidence.values, r.confidence),
    attempts: r.attempts,
    errorKind: r.errorKind,
    hiddenOil: r.hiddenOil,
    hiddenSauce: r.hiddenSauce,
    hiddenSugar: r.hiddenSugar,
    items: List.unmodifiable(items),
  );

  static MealAnalysisItem _item(MealItemRow row) => (
    name: row.name,
    measure:
        mealEnumFromWire(MealPhotoMeasure.values, row.measure) ??
        MealPhotoMeasure.unit,
    countX2: row.countX2,
    grams: row.grams,
    origin: MealItemOrigin.values.byName(row.origin),
    confirmed: row.confirmed,
  );

  static DateTime _utc(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}
