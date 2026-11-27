import 'package:meta/meta.dart';

const int aiMaxResponseBytes = 256 * 1024;
const int aiMaxErrorDetailChars = 300;

/// Ladder cap per spec 1.4: 1 initial attempt plus up to 3 step-downs.
const int aiMaxLadderAttempts = 4;

enum AiJsonMode { jsonSchema, jsonObject, none }

enum AiLimitField { maxCompletionTokens, maxTokens }

enum AiReasoningEffort { low, medium, high }

enum AiVisionSupport { unknown, yes, no }

/// Output modes the person forced in Advanced; a forced axis holds through
/// every ladder step. Both null and false means Auto.
@immutable
final class AiOutputPin {
  const new({this.jsonMode, this.streamOff = false});

  static const AiOutputPin none = AiOutputPin();

  final AiJsonMode? jsonMode;
  final bool streamOff;

  bool get isAuto => jsonMode == null && !streamOff;

  AiCapabilityProfile apply(AiCapabilityProfile profile) => profile.copyWith(
    jsonMode: jsonMode ?? profile.jsonMode,
    streamOk: profile.streamOk && !streamOff,
  );

  @override
  bool operator ==(Object other) =>
      other is AiOutputPin &&
      other.jsonMode == jsonMode &&
      other.streamOff == streamOff;

  @override
  int get hashCode => Object.hash(jsonMode, streamOff);
}

@immutable
final class AiCapabilityProfile {
  const new({
    this.jsonMode = AiJsonMode.jsonSchema,
    this.limitField = AiLimitField.maxCompletionTokens,
    this.streamOk = true,
    this.streamUsageOk = true,
    this.vision = AiVisionSupport.unknown,
  });

  factory fromJson(Map<String, Object?> json) => AiCapabilityProfile(
    jsonMode: _enumByName(
      AiJsonMode.values,
      json['jsonMode'],
      AiJsonMode.jsonSchema,
    ),
    limitField: _enumByName(
      AiLimitField.values,
      json['limitField'],
      AiLimitField.maxCompletionTokens,
    ),
    streamOk: json['streamOk'] != false,
    streamUsageOk: json['streamUsageOk'] != false,
    vision: _enumByName(
      AiVisionSupport.values,
      json['vision'],
      AiVisionSupport.unknown,
    ),
  );

  static const AiCapabilityProfile defaults = AiCapabilityProfile();

  final AiJsonMode jsonMode;
  final AiLimitField limitField;
  final bool streamOk;
  final bool streamUsageOk;
  final AiVisionSupport vision;

  AiCapabilityProfile copyWith({
    AiJsonMode? jsonMode,
    AiLimitField? limitField,
    bool? streamOk,
    bool? streamUsageOk,
    AiVisionSupport? vision,
  }) => AiCapabilityProfile(
    jsonMode: jsonMode ?? this.jsonMode,
    limitField: limitField ?? this.limitField,
    streamOk: streamOk ?? this.streamOk,
    streamUsageOk: streamUsageOk ?? this.streamUsageOk,
    vision: vision ?? this.vision,
  );

