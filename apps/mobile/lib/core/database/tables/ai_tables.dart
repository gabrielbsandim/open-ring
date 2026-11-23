import 'package:drift/drift.dart';

@DataClassName('AiReportRow')
@TableIndex(
  name: 'ai_reports_cache_key',
  columns: {
    #kind,
    #contextSha256,
    #promptVersion,
    #providerHost,
    #model,
    #createdAtUtcMs,
  },
)
class AiReports extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get createdAtUtcMs => integer()();
  IntColumn get offsetMin => integer()();
  TextColumn get kind => text()();
  TextColumn get contextSchema => text()();
  TextColumn get contextSha256 => text()();
  TextColumn get detailLevel => text()();
  TextColumn get promptVersion => text()();
  TextColumn get providerHost => text()();
  TextColumn get model => text()();
  TextColumn get status => text()();
  TextColumn get payloadJson => text().nullable()();
  TextColumn get cardsJson => text().nullable()();
  TextColumn get rawText => text().nullable()();
  IntColumn get droppedCards => integer().withDefault(const Constant(0))();
  IntColumn get promptTokens => integer().nullable()();
  IntColumn get completionTokens => integer().nullable()();
  IntColumn get reasoningTokens => integer().nullable()();
  RealColumn get cost => real().nullable()();
  TextColumn get costCurrency => text().nullable()();
  TextColumn get costSource => text()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get errorKind => text().nullable()();
}
