import 'package:meta/meta.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/ai_provider_preset.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/base_url_policy.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';

const int aiMinOutputTokens = 256;
const int aiDefaultOutputTokens = 4000;
const int aiMaxOutputTokens = 32000;
const List<int> aiAllowedTimeoutSeconds = [60, 180, 600];
const int aiMinPhotoDailyLimit = 1;
const int aiDefaultPhotoDailyLimit = 8;
const int aiMaxPhotoDailyLimit = 30;
const String aiCurrentPolicyEffectiveDate = '2026-11-25';

enum AiStructuredOutputMode { auto, jsonSchema, jsonObject, off }

enum AiStreamingMode { auto, off }

enum AiAvailability { off, notConfigured, notTested, consentNeeded, ready }

/// Optional parts of the summary; one turned on later asks for consent again.
enum AiDataCategory { body, energy, goals, food, imported }

@immutable
final class AiConfig {
  const new({
    this.preset = AiProviderPreset.openAi,
    this.baseUrl = '',
    this.model = '',
    this.detailLevel = AiDetailLevel.standard,
    this.contextWindow = AiContextWindow.standard,
    this.importedIncluded = false,
    this.maxOutputTokens = aiDefaultOutputTokens,
    this.requestTimeoutSeconds = 180,
    this.structuredOutputMode = AiStructuredOutputMode.auto,
    this.streamingMode = AiStreamingMode.auto,
    this.reasoningEffort,
    this.inputPricePerMillion,
    this.outputPricePerMillion,
    this.priceCurrency = 'USD',
    this.monthlyTokenCap,
    this.keyLastFour,
    this.testedAtUtcMs,
    this.testedHostKey,
    this.testedModel,
    this.photoModel,
    this.photoDailyLimit = aiDefaultPhotoDailyLimit,
  });

  factory fromJson(Map<String, Object?> json) {
    final timeout = json['requestTimeoutSeconds'];
    final currency = json['priceCurrency'];
    final cap = json['monthlyTokenCap'];
    final tokens = json['maxOutputTokens'];
    final daily = json['photoDailyLimit'];
    return AiConfig(
      preset: _enumByName(
        AiProviderPreset.values,
        json['preset'],
        AiProviderPreset.openAi,
      ),
      baseUrl: json['baseUrl'] is String ? json['baseUrl']! as String : '',
      model: json['model'] is String ? json['model']! as String : '',
      detailLevel: _enumByName(
        AiDetailLevel.values,
        json['detailLevel'],
        AiDetailLevel.standard,
      ),
      contextWindow: _enumByName(
        AiContextWindow.values,
        json['contextWindow'],
        AiContextWindow.standard,
      ),
      importedIncluded: json['importedIncluded'] == true,
      maxOutputTokens: tokens is int
          ? tokens.clamp(aiMinOutputTokens, aiMaxOutputTokens)
          : aiDefaultOutputTokens,
      requestTimeoutSeconds:
          timeout is int && aiAllowedTimeoutSeconds.contains(timeout)
          ? timeout
          : 180,
      structuredOutputMode: _enumByName(
        AiStructuredOutputMode.values,
        json['structuredOutputMode'],
        AiStructuredOutputMode.auto,
      ),
      streamingMode: _enumByName(
        AiStreamingMode.values,
        json['streamingMode'],
        AiStreamingMode.auto,
      ),
      reasoningEffort: _nullableEnumByName(
        AiReasoningEffort.values,
        json['reasoningEffort'],
      ),
      inputPricePerMillion: _nonNegDouble(json['inputPricePerMillion']),
      outputPricePerMillion: _nonNegDouble(json['outputPricePerMillion']),
      priceCurrency: currency is String && currency.trim().isNotEmpty
          ? currency.trim()
          : 'USD',
      monthlyTokenCap: cap is int && cap > 0 ? cap : null,
      keyLastFour: _validLastFour(json['keyLastFour']),
      testedAtUtcMs: json['testedAtUtcMs'] is int
          ? json['testedAtUtcMs']! as int
          : null,
      testedHostKey: _nonEmptyString(json['testedHostKey']),
      testedModel: _nonEmptyString(json['testedModel']),
      photoModel: _nonEmptyString(json['photoModel']),
      photoDailyLimit:
          daily is int &&
              daily >= aiMinPhotoDailyLimit &&
              daily <= aiMaxPhotoDailyLimit
          ? daily
          : aiDefaultPhotoDailyLimit,
    );
  }

