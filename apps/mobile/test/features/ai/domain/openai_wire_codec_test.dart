import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/openai_wire_codec.dart';

Stream<List<int>> _sseChunks(List<String> events, {int chunkSize = 0}) async* {
  final full = utf8.encode(events.join());
  if (chunkSize <= 0) {
    yield full;
    return;
  }
  for (var i = 0; i < full.length; i += chunkSize) {
    final end = i + chunkSize > full.length ? full.length : i + chunkSize;
    yield full.sublist(i, end);
  }
}

void main() {
  group('AiUserContent value equality', () {
    test('covers non-identical instances and differing fields', () {
      final txt1 = String.fromCharCodes('hello'.codeUnits);
      final txt2 = String.fromCharCodes('hello'.codeUnits);
      final t1 = AiTextContent(txt1);
      final t2 = AiTextContent(txt2);
      expect(identical(t1, t2), isFalse);
      expect(t1, t2);
      expect(t1.hashCode, t2.hashCode);
      expect(t1, isNot(const AiTextContent('other')));

      final b1 = String.fromCharCodes('abc'.codeUnits);
      final b2 = String.fromCharCodes('abc'.codeUnits);
      final i1 = AiImageContent(text: txt1, base64Jpeg: b1);
      final i2 = AiImageContent(text: txt2, base64Jpeg: b2);
      expect(identical(i1, i2), isFalse);
      expect(i1, i2);
      expect(i1.hashCode, i2.hashCode);
      expect(i1, isNot(AiImageContent(text: 'other', base64Jpeg: b1)));
      expect(i1, isNot(AiImageContent(text: txt1, base64Jpeg: 'xyz')));
    });
  });

  group('OpenAiWireCodec.buildChatBody', () {
    test(
      'uses system role only, forbids sampling params, and honours profile',
      () {
        final body = OpenAiWireCodec.buildChatBody(
          model: 'gpt-5-mini',
          systemPrompt: 'System contract',
          userContent: const AiTextContent('USER_JSON'),
          maxOutputTokens: 4000,
          profile: AiCapabilityProfile.defaults,
          jsonSchema: const {'type': 'object'},
          reasoningEffort: AiReasoningEffort.low,
        );

        expect(body['model'], 'gpt-5-mini');
        expect(body['max_completion_tokens'], 4000);
        expect(body.containsKey('max_tokens'), isFalse);
        expect(body['stream'], isTrue);
        expect(body['stream_options'], const {'include_usage': true});
        expect(body['reasoning_effort'], 'low');

        for (final forbidden in const [
          'temperature',
          'top_p',
          'presence_penalty',
          'frequency_penalty',
          'seed',
          'logprobs',
          'logit_bias',
          'top_logprobs',
          'n',
        ]) {
          expect(body.containsKey(forbidden), isFalse, reason: forbidden);
        }

        final messages = body['messages']! as List<Object?>;
        expect(messages, hasLength(2));
        expect((messages[0]! as Map)['role'], 'system');
        expect((messages[0]! as Map)['content'], 'System contract');
        expect((messages[1]! as Map)['role'], 'user');
        expect((messages[1]! as Map)['content'], 'USER_JSON');

        expect(body['response_format'], const {
          'type': 'json_schema',
          'json_schema': {
            'name': 'openring_report',
            'strict': true,
            'schema': {'type': 'object'},
          },
        });
      },
    );

    test(
      'handles limitField, streamOverride, streamUsageOk, and jsonModes',
      () {
        final noStreamUsage = OpenAiWireCodec.buildChatBody(
          model: 'llama-3',
          systemPrompt: 'Sys',
          userContent: const AiTextContent('U'),
          maxOutputTokens: 1200,
          profile: const AiCapabilityProfile(
            jsonMode: AiJsonMode.jsonObject,
            limitField: AiLimitField.maxTokens,
          ),
          jsonSchema: const {'type': 'object'},
          streamOverride: false,
        );
        expect(noStreamUsage['max_tokens'], 1200);
        expect(noStreamUsage.containsKey('max_completion_tokens'), isFalse);
        expect(noStreamUsage['stream'], isFalse);
        expect(noStreamUsage.containsKey('stream_options'), isFalse);
        expect(noStreamUsage.containsKey('reasoning_effort'), isFalse);
        expect(noStreamUsage['response_format'], const {'type': 'json_object'});

        final usageOff = OpenAiWireCodec.buildChatBody(
          model: 'm',
          systemPrompt: 's',
          userContent: const AiTextContent('u'),
          maxOutputTokens: 512,
          profile: const AiCapabilityProfile(
            streamUsageOk: false,
            jsonMode: AiJsonMode.none,
          ),
          jsonSchema: const {'type': 'object'},
        );
        expect(usageOff['stream'], isTrue);
        expect(usageOff.containsKey('stream_options'), isFalse);
        expect(usageOff.containsKey('response_format'), isFalse);

        final nullSchema = OpenAiWireCodec.buildChatBody(
          model: 'm',
          systemPrompt: 's',
          userContent: const AiTextContent('u'),
          maxOutputTokens: 512,
          profile: AiCapabilityProfile.defaults,
        );
        expect(nullSchema.containsKey('response_format'), isFalse);

        final profileStreamOff = OpenAiWireCodec.buildChatBody(
          model: 'm',
          systemPrompt: 's',
          userContent: const AiTextContent('u'),
          maxOutputTokens: 512,
          profile: const AiCapabilityProfile(streamOk: false),
        );
        expect(profileStreamOff['stream'], isFalse);
        expect(profileStreamOff.containsKey('stream_options'), isFalse);

        final forcedStreamOn = OpenAiWireCodec.buildChatBody(
          model: 'm',
          systemPrompt: 's',
          userContent: const AiTextContent('u'),
          maxOutputTokens: 512,
          profile: const AiCapabilityProfile(streamOk: false),
          streamOverride: true,
        );
        expect(forcedStreamOn['stream'], isTrue);
        expect(forcedStreamOn['stream_options'], const {'include_usage': true});
      },
    );

    test(
      'encodes multimodal image content text-first as JPEG URI with no detail',
      () {
        final body = OpenAiWireCodec.buildChatBody(
          model: 'gpt-5-mini',
          systemPrompt: 'Sys',
          userContent: const AiImageContent(
            text: 'Describe meal',
            base64Jpeg: 'AAAA',
          ),
          maxOutputTokens: 500,
          profile: const AiCapabilityProfile(jsonMode: AiJsonMode.none),
        );
        final messages = body['messages']! as List<Object?>;
        final userContent = (messages[1]! as Map)['content']! as List<Object?>;
        expect(userContent, hasLength(2));
        expect(userContent[0], const {'type': 'text', 'text': 'Describe meal'});
        final imagePart = userContent[1]! as Map<String, Object?>;
        expect(imagePart['type'], 'image_url');
        final imageUrl = imagePart['image_url']! as Map<String, Object?>;
        expect(imageUrl['url'], 'data:image/jpeg;base64,AAAA');
        expect(imageUrl.containsKey('detail'), isFalse);
      },
    );
  });

  group('OpenAiWireCodec.parseModelsList', () {
    test('returns sorted deduplicated IDs and ignores invalid entries', () {
      const json = '''
      {
        "data": [
          {"id": " gpt-5-mini "},
          {"id": "claude-sonnet"},
          {"id": "gpt-5-mini"},
          {"id": ""},
          {"id": 123},
          "bad-entry",
          {"id": "anthropic/claude-haiku"}
        ]
      }
      ''';
      expect(OpenAiWireCodec.parseModelsList(json), [
        'anthropic/claude-haiku',
        'claude-sonnet',
        'gpt-5-mini',
      ]);
    });

    test('throws unreadable on malformed JSON or missing data list', () {
      for (final bad in ['not-json', '{}', '{"data": {}}', '[]']) {
        expect(
          () => OpenAiWireCodec.parseModelsList(bad),
          throwsA(const AnalysisFailure(kind: AnalysisFailureKind.unreadable)),
          reason: bad,
        );
      }
    });
  });

  group('OpenAiWireCodec.stripThinkBlocks', () {
    test('strips closed case-insensitive and trailing unclosed blocks', () {
      expect(
        OpenAiWireCodec.stripThinkBlocks(
          '  <THINK>multi\nline</think>{"ok":true} ',
        ),
        '{"ok":true}',
      );
      expect(
        OpenAiWireCodec.stripThinkBlocks('pre<think>cut off mid thought'),
        'pre',
      );
      expect(OpenAiWireCodec.stripThinkBlocks('<think>cut off only'), isEmpty);
    });
  });

  group('OpenAiWireCodec.parseSseStream', () {
    test(
      'handles split multibyte UTF-8, comments, duplicate finish, and cost',
      () async {
        final events = [
          ': OPENROUTER PROCESSING\n',
          '\n',
          'data: {"choices":[{"delta":{"content":"ação 😀 ","reasoning":"skip"}}]}\n\n',
          'data:{"choices":[{"delta":{"content":"fim"},"finish_reason":"stop"}]}\n\n',
          'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n',
          'data: {"choices":[],"usage":{"prompt_tokens":100,"completion_tokens":20,"total_tokens":120,"completion_tokens_details":{"reasoning_tokens":7},"cost":0.0025}}\n\n',
          'data: [DONE]\n\n',
        ];
        final emitted = await OpenAiWireCodec.parseSseStream(
          _sseChunks(events, chunkSize: 1),
        ).toList();

        expect(emitted, [
          const AnalysisProgress(8),
          const AnalysisProgress(11),
          const AnalysisCompleted(
            text: 'ação 😀 fim',
            finishReason: 'stop',
            usage: AiTokenUsage(
              promptTokens: 100,
              completionTokens: 20,
              totalTokens: 120,
              reasoningTokens: 7,
              providerCost: 0.0025,
            ),
          ),
        ]);
      },
    );

    test('yields null usage when omitted by provider', () async {
      final emitted = await OpenAiWireCodec.parseSseStream(
        _sseChunks([
          'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}\n\n',
          'data: [DONE]\n\n',
        ]),
      ).toList();
      expect(
        emitted.last,
        const AnalysisCompleted(text: 'ok', finishReason: 'stop'),
      );
    });

    test('ignores non-numeric optional usage telemetry in SSE', () async {
      final emitted = await OpenAiWireCodec.parseSseStream(
        _sseChunks([
          'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":"10","completion_tokens":4,"completion_tokens_details":{"reasoning_tokens":"bad"},"cost":"0.001"}}\n\n',
          'data: [DONE]\n\n',
        ]),
      ).toList();
      expect(
        emitted.last,
        const AnalysisCompleted(
          text: 'ok',
          finishReason: 'stop',
          usage: AiTokenUsage(completionTokens: 4),
        ),
      );
    });

    test('maps mid-stream top-level errors under HTTP 200 and scrubs key', () async {
      const secret = 'sk-stream-999';
      await expectLater(
        OpenAiWireCodec.parseSseStream(
          _sseChunks([
            'data: {"error":{"code":429,"type":"insufficient_quota","message":"Quota out for $secret"}}\n\n',
          ]),
          apiKey: secret,
        ).toList(),
        throwsA(
          const AnalysisFailure(
            kind: AnalysisFailureKind.noCredit,
            detail: 'Quota out for [redacted]',
            statusCode: 429,
          ),
        ),
      );

      await expectLater(
        OpenAiWireCodec.parseSseStream(
          _sseChunks([
            'data: {"error":{"code":-1,"message":"Bad key $secret"}}\n\n',
          ]),
          apiKey: secret,
        ).toList(),
        throwsA(
          const AnalysisFailure(
            kind: AnalysisFailureKind.serverError,
            detail: 'Bad key [redacted]',
          ),
        ),
      );

      await expectLater(
        OpenAiWireCodec.parseSseStream(
          _sseChunks([
            'data: {"choices":[{"delta":{},"finish_reason":"error","error":{"message":"boom $secret"}}]}\n\n',
          ]),
          apiKey: secret,
        ).toList(),
        throwsA(
          const AnalysisFailure(
            kind: AnalysisFailureKind.serverError,
            detail: 'boom [redacted]',
          ),
        ),
      );

      await expectLater(
        OpenAiWireCodec.parseSseStream(
          _sseChunks([
            'data: {"choices":[{"delta":{},"finish_reason":"error"}]}\n\n',
          ]),
        ).toList(),
        throwsA(const AnalysisFailure(kind: AnalysisFailureKind.serverError)),
      );
    });

    test('detects refusal, content_filter, and think-only emptyAfterLimit', () async {
      const secret = 'sk-ref-1';
      await expectLater(
        OpenAiWireCodec.parseSseStream(
          _sseChunks([
            'data: {"choices":[{"delta":{"refusal":"Policy $secret"},"finish_reason":"stop"}]}\n\n',
          ]),
          apiKey: secret,
        ).toList(),
        throwsA(
          const AnalysisFailure(
            kind: AnalysisFailureKind.refused,
            detail: 'Policy [redacted]',
          ),
        ),
      );

      await expectLater(
        OpenAiWireCodec.parseSseStream(
          _sseChunks([
            'data: {"choices":[{"delta":{"content":"partial"},"finish_reason":"content_filter"}]}\n\n',
          ]),
        ).toList(),
        throwsA(const AnalysisFailure(kind: AnalysisFailureKind.refused)),
      );

      for (final thinkPayload in [
        '<think>closed reasoning</think>',
        '<think>unclosed reasoning at limit',
      ]) {
        await expectLater(
          OpenAiWireCodec.parseSseStream(
            _sseChunks([
              'data: {"choices":[{"delta":{"content":"$thinkPayload"},"finish_reason":"length"}]}\n\n',
              'data: [DONE]\n\n',
            ]),
          ).toList(),
          throwsA(
            const AnalysisFailure(kind: AnalysisFailureKind.emptyAfterLimit),
          ),
          reason: thinkPayload,
        );
      }
    });

    test('throws unreadable for DONE-only, empty, corrupt JSON, invalid UTF-8, and >maxBytes', () async {
      await expectLater(
        OpenAiWireCodec.parseSseStream(_sseChunks(['data: [DONE]\n\n']))
            .toList(),
        throwsA(const AnalysisFailure(kind: AnalysisFailureKind.unreadable)),
      );

      await expectLater(
        OpenAiWireCodec.parseSseStream(const Stream.empty()).toList(),
        throwsA(const AnalysisFailure(kind: AnalysisFailureKind.unreadable)),
      );

      await expectLater(
        OpenAiWireCodec.parseSseStream(_sseChunks(['data: {bad\n\n'])).toList(),
        throwsA(const AnalysisFailure(kind: AnalysisFailureKind.unreadable)),
      );

      await expectLater(
        OpenAiWireCodec.parseSseStream(
          Stream.fromIterable([
            [0xFF, 0xFE, 0xFD],
          ]),
        ).toList(),
        throwsA(const AnalysisFailure(kind: AnalysisFailureKind.unreadable)),
      );

      await expectLater(
        OpenAiWireCodec.parseSseStream(
          _sseChunks([
            'data: {"choices":[{"delta":{"content":"too big across chunks"}}]}\n\n',
          ], chunkSize: 8),
          maxBytes: 16,
        ).toList(),
        throwsA(const AnalysisFailure(kind: AnalysisFailureKind.unreadable)),
      );
    });
  });

  group('OpenAiWireCodec.parseJsonResponse', () {
    test(
      'parses valid response, strips think blocks, and handles wrong types',
      () {
        const json = r'''
      {
        "choices": [{
          "finish_reason": "stop",
          "message": {"content": "<think>plan</think>{\"cards\":[]}", "refusal": null}
        }],
        "usage": {
          "prompt_tokens": 50,
          "completion_tokens": 10,
          "total_tokens": 60,
          "completion_tokens_details": {"reasoning_tokens": 4},
          "cost": 0.001
        }
      }
      ''';
        final result = OpenAiWireCodec.parseJsonResponse(json);
        expect(
          result,
          const AnalysisCompleted(
            text: '{"cards":[]}',
            finishReason: 'stop',
            usage: AiTokenUsage(
              promptTokens: 50,
              completionTokens: 10,
              totalTokens: 60,
              reasoningTokens: 4,
              providerCost: 0.001,
            ),
          ),
        );

        // Unexpected field types (including stringified usage) do not throw TypeError.
        final weird = OpenAiWireCodec.parseJsonResponse(
          '{"choices":[{"finish_reason":42,"message":{"content":false,"refusal":9}}],"usage":{"prompt_tokens":10,"cost":"0.001","completion_tokens_details":{"reasoning_tokens":"x"}}}',
        );
        expect(
          weird,
          const AnalysisCompleted(
            text: '',
            finishReason: '',
            usage: AiTokenUsage(promptTokens: 10),
          ),
        );
      },
    );

    test('handles size limit, malformed shapes, errors, refusal, and emptyAfterLimit', () {
      const utf8BoundaryJson =
          '{"choices":[{"finish_reason":"stop","message":{"content":"ção"}}]}';
      expect(
        () => OpenAiWireCodec.parseJsonResponse(
          utf8BoundaryJson,
          maxBytes: utf8BoundaryJson.length + 1,
        ),
        throwsA(const AnalysisFailure(kind: AnalysisFailureKind.unreadable)),
      );
      expect(
        OpenAiWireCodec.parseJsonResponse(
          utf8BoundaryJson,
          maxBytes: utf8.encode(utf8BoundaryJson).length,
        ),
        const AnalysisCompleted(text: 'ção', finishReason: 'stop'),
      );
      for (final bad in [
        'not-json',
        '{"choices":[]}',
        '{"choices":[123]}',
        '{"choices":[{"finish_reason":"stop"}]}',
      ]) {
        expect(
          () => OpenAiWireCodec.parseJsonResponse(bad),
          throwsA(const AnalysisFailure(kind: AnalysisFailureKind.unreadable)),
          reason: bad,
        );
      }

      const secret = 'sk-json-5';
      expect(
        () => OpenAiWireCodec.parseJsonResponse(
          '{"error":{"code":502,"message":"Upstream $secret"}}',
          apiKey: secret,
        ),
        throwsA(
          const AnalysisFailure(
            kind: AnalysisFailureKind.serverError,
            detail: 'Upstream [redacted]',
            statusCode: 502,
          ),
        ),
      );
      expect(
        () => OpenAiWireCodec.parseJsonResponse(
          '{"choices":[{"finish_reason":"error","message":{},"error":{"type":"crash"}}]}',
        ),
        throwsA(
          const AnalysisFailure(
            kind: AnalysisFailureKind.serverError,
            detail: 'crash',
          ),
        ),
      );
      expect(
        () => OpenAiWireCodec.parseJsonResponse(
          '{"choices":[{"finish_reason":"stop","message":{"refusal":"No $secret"}}]}',
          apiKey: secret,
        ),
        throwsA(
          const AnalysisFailure(
            kind: AnalysisFailureKind.refused,
            detail: 'No [redacted]',
          ),
        ),
      );
      expect(
        () => OpenAiWireCodec.parseJsonResponse(
          '{"choices":[{"finish_reason":"length","message":{"content":"<think>cut"}}]}',
        ),
        throwsA(
          const AnalysisFailure(kind: AnalysisFailureKind.emptyAfterLimit),
        ),
      );
    });
  });

  group('OpenAiWireCodec.classifyHttpError', () {
    test('classifies status codes, context/quota overrides, Retry-After, and scrubbing', () {
      const secret = 'sk-http-key';
      expect(
        OpenAiWireCodec.classifyHttpError(statusCode: 302, body: 'moved'),
        const AnalysisFailure(
          kind: AnalysisFailureKind.redirect,
          detail: 'moved',
          statusCode: 302,
        ),
      );
      expect(
        OpenAiWireCodec.classifyHttpError(
          statusCode: 400,
          body: '{"error":{"message":"invalid model $secret"}}',
          apiKey: secret,
        ),
        const AnalysisFailure(
          kind: AnalysisFailureKind.badRequest,
          detail: 'invalid model [redacted]',
          statusCode: 400,
        ),
      );
      expect(
        OpenAiWireCodec.classifyHttpError(
          statusCode: 400,
          body: 'exceeded maximum context length',
        ).kind,
        AnalysisFailureKind.contextTooLong,
      );
      expect(
        OpenAiWireCodec.classifyHttpError(statusCode: 401, body: '').kind,
        AnalysisFailureKind.unauthorized,
      );
      expect(
        OpenAiWireCodec.classifyHttpError(statusCode: 402, body: '').kind,
        AnalysisFailureKind.noCredit,
      );
      expect(
        OpenAiWireCodec.classifyHttpError(statusCode: 403, body: '').kind,
        AnalysisFailureKind.forbidden,
      );
      expect(
        OpenAiWireCodec.classifyHttpError(statusCode: 404, body: '').kind,
        AnalysisFailureKind.modelNotFound,
      );
      expect(
        OpenAiWireCodec.classifyHttpError(statusCode: 413, body: '').kind,
        AnalysisFailureKind.contextTooLong,
      );
      expect(
        OpenAiWireCodec.classifyHttpError(
          statusCode: 429,
          body: 'slow down',
          headers: const {'Retry-After': '15'},
        ),
        const AnalysisFailure(
          kind: AnalysisFailureKind.rateLimited,
          detail: 'slow down',
          statusCode: 429,
          retryAfterSeconds: 15,
        ),
      );
      expect(
        OpenAiWireCodec.classifyHttpError(
          statusCode: 429,
          body: 'slow down',
          headers: const {'retry-after': '-5'},
        ).retryAfterSeconds,
        isNull,
      );
      expect(
        OpenAiWireCodec.classifyHttpError(
          statusCode: 429,
          body: 'slow down',
          headers: const {'retry-after': 'abc'},
        ).retryAfterSeconds,
        isNull,
      );
      expect(
        OpenAiWireCodec.classifyHttpError(
          statusCode: 429,
          body: '{"error":{"message":"Insufficient quota"}}',
          headers: const {'retry-after': '30'},
        ),
        const AnalysisFailure(
          kind: AnalysisFailureKind.noCredit,
          detail: 'Insufficient quota',
          statusCode: 429,
        ),
      );
      expect(
        OpenAiWireCodec.classifyHttpError(statusCode: 503, body: 'down').kind,
        AnalysisFailureKind.serverError,
      );
      expect(
        OpenAiWireCodec.classifyHttpError(
          statusCode: 400,
          body: '{"object":"error","message":"Unknown field: max_completion_tokens"}',
        ),
        const AnalysisFailure(
          kind: AnalysisFailureKind.badRequest,
          detail: 'Unknown field: max_completion_tokens',
          statusCode: 400,
        ),
      );
      expect(
        OpenAiWireCodec.classifyHttpError(
          statusCode: 400,
          body: '{"detail":"Unknown field: stream_options"}',
        ),
        const AnalysisFailure(
          kind: AnalysisFailureKind.badRequest,
          detail: 'Unknown field: stream_options',
          statusCode: 400,
        ),
      );
      expect(
        OpenAiWireCodec.classifyHttpError(
          statusCode: 400,
          body: '{"detail":[{"msg":"stream_options unsupported"}]}',
        ).detail,
        contains('stream_options unsupported'),
      );
      expect(
        OpenAiWireCodec.classifyHttpError(statusCode: 418, body: 'teapot').kind,
        AnalysisFailureKind.badRequest,
      );

      final longDetail = OpenAiWireCodec.classifyHttpError(
        statusCode: 500,
        body: '${'x' * 290}$secret${'y' * 50}',
        apiKey: secret,
      ).detail;
      expect(longDetail.length, aiMaxErrorDetailChars);
      expect(longDetail, '${'x' * 290}[redacted]');
      expect(longDetail, isNot(contains('sk-')));
    });
  });
}
