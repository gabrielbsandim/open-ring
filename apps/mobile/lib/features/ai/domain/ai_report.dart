import 'package:meta/meta.dart';

const int aiReportKeepCount = 60;
const int aiReportPayloadDays = 30;

enum AiReportStatus {
  done('done'),
  failed('failed'),
  cancelled('cancelled');

  new(this.wire);

  final String wire;

  static AiReportStatus fromWire(String raw) =>
      values.firstWhere((s) => s.wire == raw, orElse: () => failed);
}

enum AiCostSource {
  provider('provider'),
  userPrice('user_price'),
  none('none');

  new(this.wire);

  final String wire;

  static AiCostSource fromWire(String raw) =>
      values.firstWhere((s) => s.wire == raw, orElse: () => none);
}

@immutable
final class AiReportCacheKey {
  const new({
    required this.kind,
    required this.contextSha256,
    required this.promptVersion,
    required this.providerHost,
    required this.model,
  });

  final String kind;
  final String contextSha256;
  final String promptVersion;
  final String providerHost;
  final String model;

  @override
  bool operator ==(Object other) =>
      other is AiReportCacheKey &&
      other.kind == kind &&
      other.contextSha256 == contextSha256 &&
      other.promptVersion == promptVersion &&
      other.providerHost == providerHost &&
      other.model == model;

  @override
  int get hashCode =>
      Object.hash(kind, contextSha256, promptVersion, providerHost, model);
}

@immutable
final class AiReport {
  const new({
    required this.createdAtUtc,
    required this.offsetMin,
    required this.kind,
    required this.contextSchema,
    required this.contextSha256,
    required this.detailLevel,
    required this.promptVersion,
    required this.providerHost,
    required this.model,
    required this.status,
    this.id,
    this.payloadJson,
    this.cardsJson,
    this.rawText,
    this.droppedCards = 0,
    this.promptTokens,
    this.completionTokens,
    this.reasoningTokens,
    this.cost,
    this.costCurrency,
    this.costSource = AiCostSource.none,
    this.durationMs,
    this.errorKind,
  });

  final int? id;
  final DateTime createdAtUtc;
  final int offsetMin;
  final String kind;
  final String contextSchema;
  final String contextSha256;
  final String detailLevel;
  final String promptVersion;
  final String providerHost;
  final String model;
  final AiReportStatus status;
  final String? payloadJson;
  final String? cardsJson;
  final String? rawText;
  final int droppedCards;
  final int? promptTokens;
  final int? completionTokens;
  final int? reasoningTokens;
  final double? cost;
  final String? costCurrency;
  final AiCostSource costSource;
  final int? durationMs;
  final String? errorKind;

  AiReportCacheKey get cacheKey => AiReportCacheKey(
    kind: kind,
    contextSha256: contextSha256,
    promptVersion: promptVersion,
    providerHost: providerHost,
    model: model,
  );
}

abstract interface class AiReportStore {
  /// Inserts and applies retention in one step; returns the new id.
  Future<int> insert(AiReport report);

  Future<AiReport?> newestDone(AiReportCacheKey key);

  /// Newest first.
  Future<List<AiReport>> recent({int limit = aiReportKeepCount});

  Future<void> deleteAll();

  Future<void> applyRetention(DateTime nowUtc);
}
