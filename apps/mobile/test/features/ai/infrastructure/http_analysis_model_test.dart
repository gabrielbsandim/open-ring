import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/base_url_policy.dart';
import 'package:open_ring/features/ai/domain/openai_wire_codec.dart';
import 'package:open_ring/features/ai/infrastructure/http_analysis_model.dart';

import '../../../helpers/ai_fakes.dart';

const _key = 'sk-test-secret-key-123456';

NormalizedBaseUrl _url(String raw) => switch (BaseUrlPolicy.parse(raw)) {
  BaseUrlOk(:final url) => url,
  BaseUrlRejected(:final reason) => throw StateError('$reason'),
};

final class _Recorded {
  new(this.request, this.body);

  final http.BaseRequest request;
  final String body;

  Map<String, Object?> get json => jsonDecode(body) as Map<String, Object?>;
}

typedef _Responder = Future<http.StreamedResponse> Function(_Recorded call);

final class _Harness {
  new(
    this.responder, {
    String url = 'https://api.example.com/v1',
    this.lookup,
    bool local = false,
  }) {
    store = InMemoryAiConfigStore();
    model = HttpAnalysisModel(
      baseUrl: _url(url),
      model: 'model-x',
      apiKey: _key,
      local: local,
      profileStore: store,
      lookup: lookup ?? (_) async => ['192.168.1.20'],
      clientFactory: (_, ip) {
        pinnedIps.add(ip);
        return MockClient.streaming((request, bodyStream) async {
          final call = _Recorded(request, await bodyStream.bytesToString());
          calls.add(call);
          return await responder(call);
        });
      },
    );
  }

  final _Responder responder;
  final AddressLookup? lookup;
  final List<_Recorded> calls = [];
  final List<String?> pinnedIps = [];
  late final InMemoryAiConfigStore store;
  late final HttpAnalysisModel model;

  Future<List<AnalysisEvent>> run({Future<void>? cancel}) => model
      .generate(_request, cancel: cancel ?? Completer<void>().future)
      .toList();
}

const _request = AnalysisRequest(
  systemPrompt: 'system',
  userContent: AiTextContent('user'),
  maxOutputTokens: 1000,
  jsonSchema: {'type': 'object'},
);

http.StreamedResponse _json(
  int status,
  Object body, {
  Map<String, String> headers = const {},
}) => http.StreamedResponse(
  Stream.value(utf8.encode(body is String ? body : jsonEncode(body))),
  status,
  headers: {'content-type': 'application/json', ...headers},
);

http.StreamedResponse _sse(List<Map<String, Object?>> chunks) =>
    http.StreamedResponse(
      Stream.fromIterable([
        for (final c in chunks) utf8.encode('data: ${jsonEncode(c)}\n\n'),
        utf8.encode('data: [DONE]\n\n'),
      ]),
      200,
      headers: {'content-type': 'text/event-stream'},
    );

Map<String, Object?> _delta(String text) => {
  'choices': [
    {
      'delta': {'content': text},
    },
  ],
};

final List<Map<String, Object?>> _okStream = [
  _delta('{"ok":'),
  _delta('true}'),
  {
    'choices': [
      {'delta': <String, Object?>{}, 'finish_reason': 'stop'},
    ],
  },
  {
    'choices': <Object?>[],
    'usage': {'prompt_tokens': 10, 'completion_tokens': 4, 'total_tokens': 14},
  },
];

Map<String, Object?> _error(String message) => {
  'error': {'message': message},
};

Future<AnalysisFailure> _failureOf(Future<Object?> future) async {
  try {
    await future;
  } on AnalysisFailure catch (failure) {
    return failure;
  }
  fail('expected an AnalysisFailure');
}