  static const AiConfig defaults = AiConfig();

  final AiProviderPreset preset;
  final String baseUrl;
  final String model;
  final AiDetailLevel detailLevel;
  final AiContextWindow contextWindow;
  final bool importedIncluded;
  final int maxOutputTokens;
  final int requestTimeoutSeconds;
  final AiStructuredOutputMode structuredOutputMode;
  final AiStreamingMode streamingMode;
  final AiReasoningEffort? reasoningEffort;
  final double? inputPricePerMillion;
  final double? outputPricePerMillion;
  final String priceCurrency;
  final int? monthlyTokenCap;
  final String? keyLastFour;
  final int? testedAtUtcMs;
  final String? testedHostKey;
  final String? testedModel;
  final String? photoModel;
  final int photoDailyLimit;

  String get trimmedModel => model.trim();

  NormalizedBaseUrl? get normalizedUrl {
    final raw = baseUrl.trim();
    if (raw.isEmpty) return null;
    return switch (BaseUrlPolicy.parse(raw)) {
      BaseUrlOk(:final url) => url,
      BaseUrlRejected() => null,
    };
  }

  String? get hostKey => normalizedUrl?.hostKey;

  bool get isTestedForCurrentTarget =>
      testedAtUtcMs != null &&
      hostKey != null &&
      testedHostKey == hostKey &&
      trimmedModel.isNotEmpty &&
      testedModel == trimmedModel;

