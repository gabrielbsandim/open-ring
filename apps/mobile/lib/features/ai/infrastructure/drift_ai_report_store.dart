import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';

final class DriftAiReportStore implements AiReportStore {
  new(this._db);

  final AppDatabase _db;

  // Retention is measured from the report's own timestamp so an insert
  // never depends on a wall clock the caller did not pass.
  @override
  Future<int> insert(AiReport report) => _db.transaction(() async {
    final id = await _db.into(_db.aiReports).insert(_companion(report));
    await _retain(report.createdAtUtc);
    return id;
  });

  @override
  Future<AiReport?> newestDone(AiReportCacheKey key) async {
    final query = _db.select(_db.aiReports)
      ..where(
        (r) =>
            r.kind.equals(key.kind) &
            r.contextSha256.equals(key.contextSha256) &
            r.promptVersion.equals(key.promptVersion) &
            r.providerHost.equals(key.providerHost) &
            r.model.equals(key.model) &
            r.status.equals(AiReportStatus.done.wire),
      )
      ..orderBy(_newestFirst)
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : _report(row);
  }

  @override
  Future<List<AiReport>> recent({int limit = aiReportKeepCount}) async {
    final query = _db.select(_db.aiReports)
      ..orderBy(_newestFirst)
      ..limit(limit);
    return [for (final row in await query.get()) _report(row)];
  }

  @override
  Future<void> deleteAll() => _db.delete(_db.aiReports).go();

  @override
  Future<void> applyRetention(DateTime nowUtc) =>
      _db.transaction(() => _retain(nowUtc));

  Future<void> _retain(DateTime nowUtc) async {
    await _db.customStatement(
      'DELETE FROM ai_reports WHERE id NOT IN (SELECT id FROM ai_reports '
      'ORDER BY created_at_utc_ms DESC, id DESC LIMIT ?)',
      [aiReportKeepCount],
    );
    final cutoff = nowUtc.subtract(const Duration(days: aiReportPayloadDays));
    await (_db.update(_db.aiReports)..where(
          (r) => r.createdAtUtcMs.isSmallerThanValue(
            cutoff.millisecondsSinceEpoch,
          ),
        ))
        .write(
          const AiReportsCompanion(
            payloadJson: Value(null),
            rawText: Value(null),
          ),
        );
  }

  static List<OrderingTerm Function($AiReportsTable)> get _newestFirst => [
    (r) => OrderingTerm.desc(r.createdAtUtcMs),
    (r) => OrderingTerm.desc(r.id),
  ];

  static AiReportsCompanion _companion(AiReport r) => AiReportsCompanion.insert(
    createdAtUtcMs: r.createdAtUtc.millisecondsSinceEpoch,
    offsetMin: r.offsetMin,
    kind: r.kind,
    contextSchema: r.contextSchema,
    contextSha256: r.contextSha256,
    detailLevel: r.detailLevel,
    promptVersion: r.promptVersion,
    providerHost: r.providerHost,
    model: r.model,
    status: r.status.wire,
    payloadJson: Value(r.payloadJson),
    cardsJson: Value(r.cardsJson),
    rawText: Value(r.rawText),
    droppedCards: Value(r.droppedCards),
    promptTokens: Value(r.promptTokens),
    completionTokens: Value(r.completionTokens),
    reasoningTokens: Value(r.reasoningTokens),
    cost: Value(r.cost),
    costCurrency: Value(r.costCurrency),
    costSource: r.costSource.wire,
    durationMs: Value(r.durationMs),
    errorKind: Value(r.errorKind),
  );

  static AiReport _report(AiReportRow row) => AiReport(
    id: row.id,
    createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
      row.createdAtUtcMs,
      isUtc: true,
    ),
    offsetMin: row.offsetMin,
    kind: row.kind,
    contextSchema: row.contextSchema,
    contextSha256: row.contextSha256,
    detailLevel: row.detailLevel,
    promptVersion: row.promptVersion,
    providerHost: row.providerHost,
    model: row.model,
    status: AiReportStatus.fromWire(row.status),
    payloadJson: row.payloadJson,
    cardsJson: row.cardsJson,
    rawText: row.rawText,
    droppedCards: row.droppedCards,
    promptTokens: row.promptTokens,
    completionTokens: row.completionTokens,
    reasoningTokens: row.reasoningTokens,
    cost: row.cost,
    costCurrency: row.costCurrency,
    costSource: AiCostSource.fromWire(row.costSource),
    durationMs: row.durationMs,
    errorKind: row.errorKind,
  );
}