void main() {
  group('generate', () {
    test('streams progress and completes with usage', () async {
      final h = _Harness((_) async => _sse(_okStream));

      final events = await h.run();

      expect(events.whereType<AnalysisProgress>(), hasLength(2));
      final done = events.last as AnalysisCompleted;
      expect(done.text, '{"ok":true}');
      expect(done.finishReason, 'stop');
      expect(done.usage?.totalTokens, 14);
      final request = h.calls.single.request;
      expect(
        request.url.toString(),
        'https://api.example.com/v1/chat/completions',
      );
      expect(request.followRedirects, isFalse);
      expect(request.headers['user-agent'], 'OpenRing');
      expect(request.headers['authorization'], 'Bearer $_key');
      expect(
        request.headers.keys.map((k) => k.toLowerCase()),
        isNot(anyOf(contains('http-referer'), contains('x-openrouter-title'))),
      );
      expect(h.calls.single.json['stream_options'], {'include_usage': true});
      expect(h.pinnedIps.single, isNull);
    });

    test('parses a non-streaming JSON answer', () async {
      final h = _Harness(
        (_) async => _json(200, {
          'choices': [
            {
              'message': {'content': 'hello'},
              'finish_reason': 'stop',
            },
          ],
          'usage': {'prompt_tokens': 3, 'completion_tokens': 1},
        }),
      );

      final events = await h.run();

      final done = events.single as AnalysisCompleted;
      expect(done.text, 'hello');
      expect(done.usage?.promptTokens, 3);
    });

    test(
      '400 naming stream_options steps down and stores the profile',
      () async {
        final h = _Harness((call) async {
          if (call.json.containsKey('stream_options')) {
            return _json(400, _error('Unknown parameter: stream_options'));
          }
          return _sse(_okStream);
        });

        final events = await h.run();

        expect(events.last, isA<AnalysisCompleted>());
        expect(h.calls, hasLength(2));
        expect(h.calls.last.json.containsKey('stream_options'), isFalse);
        expect(h.store.profiles.values.single.streamUsageOk, isFalse);
      },
    );

    test('400 naming max_completion_tokens switches to max_tokens', () async {
      final h = _Harness((call) async {
        if (call.json.containsKey('max_completion_tokens')) {
          return _json(400, _error('max_completion_tokens is not supported'));
        }
        return _sse(_okStream);
      });

      await h.run();

      expect(h.calls.last.json['max_tokens'], 1000);
    });

    test('400 stops after 4 attempts with badRequest', () async {
      final h = _Harness((_) async => _json(400, _error('nope')));

      final failure = await _failureOf(h.run());

      expect(failure.kind, AnalysisFailureKind.badRequest);
      expect(h.calls, hasLength(4));
    });

    final statusCases = <int, AnalysisFailureKind>{
      401: AnalysisFailureKind.unauthorized,
      402: AnalysisFailureKind.noCredit,
      403: AnalysisFailureKind.forbidden,
      404: AnalysisFailureKind.modelNotFound,
      413: AnalysisFailureKind.contextTooLong,
      429: AnalysisFailureKind.rateLimited,
      500: AnalysisFailureKind.serverError,
      503: AnalysisFailureKind.serverError,
      302: AnalysisFailureKind.redirect,
    };
    for (final entry in statusCases.entries) {
      test('HTTP ${entry.key} maps to ${entry.value.name}', () async {
        final h = _Harness(
          (_) async => _json(
            entry.key,
            _error('status ${entry.key}'),
            headers: {'retry-after': '7', 'location': 'https://evil.example'},
          ),
        );

        final failure = await _failureOf(h.run());

        expect(failure.kind, entry.value);
        expect(failure.statusCode, entry.key);
        expect(h.calls, hasLength(1));
        if (entry.key == 429) expect(failure.retryAfterSeconds, 7);
      });
    }

    test('error detail is scrubbed of the key and capped', () async {
      final h = _Harness(
        (_) async => _json(401, _error('bad key $_key ${'x' * 400}')),
      );

      final failure = await _failureOf(h.run());

      expect(failure.detail, isNot(contains(_key)));
      expect(failure.detail, contains('[redacted]'));
      expect(failure.detail.length, lessThanOrEqualTo(aiMaxErrorDetailChars));
    });

    test('a body past 256 KB fails as unreadable', () async {
      final h = _Harness(
        (_) async => http.StreamedResponse(
          Stream.fromIterable(
            List.generate(5, (_) => List<int>.filled(64 * 1024, 0x20)),
          ),
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      );

      final failure = await _failureOf(h.run());

      expect(failure.kind, AnalysisFailureKind.unreadable);
    });

    test('cancel aborts a stream in progress', () async {
      final body = StreamController<List<int>>();
      final cancel = Completer<void>();
      final h = _Harness(
        (_) async => http.StreamedResponse(
          body.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      );
      final events = <AnalysisEvent>[];
      final error = Completer<Object>();
      h.model
          .generate(_request, cancel: cancel.future)
          .listen(events.add, onError: error.complete);

      body.add(utf8.encode('data: ${jsonEncode(_delta('hi'))}\n\n'));
      await pumpEventQueue();
      cancel.complete();

      final failure = await error.future;
      expect(events.single, const AnalysisProgress(2));
      expect(failure, isA<AnalysisFailure>());
      expect((failure as AnalysisFailure).kind, AnalysisFailureKind.cancelled);
      await body.close();
    });

    test('cancel aborts while waiting for the response headers', () async {
      final cancel = Completer<void>();
      final h = _Harness((_) => Completer<http.StreamedResponse>().future);

      final pending = _failureOf(h.run(cancel: cancel.future));
      await pumpEventQueue();
      cancel.complete();

      expect((await pending).kind, AnalysisFailureKind.cancelled);
    });

    test('no first byte within 60 s times out at that stage', () {
      fakeAsync((async) {
        final h = _Harness((_) => Completer<http.StreamedResponse>().future);
        AnalysisFailure? failure;
        unawaited(_failureOf(h.run()).then((f) => failure = f));

        async.elapse(const Duration(seconds: 59));
        expect(failure, isNull);
        async.elapse(const Duration(seconds: 2));

        expect(failure?.kind, AnalysisFailureKind.timeout);
        expect(failure?.timeoutStage, TimeoutStage.firstByte);
      });
    });

    // The async* cancel path awaits a root zone future, so the error lands
    // only after real microtasks run; hence FakeAsync driven by hand.
    test('silence between chunks times out as idle', () async {
      final async = FakeAsync();
      final body = StreamController<List<int>>();
      AnalysisFailure? failure;
      async.run((_) {
        final h = _Harness(
          (_) async => http.StreamedResponse(
            body.stream,
            200,
            headers: {'content-type': 'text/event-stream'},
          ),
          url: 'http://192.168.1.20:11434/v1',
          local: true,
        );
        unawaited(_failureOf(h.run()).then((f) => failure = f));
      });
      Future<void> settle() async {
        for (var i = 0; i < 5; i++) {
          async.flushMicrotasks();
          await pumpEventQueue();
        }
      }

      await settle();
      body.add(utf8.encode('data: ${jsonEncode(_delta('a'))}\n\n'));
      await settle();
      async.elapse(const Duration(seconds: 119));
      await settle();
      expect(failure, isNull);
      async.elapse(const Duration(seconds: 2));
      await settle();

      expect(failure?.kind, AnalysisFailureKind.timeout);
      expect(failure?.timeoutStage, TimeoutStage.idle);
      expect(failure?.detail, '120');
    });
  });

  group('cleartext policy', () {
    test(
      'http to a public literal address is rejected before sending',
      () async {
        var sent = 0;
        final model = HttpAnalysisModel(
          baseUrl: NormalizedBaseUrl(
            uri: Uri.parse('http://8.8.8.8/v1'),
            asciiHost: '8.8.8.8',
            hasNonAsciiHost: false,
            port: 80,
          ),
          model: 'm',
          lookup: (host) async => [host],
          clientFactory: (_, _) => MockClient((_) async {
            sent++;
            return http.Response('', 200);
          }),
        );

        final failure = await _failureOf(
          model.generate(_request, cancel: Completer<void>().future).toList(),
        );

        expect(failure.kind, AnalysisFailureKind.cleartextBlocked);
        expect(sent, 0);
      },
    );

    test('http host with any public DNS answer is rejected', () async {
      final h = _Harness(
        (_) async => _sse(_okStream),
        url: 'http://gpu-box.local:11434/v1',
        lookup: (_) async => ['192.168.1.20', '93.184.216.34'],
      );

      final failure = await _failureOf(h.run());

      expect(failure.kind, AnalysisFailureKind.cleartextBlocked);
      expect(h.calls, isEmpty);
    });

    test(
      'http host on a private address connects to the checked address',
      () async {
        final h = _Harness(
          (_) async => _sse(_okStream),
          url: 'http://gpu-box.local:11434/v1',
          lookup: (_) async => ['192.168.1.20'],
        );

        await h.run();

        expect(h.pinnedIps.single, '192.168.1.20');
      },
    );
  });

  group('listModels', () {
    test('reads data ids from the models endpoint', () async {
      final h = _Harness(
        (_) async => _json(200, {
          'data': [
            {'id': 'b'},
            {'id': 'a'},
          ],
        }),
      );

      expect(await h.model.listModels(), ['a', 'b']);
      expect(h.calls.single.request.method, 'GET');
      expect(h.calls.single.request.url.query, 'limit=1000');
    });
  });

  group('probe', () {
    test('ladder finds the step and stores the profile', () async {
      final h = _Harness((call) async {
        if (call.request.method == 'GET') {
          return _json(200, {
            'data': [
              {'id': 'model-x'},
            ],
          });
        }
        final format = call.json['response_format']! as Map<String, Object?>;
        if (format['type'] == 'json_schema') {
          return _json(
            400,
            _error('response_format json_schema is not supported'),
          );
        }
        return _sse(_okStream);
      });

      final result = await h.model.probe();

      expect(result.profile.jsonMode, AiJsonMode.jsonObject);
      expect(result.models, ['model-x']);
      expect(result.usage?.totalTokens, 14);
      expect(h.calls, hasLength(3));
      final stored = await h.store.readCapabilityProfile(
        'https://api.example.com:443',
        'model-x',
      );
      expect(stored, result.profile);
    });

    test(
      'sends only the fixed sentence and tolerates a missing model list',
      () async {
        final h = _Harness((call) async {
          if (call.request.method == 'GET') return _json(404, 'not found');
          return _sse(_okStream);
        });

        final result = await h.model.probe();

        expect(result.models, isNull);
        final body = h.calls.last.json;
        final messages = body['messages']! as List<Object?>;
        expect(messages, [
          {
            'role': 'system',
            'content': HttpAnalysisModel.probeRequest.systemPrompt,
          },
          {'role': 'user', 'content': probeUserMessage},
        ]);
        expect(body['max_completion_tokens'], 512);
        final schema =
            (body['response_format']! as Map<String, Object?>)['json_schema'];
        expect(schema, isNotNull);
      },
    );

    test('401 on the model list stops before chat', () async {
      final h = _Harness((_) async => _json(401, _error('bad key')));

      final failure = await _failureOf(h.model.probe());

      expect(failure.kind, AnalysisFailureKind.unauthorized);
      expect(h.calls, hasLength(1));
      expect(h.store.profiles, isEmpty);
    });
  });
}