  /// Steps down one wire capability on an HTTP 400 before billing occurs,
  /// returning null once every applicable step is exhausted or unmatched.
  /// An [imageRequest] refused for its image stops here.
  AiCapabilityProfile? nextOnBadRequest(
    String errorMessage, {
    bool imageRequest = false,
  }) {
    final lower = errorMessage.toLowerCase();
    if (imageRequest && _refusesImage(lower)) return null;
    if (streamOk && streamUsageOk && lower.contains('stream_options')) {
      return copyWith(streamUsageOk: false);
    }
    if (limitField == AiLimitField.maxCompletionTokens &&
        lower.contains('max_completion_tokens')) {
      return copyWith(limitField: AiLimitField.maxTokens);
    }
    if (streamOk &&
        lower.contains('stream') &&
        !lower.contains('stream_options')) {
      return copyWith(streamOk: false);
    }
    if (jsonMode == AiJsonMode.jsonSchema &&
        streamOk &&
        !lower.contains('json_schema') &&
        !lower.contains('response_format')) {
      return copyWith(streamOk: false);
    }
    if (jsonMode == AiJsonMode.jsonSchema) {
      return copyWith(jsonMode: AiJsonMode.jsonObject, streamOk: true);
    }
    if (jsonMode == AiJsonMode.jsonObject) {
      return copyWith(jsonMode: AiJsonMode.none);
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'jsonMode': jsonMode.name,
    'limitField': limitField.name,
    'streamOk': streamOk,
    'streamUsageOk': streamUsageOk,
    'vision': vision.name,
  };

  static T _enumByName<T extends Enum>(
    List<T> values,
    Object? raw,
    T fallback,
  ) {
    if (raw is! String) return fallback;
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      other is AiCapabilityProfile &&
      other.jsonMode == jsonMode &&
      other.limitField == limitField &&
      other.streamOk == streamOk &&
      other.streamUsageOk == streamUsageOk &&
      other.vision == vision;

  @override
  int get hashCode =>
      Object.hash(jsonMode, limitField, streamOk, streamUsageOk, vision);
}

@immutable
final class AiTokenUsage {
  const new({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.reasoningTokens,
    this.providerCost,
  });

  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  final int? reasoningTokens;
  final double? providerCost;

  @override
  bool operator ==(Object other) =>
      other is AiTokenUsage &&
      other.promptTokens == promptTokens &&
      other.completionTokens == completionTokens &&
      other.totalTokens == totalTokens &&
      other.reasoningTokens == reasoningTokens &&
      other.providerCost == providerCost;

  @override
  int get hashCode => Object.hash(
    promptTokens,
    completionTokens,
    totalTokens,
    reasoningTokens,
    providerCost,
  );
}

@immutable
sealed class AnalysisEvent {
  const new();
}

@immutable
final class AnalysisProgress extends AnalysisEvent {
  const new(this.receivedChars);

  final int receivedChars;

  @override
  bool operator ==(Object other) =>
      other is AnalysisProgress && other.receivedChars == receivedChars;

  @override
  int get hashCode => receivedChars.hashCode;
}

@immutable
final class AnalysisCompleted extends AnalysisEvent {
  const new({required this.text, required this.finishReason, this.usage});

  final String text;
  final String finishReason;
  final AiTokenUsage? usage;

  @override
  bool operator ==(Object other) =>
      other is AnalysisCompleted &&
      other.text == text &&
      other.finishReason == finishReason &&
      other.usage == usage;

  @override
  int get hashCode => Object.hash(text, finishReason, usage);
}

enum AnalysisFailureKind {
  unreachable,
  tls,
  cleartextBlocked,
  redirect,
  badRequest,
  unauthorized,
  noCredit,
  forbidden,
  modelNotFound,
  contextTooLong,
  rateLimited,
  serverError,
  timeout,
  emptyAfterLimit,
  refused,
  unreadable,
  cancelled,
}

enum TimeoutStage { connect, firstByte, idle, total }

@immutable
final class AnalysisFailure implements Exception {
  const new({
    required this.kind,
    this.detail = '',
    this.statusCode,
    this.retryAfterSeconds,
    this.timeoutStage,
  });

  final AnalysisFailureKind kind;
  final String detail;
  final int? statusCode;
  final int? retryAfterSeconds;
  final TimeoutStage? timeoutStage;

  @override
  bool operator ==(Object other) =>
      other is AnalysisFailure &&
      other.kind == kind &&
      other.detail == detail &&
      other.statusCode == statusCode &&
      other.retryAfterSeconds == retryAfterSeconds &&
      other.timeoutStage == timeoutStage;

  @override
  int get hashCode =>
      Object.hash(kind, detail, statusCode, retryAfterSeconds, timeoutStage);
}

// Phrases, not bare words: a model id such as "llama-3.2-11b-vision" is
// echoed in unrelated 400s.
const List<String> _imageRefusals = [
  'image input',
  'image_url',
  'image content',
  'images are not supported',
  'does not support image',
  'does not support vision',
  'not a vision model',
  'not multimodal',
  'multimodal input',
];

bool _refusesImage(String lower) => _imageRefusals.any(lower.contains);

/// A 400 to a request with an image part that refuses the image itself, so
/// no wire step down can help.
bool isNoVisionFailure(AnalysisFailure failure, {required bool imageRequest}) =>
    imageRequest &&
    failure.kind == AnalysisFailureKind.badRequest &&
    failure.statusCode == 400 &&
    _refusesImage(failure.detail.toLowerCase());

String scrubApiKey(String text, String? apiKey) {
  final cleaned = _replaceKey(text, apiKey).trim();
  if (cleaned.length <= aiMaxErrorDetailChars) return cleaned;
  return cleaned.substring(0, aiMaxErrorDetailChars);
}

String _replaceKey(String text, String? apiKey) {
  if (apiKey == null || apiKey.isEmpty) return text;
  final replaced = text.replaceAll(apiKey, '[redacted]');
  final trimmed = apiKey.trim();
  if (trimmed.isEmpty || trimmed == apiKey) return replaced;
  return replaced.replaceAll(trimmed, '[redacted]');
}