  static String? lastFourOf(String apiKey) {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) return null;
    final runes = trimmed.runes.toList();
    if (runes.length < 8) return '';
    return String.fromCharCodes(runes.sublist(runes.length - 4));
  }

  AiConfig copyWith({
    AiProviderPreset? preset,
    String? baseUrl,
    String? model,
    AiDetailLevel? detailLevel,
    AiContextWindow? contextWindow,
    bool? importedIncluded,
    int? maxOutputTokens,
    int? requestTimeoutSeconds,
    AiStructuredOutputMode? structuredOutputMode,
    AiStreamingMode? streamingMode,
    AiReasoningEffort? reasoningEffort,
    bool clearReasoningEffort = false,
    double? inputPricePerMillion,
    bool clearInputPrice = false,
    double? outputPricePerMillion,
    bool clearOutputPrice = false,
    String? priceCurrency,
    int? monthlyTokenCap,
    bool clearMonthlyTokenCap = false,
    String? keyLastFour,
    bool clearKeyLastFour = false,
    int? testedAtUtcMs,
    String? testedHostKey,
    String? testedModel,
    bool clearTested = false,
    String? photoModel,
    bool clearPhotoModel = false,
    int? photoDailyLimit,
  }) => AiConfig(
    preset: preset ?? this.preset,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    detailLevel: detailLevel ?? this.detailLevel,
    contextWindow: contextWindow ?? this.contextWindow,
    importedIncluded: importedIncluded ?? this.importedIncluded,
    maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
    requestTimeoutSeconds: requestTimeoutSeconds ?? this.requestTimeoutSeconds,
    structuredOutputMode: structuredOutputMode ?? this.structuredOutputMode,
    streamingMode: streamingMode ?? this.streamingMode,
    reasoningEffort: clearReasoningEffort
        ? null
        : reasoningEffort ?? this.reasoningEffort,
    inputPricePerMillion: clearInputPrice
        ? null
        : inputPricePerMillion ?? this.inputPricePerMillion,
    outputPricePerMillion: clearOutputPrice
        ? null
        : outputPricePerMillion ?? this.outputPricePerMillion,
    priceCurrency: priceCurrency ?? this.priceCurrency,
    monthlyTokenCap: clearMonthlyTokenCap
        ? null
        : monthlyTokenCap ?? this.monthlyTokenCap,
    keyLastFour: clearKeyLastFour ? null : keyLastFour ?? this.keyLastFour,
    testedAtUtcMs: clearTested ? null : testedAtUtcMs ?? this.testedAtUtcMs,
    testedHostKey: clearTested ? null : testedHostKey ?? this.testedHostKey,
    testedModel: clearTested ? null : testedModel ?? this.testedModel,
    photoModel: clearPhotoModel ? null : photoModel ?? this.photoModel,
    photoDailyLimit: photoDailyLimit ?? this.photoDailyLimit,
  );

  Map<String, Object?> toJson() => {
    'preset': preset.name,
    'baseUrl': baseUrl,
    'model': model,
    'detailLevel': detailLevel.name,
    'contextWindow': contextWindow.name,
    'importedIncluded': importedIncluded,
    'maxOutputTokens': maxOutputTokens,
    'requestTimeoutSeconds': requestTimeoutSeconds,
    'structuredOutputMode': structuredOutputMode.name,
    'streamingMode': streamingMode.name,
    if (reasoningEffort != null) 'reasoningEffort': reasoningEffort!.name,
    if (inputPricePerMillion != null)
      'inputPricePerMillion': inputPricePerMillion,
    if (outputPricePerMillion != null)
      'outputPricePerMillion': outputPricePerMillion,
    'priceCurrency': priceCurrency,
    if (monthlyTokenCap != null) 'monthlyTokenCap': monthlyTokenCap,
    if (keyLastFour != null) 'keyLastFour': keyLastFour,
    if (testedAtUtcMs != null) 'testedAtUtcMs': testedAtUtcMs,
    if (testedHostKey != null) 'testedHostKey': testedHostKey,
    if (testedModel != null) 'testedModel': testedModel,
    if (photoModel != null) 'photoModel': photoModel,
    'photoDailyLimit': photoDailyLimit,
  };

  @override
  bool operator ==(Object other) =>
      other is AiConfig &&
      other.preset == preset &&
      other.baseUrl == baseUrl &&
      other.model == model &&
      other.detailLevel == detailLevel &&
      other.contextWindow == contextWindow &&
      other.importedIncluded == importedIncluded &&
      other.maxOutputTokens == maxOutputTokens &&
      other.requestTimeoutSeconds == requestTimeoutSeconds &&
      other.structuredOutputMode == structuredOutputMode &&
      other.streamingMode == streamingMode &&
      other.reasoningEffort == reasoningEffort &&
      other.inputPricePerMillion == inputPricePerMillion &&
      other.outputPricePerMillion == outputPricePerMillion &&
      other.priceCurrency == priceCurrency &&
      other.monthlyTokenCap == monthlyTokenCap &&
      other.keyLastFour == keyLastFour &&
      other.testedAtUtcMs == testedAtUtcMs &&
      other.testedHostKey == testedHostKey &&
      other.testedModel == testedModel &&
      other.photoModel == photoModel &&
      other.photoDailyLimit == photoDailyLimit;

  @override
  int get hashCode => Object.hashAll([
    preset,
    baseUrl,
    model,
    detailLevel,
    contextWindow,
    importedIncluded,
    maxOutputTokens,
    requestTimeoutSeconds,
    structuredOutputMode,
    streamingMode,
    reasoningEffort,
    inputPricePerMillion,
    outputPricePerMillion,
    priceCurrency,
    monthlyTokenCap,
    keyLastFour,
    testedAtUtcMs,
    testedHostKey,
    testedModel,
    photoModel,
    photoDailyLimit,
  ]);

  @override
  String toString() =>
      'AiConfig(preset: ${preset.name}, host: ${hostKey ?? "unset"}, '
      'model: $trimmedModel)';
}

@immutable
final class AiConsent {
  const new({
    required this.consentedAtUtcMs,
    required this.policyEffectiveDate,
    required this.hostKey,
    required this.detailLevel,
    required this.contextSchemaVersion,
    this.categories = const {},
  });

  final int consentedAtUtcMs;
  final String policyEffectiveDate;
  final String hostKey;
  final AiDetailLevel detailLevel;
  final String contextSchemaVersion;
  final Set<AiDataCategory> categories;

