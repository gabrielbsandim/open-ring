import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';

@immutable
sealed class AiUserContent {
  const new();
}

@immutable
final class AiTextContent extends AiUserContent {
  const new(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      other is AiTextContent && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

@immutable
final class AiImageContent extends AiUserContent {
  const new({required this.text, required this.base64Jpeg});

  final String text;
  final String base64Jpeg;

  @override
  bool operator ==(Object other) =>
      other is AiImageContent &&
      other.text == text &&
      other.base64Jpeg == base64Jpeg;

  @override
  int get hashCode => Object.hash(text, base64Jpeg);
}

abstract final class OpenAiWireCodec {
  static final _thinkPattern = RegExp(
    r'<think>[\s\S]*?</think>',
    caseSensitive: false,
  );
  static final _unclosedThinkPattern = RegExp(
    r'<think>[\s\S]*$',
    caseSensitive: false,
  );
  static const _contextKeywords = [
    'context_length',
    'maximum context',
    'too long',
    'token limit',
    'context window',
  ];
  static const _quotaKeywords = ['quota', 'billing', 'credit', 'insufficient'];

  static Map<String, Object?> buildChatBody({
    required String model,
    required String systemPrompt,
    required AiUserContent userContent,
    required int maxOutputTokens,
    required AiCapabilityProfile profile,
    Map<String, Object?>? jsonSchema,
    String schemaName = 'openring_report',
    AiReasoningEffort? reasoningEffort,
    bool? streamOverride,
  }) {
    final stream = streamOverride ?? profile.streamOk;
    final limitKey = switch (profile.limitField) {
      AiLimitField.maxCompletionTokens => 'max_completion_tokens',
      AiLimitField.maxTokens => 'max_tokens',
    };
    final body = <String, Object?>{
      'model': model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': _encodeUserContent(userContent)},
      ],
      limitKey: maxOutputTokens,
      'stream': stream,
    };
    if (stream && profile.streamUsageOk) {
      body['stream_options'] = const {'include_usage': true};
    }
    if (reasoningEffort != null) {
      body['reasoning_effort'] = reasoningEffort.name;
    }
    final format = _responseFormat(profile.jsonMode, jsonSchema, schemaName);
    if (format != null) body['response_format'] = format;
    return body;
  }

  static List<String> parseModelsList(String body) {
    final decoded = _decodeJsonMap(body);
    final rawList = decoded?['data'];
    if (rawList is! List<Object?>) {
      throw const AnalysisFailure(kind: AnalysisFailureKind.unreadable);
    }
    final ids = <String>{};
    for (final entry in rawList) {
      if (entry is! Map<String, Object?>) continue;
      final rawId = entry['id'];
      if (rawId is! String) continue;
      final id = rawId.trim();
      if (id.isNotEmpty) ids.add(id);
    }
    final sorted = ids.toList()..sort();
    return sorted;
  }

  static String stripThinkBlocks(String text) => text
      .replaceAll(_thinkPattern, '')
      .replaceAll(_unclosedThinkPattern, '')
      .trim();

  static Stream<AnalysisEvent> parseSseStream(
    Stream<List<int>> bytes, {
    int maxBytes = aiMaxResponseBytes,
    String? apiKey,
  }) async* {
    final limited = _limitBytes(bytes, maxBytes: maxBytes);
    final lines = utf8.decoder.bind(limited).transform(const LineSplitter());
    final state = _SseAccumulator(apiKey: apiKey);
    try {
      await for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith(':')) continue;
        if (!trimmed.startsWith('data:')) continue;
        final payload = trimmed.substring(5).trim();
        if (payload == '[DONE]') break;
        final progress = state.consumeJson(payload);
        if (progress != null) yield progress;
      }
    } on FormatException {
      throw const AnalysisFailure(kind: AnalysisFailureKind.unreadable);
    }
    yield state.finish();
  }

  static AnalysisCompleted parseJsonResponse(
    String body, {
    int maxBytes = aiMaxResponseBytes,
    String? apiKey,
  }) {
    if (utf8.encode(body).length > maxBytes) {
      throw const AnalysisFailure(kind: AnalysisFailureKind.unreadable);
    }
    final map = _decodeJsonMap(body);
    if (map == null) {
      throw const AnalysisFailure(kind: AnalysisFailureKind.unreadable);
    }
    _throwIfTopLevelError(map, apiKey: apiKey);
    final choices = map['choices'];
    if (choices is! List<Object?> || choices.isEmpty) {
      throw const AnalysisFailure(kind: AnalysisFailureKind.unreadable);
    }
    final first = choices.first;
    if (first is! Map<String, Object?>) {
      throw const AnalysisFailure(kind: AnalysisFailureKind.unreadable);
    }
    final rawReason = first['finish_reason'];
    final finishReason = rawReason is String ? rawReason : '';
    if (finishReason == 'error') {
      final errDetail = _extractErrorDetail(
        first['error'] != null ? first : map,
      );
      throw AnalysisFailure(
        kind: AnalysisFailureKind.serverError,
        detail: scrubApiKey(errDetail, apiKey),
      );
    }
    final message = first['message'];
    if (message is! Map<String, Object?>) {
      throw const AnalysisFailure(kind: AnalysisFailureKind.unreadable);
    }
    final rawRefusal = message['refusal'];
    final refusal = rawRefusal is String ? rawRefusal : '';
    if (refusal.isNotEmpty || finishReason == 'content_filter') {
      throw AnalysisFailure(
        kind: AnalysisFailureKind.refused,
        detail: scrubApiKey(refusal, apiKey),
      );
    }
    final rawContent = message['content'];
    final text = stripThinkBlocks(rawContent is String ? rawContent : '');
    if (text.isEmpty && finishReason == 'length') {
      throw const AnalysisFailure(kind: AnalysisFailureKind.emptyAfterLimit);
    }
    return AnalysisCompleted(
      text: text,
      finishReason: finishReason,
      usage: _extractUsage(map['usage']),
    );
  }

  static AnalysisFailure classifyHttpError({
    required int statusCode,
    required String body,
    Map<String, String> headers = const {},
    String? apiKey,
  }) {
    final detail = scrubApiKey(_extractErrorDetailFromBody(body), apiKey);
    if (statusCode >= 300 && statusCode < 400) {
      return AnalysisFailure(
        kind: AnalysisFailureKind.redirect,
        detail: detail,
        statusCode: statusCode,
      );
    }
    final lower = '${detail.toLowerCase()} ${body.toLowerCase()}';
    final kind = switch (statusCode) {
      400 =>
        _containsAny(lower, _contextKeywords)
            ? AnalysisFailureKind.contextTooLong
            : AnalysisFailureKind.badRequest,
      401 => AnalysisFailureKind.unauthorized,
      402 => AnalysisFailureKind.noCredit,
      403 => AnalysisFailureKind.forbidden,
      404 => AnalysisFailureKind.modelNotFound,
      413 => AnalysisFailureKind.contextTooLong,
      429 =>
        _containsAny(lower, _quotaKeywords)
            ? AnalysisFailureKind.noCredit
            : AnalysisFailureKind.rateLimited,
      >= 500 && <= 599 => AnalysisFailureKind.serverError,
      _ => AnalysisFailureKind.badRequest,
    };
    return AnalysisFailure(
      kind: kind,
      detail: detail,
      statusCode: statusCode,
      retryAfterSeconds: kind == AnalysisFailureKind.rateLimited
          ? _parseRetryAfter(headers)
          : null,
    );
  }

  static Object _encodeUserContent(AiUserContent content) => switch (content) {
    AiTextContent(:final text) => text,
    AiImageContent(:final text, :final base64Jpeg) => [
      {'type': 'text', 'text': text},
      {
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,$base64Jpeg'},
      },
    ],
  };

  static Map<String, Object?>? _responseFormat(
    AiJsonMode mode,
    Map<String, Object?>? schema,
    String schemaName,
  ) => switch (mode) {
    AiJsonMode.jsonSchema =>
      schema == null
          ? null
          : {
              'type': 'json_schema',
              'json_schema': {
                'name': schemaName,
                'strict': true,
                'schema': schema,
              },
            },
    AiJsonMode.jsonObject => const {'type': 'json_object'},
    AiJsonMode.none => null,
  };

  static Stream<List<int>> _limitBytes(
    Stream<List<int>> bytes, {
    required int maxBytes,
  }) async* {
    var total = 0;
    await for (final chunk in bytes) {
      total += chunk.length;
      if (total > maxBytes) {
        throw const AnalysisFailure(kind: AnalysisFailureKind.unreadable);
      }
      yield chunk;
    }
  }

  static Map<String, Object?>? _decodeJsonMap(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static void _throwIfTopLevelError(
    Map<String, Object?> map, {
    String? apiKey,
  }) {
    final error = map['error'];
    if (error == null) return;
    final code = error is Map<String, Object?> ? error['code'] : null;
    if (code is int && code >= 300 && code <= 599) {
      throw classifyHttpError(
        statusCode: code,
        body: jsonEncode(map),
        apiKey: apiKey,
      );
    }
    throw AnalysisFailure(
      kind: AnalysisFailureKind.serverError,
      detail: scrubApiKey(_extractErrorDetail(map), apiKey),
    );
  }

  static String _extractErrorDetailFromBody(String body) {
    final map = _decodeJsonMap(body);
    if (map != null) return _extractErrorDetail(map);
    return body;
  }

  static String _extractErrorDetail(Map<String, Object?> map) {
    final error = map['error'];
    if (error is String) return error;
    if (error is! Map<String, Object?>) return '';
    final message = error['message'];
    if (message is String && message.isNotEmpty) return message;
    final type = error['type'];
    return type is String ? type : '';
  }

  static AiTokenUsage? _extractUsage(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final details = raw['completion_tokens_details'];
    final reasoning = details is Map<String, Object?>
        ? (details['reasoning_tokens'] as num?)?.toInt()
        : null;
    return AiTokenUsage(
      promptTokens: (raw['prompt_tokens'] as num?)?.toInt(),
      completionTokens: (raw['completion_tokens'] as num?)?.toInt(),
      totalTokens: (raw['total_tokens'] as num?)?.toInt(),
      reasoningTokens: reasoning,
      providerCost: (raw['cost'] as num?)?.toDouble(),
    );
  }

  static int? _parseRetryAfter(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() != 'retry-after') continue;
      final seconds = int.tryParse(entry.value.trim());
      return seconds != null && seconds >= 0 ? seconds : null;
    }
    return null;
  }

  static bool _containsAny(String haystack, List<String> needles) {
    for (final needle in needles) {
      if (haystack.contains(needle)) return true;
    }
    return false;
  }
}

