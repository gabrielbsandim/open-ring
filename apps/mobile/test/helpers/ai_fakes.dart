import 'dart:async';

import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_run_state.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';

final class InMemorySecretStore implements SecretStore {
  final Map<String, String> values = {};
  int deleteCalls = 0;

  @override
  Future<String?> read(String name) async => values[name];

  @override
  Future<void> write(String name, String value) async {
    values[name] = value;
  }

  @override
  Future<void> delete(String name) async {
    deleteCalls++;
    values.remove(name);
  }
}

final class FailingSecretStore implements SecretStore {
  new({
    this.failRead = false,
    this.failWrite = false,
    this.failDelete = false,
    Object? error,
  }) : _error = error ?? StateError('keystore failure');

  final bool failRead;
  final bool failWrite;
  final bool failDelete;
  final Object _error;
  final Map<String, String> values = {};
  int deleteCalls = 0;

  @override
  Future<String?> read(String name) async {
    if (failRead) Error.throwWithStackTrace(_error, StackTrace.current);
    return values[name];
  }

  @override
  Future<void> write(String name, String value) async {
    if (failWrite) Error.throwWithStackTrace(_error, StackTrace.current);
    values[name] = value;
  }

  @override
  Future<void> delete(String name) async {
    deleteCalls++;
    if (failDelete) Error.throwWithStackTrace(_error, StackTrace.current);
    values.remove(name);
  }
}

final class InMemoryAiConfigStore implements AiConfigStore {
  AiConfig config = AiConfig.defaults;
  AiConsent? consent;
  AiMealPhotoConsent? mealPhotoConsent;
  final Map<String, AiCapabilityProfile> profiles = {};

  @override
  Future<AiConfig> readConfig() async => config;

  @override
  Future<void> writeConfig(AiConfig config) async {
    this.config = config;
  }

  @override
  Future<AiConsent?> readConsent() async => consent;

  @override
  Future<void> writeConsent(AiConsent consent) async {
    this.consent = consent;
  }

  @override
  Future<void> clearConsent() async {
    consent = null;
  }

  @override
  Future<AiMealPhotoConsent?> readMealPhotoConsent() async => mealPhotoConsent;

  @override
  Future<void> writeMealPhotoConsent(AiMealPhotoConsent consent) async {
    mealPhotoConsent = consent;
  }

  @override
  Future<void> clearMealPhotoConsent() async {
    mealPhotoConsent = null;
  }

  @override
  Future<AiCapabilityProfile?> readCapabilityProfile(
    String hostKey,
    String model,
  ) async => profiles[aiCapabilityProfileKey(hostKey, model)];

  @override
  Future<void> writeCapabilityProfile(
    String hostKey,
    String model,
    AiCapabilityProfile profile,
  ) async {
    profiles[aiCapabilityProfileKey(hostKey, model)] = profile;
  }

  @override
  Future<void> clearCapabilityProfiles() async {
    profiles.clear();
  }

  @override
  Future<void> clearAll() async {
    config = AiConfig.defaults;
    consent = null;
    mealPhotoConsent = null;
    profiles.clear();
  }
}

final class InMemoryAiReportStore implements AiReportStore {
  final List<AiReport> reports = [];
  int _nextId = 1;

  @override
  Future<int> insert(AiReport report) async {
    final id = _nextId++;
    reports.add(_withId(report, id));
    await applyRetention(report.createdAtUtc);
    return id;
  }

  @override
  Future<AiReport?> newestDone(AiReportCacheKey key) async {
    for (final report in _sorted()) {
      if (report.status == AiReportStatus.done && report.cacheKey == key) {
        return report;
      }
    }
    return null;
  }

  @override
  Future<List<AiReport>> recent({int limit = aiReportKeepCount}) async =>
      _sorted().take(limit).toList();

  @override
  Future<void> deleteAll() async => reports.clear();

  @override
  Future<void> applyRetention(DateTime nowUtc) async {
    final kept = _sorted().take(aiReportKeepCount).toList();
    final cutoff = nowUtc.subtract(const Duration(days: aiReportPayloadDays));
    reports
      ..clear()
      ..addAll([for (final r in kept) _purgedIfOlder(r, cutoff)]);
  }

  static AiReport _purgedIfOlder(AiReport r, DateTime cutoff) {
    if (r.createdAtUtc.isBefore(cutoff)) return _purged(r);
    return r;
  }

  List<AiReport> _sorted() => [...reports]
    ..sort((a, b) {
      final byTime = b.createdAtUtc.compareTo(a.createdAtUtc);
      return byTime != 0 ? byTime : b.id!.compareTo(a.id!);
    });

  static AiReport _withId(AiReport r, int id) =>
      _copy(r, id: id, payloadJson: r.payloadJson, rawText: r.rawText);

  static AiReport _purged(AiReport r) => _copy(r, id: r.id!);

  static AiReport _copy(
    AiReport r, {
    required int id,
    String? payloadJson,
    String? rawText,
  }) => AiReport(
    id: id,
    createdAtUtc: r.createdAtUtc,
    offsetMin: r.offsetMin,
    kind: r.kind,
    contextSchema: r.contextSchema,
    contextSha256: r.contextSha256,
    detailLevel: r.detailLevel,
    promptVersion: r.promptVersion,
    providerHost: r.providerHost,
    model: r.model,
    status: r.status,
    payloadJson: payloadJson,
    cardsJson: r.cardsJson,
    rawText: rawText,
    droppedCards: r.droppedCards,
    promptTokens: r.promptTokens,
    completionTokens: r.completionTokens,
    reasoningTokens: r.reasoningTokens,
    cost: r.cost,
    costCurrency: r.costCurrency,
    costSource: r.costSource,
    durationMs: r.durationMs,
    errorKind: r.errorKind,
  );
}

AiReport sampleAiReport({required DateTime at, String text = 'raw'}) =>
    AiReport(
      createdAtUtc: at,
      offsetMin: 0,
      kind: 'daily',
      contextSchema: 'health_context_v2',
      contextSha256: 'sha-$text',
      detailLevel: 'standard',
      promptVersion: 'v1',
      providerHost: 'reports.example.com',
      model: 'model-x',
      status: AiReportStatus.done,
      payloadJson: text,
      cardsJson: text,
      rawText: text,
    );

final class InMemoryAiRunMarkerStore implements AiRunMarkerStore {
  AiReport? value;
  int writes = 0;

  @override
  Future<AiReport?> read() async {
    await readGate?.future;
    final draft = value;
    if (draft == null) return null;
    return AiReport(
      createdAtUtc: draft.createdAtUtc,
      offsetMin: draft.offsetMin,
      kind: draft.kind,
      contextSchema: draft.contextSchema,
      contextSha256: draft.contextSha256,
      detailLevel: draft.detailLevel,
      promptVersion: draft.promptVersion,
      providerHost: draft.providerHost,
      model: draft.model,
      status: AiReportStatus.cancelled,
      errorKind: 'cancelled',
    );
  }

  @override
  Future<void> write(AiReport draft) async {
    writes++;
    await writeGate?.future;
    if (writeError != null) throw writeError!;
    value = draft;
  }

  @override
  Future<void> clear() async {
    if (clearError != null) throw clearError!;
    value = null;
  }

  String? month;
  int monthSum = 0;
  Completer<void>? readGate;
  Exception? writeError;
  Completer<void>? writeGate;
  Exception? clearError;

  @override
  Future<int> monthTokens(String month) async =>
      month == this.month ? monthSum : 0;

  @override
  Future<void> addMonthTokens(String month, int tokens) async {
    monthSum = await monthTokens(month) + tokens;
    this.month = month;
  }
}