  bool covers({
    required String hostKey,
    required AiDetailLevel detailLevel,
    required String contextSchemaVersion,
    required String policyEffectiveDate,
    Set<AiDataCategory> categories = const {},
  }) =>
      this.hostKey == hostKey &&
      this.contextSchemaVersion == contextSchemaVersion &&
      this.policyEffectiveDate == policyEffectiveDate &&
      this.detailLevel.index >= detailLevel.index &&
      this.categories.containsAll(categories);

  Map<String, Object?> toJson() => {
    'consentedAtUtcMs': consentedAtUtcMs,
    'policyEffectiveDate': policyEffectiveDate,
    'hostKey': hostKey,
    'detailLevel': detailLevel.name,
    'contextSchemaVersion': contextSchemaVersion,
    'categories': [
      for (final c in AiDataCategory.values)
        if (categories.contains(c)) c.name,
    ],
  };

  static AiConsent? tryFromJson(Map<String, Object?> json) {
    final ts = json['consentedAtUtcMs'];
    final date = _nonEmptyString(json['policyEffectiveDate']);
    final host = _nonEmptyString(json['hostKey']);
    final schema = _nonEmptyString(json['contextSchemaVersion']);
    final detail = _nullableEnumByName(
      AiDetailLevel.values,
      json['detailLevel'],
    );
    if (ts is! int ||
        date == null ||
        host == null ||
        schema == null ||
        detail == null) {
      return null;
    }
    final names = json['categories'];
    return AiConsent(
      consentedAtUtcMs: ts,
      policyEffectiveDate: date,
      hostKey: host,
      detailLevel: detail,
      contextSchemaVersion: schema,
      categories: {
        if (names is List)
          for (final n in names) ?_nullableEnumByName(AiDataCategory.values, n),
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AiConsent &&
      other.consentedAtUtcMs == consentedAtUtcMs &&
      other.policyEffectiveDate == policyEffectiveDate &&
      other.hostKey == hostKey &&
      other.detailLevel == detailLevel &&
      other.contextSchemaVersion == contextSchemaVersion &&
      other.categories.length == categories.length &&
      other.categories.containsAll(categories);

  @override
  int get hashCode => Object.hash(
    consentedAtUtcMs,
    policyEffectiveDate,
    hostKey,
    detailLevel,
    contextSchemaVersion,
    Object.hashAllUnordered(categories),
  );
}

@immutable
final class AiMealPhotoConsent {
  const new({
    required this.consentedAtUtcMs,
    required this.policyEffectiveDate,
    required this.hostKey,
  });

  final int consentedAtUtcMs;
  final String policyEffectiveDate;
  final String hostKey;

  bool covers({required String hostKey, required String policyEffectiveDate}) =>
      this.hostKey == hostKey &&
      this.policyEffectiveDate == policyEffectiveDate;

  Map<String, Object?> toJson() => {
    'consentedAtUtcMs': consentedAtUtcMs,
    'policyEffectiveDate': policyEffectiveDate,
    'hostKey': hostKey,
  };

  static AiMealPhotoConsent? tryFromJson(Map<String, Object?> json) {
    final ts = json['consentedAtUtcMs'];
    final date = _nonEmptyString(json['policyEffectiveDate']);
    final host = _nonEmptyString(json['hostKey']);
    if (ts is! int || date == null || host == null) return null;
    return AiMealPhotoConsent(
      consentedAtUtcMs: ts,
      policyEffectiveDate: date,
      hostKey: host,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AiMealPhotoConsent &&
      other.consentedAtUtcMs == consentedAtUtcMs &&
      other.policyEffectiveDate == policyEffectiveDate &&
      other.hostKey == hostKey;

  @override
  int get hashCode =>
      Object.hash(consentedAtUtcMs, policyEffectiveDate, hostKey);
}

enum AiPhotoQueuePauseReason { unauthorized, noCredit, forbidden, noVision }

/// Why the photo queue stopped sending, bound to the target that refused.
@immutable
final class AiPhotoQueuePause {
  const new({
    required this.reason,
    required this.hostKey,
    required this.model,
    required this.keyLastFour,
    required this.atUtcMs,
  });

  final AiPhotoQueuePauseReason reason;
  final String hostKey;
  final String model;
  final String? keyLastFour;
  final int atUtcMs;

  /// A new host, photo model or key lifts the pause.
  bool holds({
    required String? hostKey,
    required String model,
    required String? keyLastFour,
  }) =>
      this.hostKey == hostKey &&
      this.model == model &&
      this.keyLastFour == keyLastFour;

  Map<String, Object?> toJson() => {
    'reason': reason.name,
    'hostKey': hostKey,
    'model': model,
    'keyLastFour': keyLastFour,
    'atUtcMs': atUtcMs,
  };

  static AiPhotoQueuePause? tryFromJson(Map<String, Object?> json) {
    final reason = _nullableEnumByName(
      AiPhotoQueuePauseReason.values,
      json['reason'],
    );
    final host = _nonEmptyString(json['hostKey']);
    final model = _nonEmptyString(json['model']);
    final at = json['atUtcMs'];
    final last = _validLastFour(json['keyLastFour']);
    if (reason == null || host == null || model == null || at is! int) {
      return null;
    }
    if (last == null && json['keyLastFour'] != null) return null;
    return AiPhotoQueuePause(
      reason: reason,
      hostKey: host,
      model: model,
      keyLastFour: last,
      atUtcMs: at,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AiPhotoQueuePause &&
      other.reason == reason &&
      other.hostKey == hostKey &&
      other.model == model &&
      other.keyLastFour == keyLastFour &&
      other.atUtcMs == atUtcMs;

  @override
  int get hashCode => Object.hash(reason, hostKey, model, keyLastFour, atUtcMs);
}

String aiCapabilityProfileKey(String hostKey, String model) =>
    '$hostKey|${model.trim()}';

AiAvailability resolveAiAvailability({
  required bool moduleEnabled,
  required AiConfig config,
  required bool hasStoredKey,
  required AiConsent? consent,
  String contextSchemaVersion = aiContextSchemaVersion,
  String policyEffectiveDate = aiCurrentPolicyEffectiveDate,
}) {
  if (!moduleEnabled) return AiAvailability.off;
  final url = config.normalizedUrl;
  if (url == null || config.trimmedModel.isEmpty) {
    return AiAvailability.notConfigured;
  }
  if (config.preset.keyRequired && !hasStoredKey) {
    return AiAvailability.notConfigured;
  }
  if (!config.isTestedForCurrentTarget) return AiAvailability.notTested;
  final ok =
      consent != null &&
      consent.covers(
        hostKey: url.hostKey,
        detailLevel: config.detailLevel,
        contextSchemaVersion: contextSchemaVersion,
        policyEffectiveDate: policyEffectiveDate,
      );
  return ok ? AiAvailability.ready : AiAvailability.consentNeeded;
}

abstract interface class AiConfigStore {
  Future<AiConfig> readConfig();
  Future<void> writeConfig(AiConfig config);
  Future<AiConsent?> readConsent();
  Future<void> writeConsent(AiConsent consent);
  Future<void> clearConsent();
  Future<AiMealPhotoConsent?> readMealPhotoConsent();
  Future<void> writeMealPhotoConsent(AiMealPhotoConsent consent);
  Future<void> clearMealPhotoConsent();
  Future<AiPhotoQueuePause?> readPhotoQueuePause();
  Future<void> writePhotoQueuePause(AiPhotoQueuePause pause);
  Future<void> clearPhotoQueuePause();
  Future<AiCapabilityProfile?> readCapabilityProfile(
    String hostKey,
    String model,
  );
  Future<void> writeCapabilityProfile(
    String hostKey,
    String model,
    AiCapabilityProfile profile,
  );
  Future<void> clearCapabilityProfiles();
  Future<void> clearAll();
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    _nullableEnumByName(values, raw) ?? fallback;

T? _nullableEnumByName<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! String) return null;
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return null;
}

double? _nonNegDouble(Object? raw) =>
    raw is num && raw.isFinite && raw >= 0 ? raw.toDouble() : null;

String? _nonEmptyString(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _validLastFour(Object? raw) {
  if (raw is! String) return null;
  return raw.runes.length <= 4 ? raw : null;
}