final class _SseAccumulator {
  new({this.apiKey});

  final String? apiKey;
  final StringBuffer _content = StringBuffer();
  final StringBuffer _refusal = StringBuffer();
  String _finishReason = '';
  AiTokenUsage? _usage;
  bool sawEvent = false;

  AnalysisProgress? consumeJson(String payload) {
    final map = OpenAiWireCodec._decodeJsonMap(payload);
    if (map == null) {
      throw const AnalysisFailure(kind: AnalysisFailureKind.unreadable);
    }
    sawEvent = true;
    OpenAiWireCodec._throwIfTopLevelError(map, apiKey: apiKey);
    final usage = OpenAiWireCodec._extractUsage(map['usage']);
    if (usage != null) _usage = usage;
    final choices = map['choices'];
    if (choices is! List<Object?> || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map<String, Object?>) return null;
    final reason = first['finish_reason'];
    if (reason is String && reason.isNotEmpty) _finishReason = reason;
    if (_finishReason == 'error') {
      final errDetail = OpenAiWireCodec._extractErrorDetail(
        first['error'] != null ? first : map,
      );
      throw AnalysisFailure(
        kind: AnalysisFailureKind.serverError,
        detail: scrubApiKey(errDetail, apiKey),
      );
    }
    final delta = first['delta'];
    if (delta is! Map<String, Object?>) return null;
    final refusal = delta['refusal'];
    if (refusal is String && refusal.isNotEmpty) _refusal.write(refusal);
    final piece = delta['content'];
    if (piece is String && piece.isNotEmpty) {
      _content.write(piece);
      return AnalysisProgress(_content.length);
    }
    return null;
  }

  AnalysisCompleted finish() {
    if (!sawEvent) {
      throw const AnalysisFailure(kind: AnalysisFailureKind.unreadable);
    }
    if (_refusal.isNotEmpty || _finishReason == 'content_filter') {
      throw AnalysisFailure(
        kind: AnalysisFailureKind.refused,
        detail: scrubApiKey(_refusal.toString(), apiKey),
      );
    }
    final text = OpenAiWireCodec.stripThinkBlocks(_content.toString());
    if (text.isEmpty && _finishReason == 'length') {
      throw const AnalysisFailure(kind: AnalysisFailureKind.emptyAfterLimit);
    }
    return AnalysisCompleted(
      text: text,
      finishReason: _finishReason,
      usage: _usage,
    );
  }
}
