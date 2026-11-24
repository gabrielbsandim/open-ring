import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/base_url_policy.dart';
import 'package:open_ring/features/ai/domain/meal_photo_prompt.dart';
import 'package:open_ring/features/ai/domain/meal_photo_wire.dart';
import 'package:open_ring/features/ai/infrastructure/http_analysis_model.dart';

import '../../../helpers/ai_fakes.dart';
import '../wire_jpeg_fixture.dart';

const _dataUrlHead = 'data:image/jpeg;base64,';

http.Response _json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

final Map<String, Object?> _answer = {
  'choices': [
    {
      'message': {'content': '{"is_food":"yes"}'},
      'finish_reason': 'stop',
    },
  ],
};

final class _Recording {
  new(this.respond);

  final http.Response Function(int call) respond;
  final List<Map<String, Object?>> bodies = [];

  HttpAnalysisModel model() => HttpAnalysisModel(
    baseUrl: switch (BaseUrlPolicy.parse('https://api.example.com/v1')) {
      BaseUrlOk(:final url) => url,
      BaseUrlRejected() => throw StateError('url'),
    },
    model: 'vision-m',
    apiKey: 'sk-test',
    profileStore: InMemoryAiConfigStore(),
    clientFactory: (_, _) => MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, Object?>);
      return respond(bodies.length);
    }),
  );

  Future<void> send(AnalysisRequest request) =>
      model().generate(request, cancel: Completer<void>().future).drain<void>();
}

AnalysisRequest _mealRequest() => buildMealPhotoRequest(
  base64Encode(prepareWirePhoto(leakyPhoto(orientation: 6)).bytes),
  withItems: false,
  replyLanguage: 'en',
  maxOutputTokens: 900,
);

List<Object?> _userParts(Map<String, Object?> body) {
  final messages = body['messages']! as List<Object?>;
  final user = messages[1]! as Map<String, Object?>;
  return user['content']! as List<Object?>;
}

void main() {
  test('the wire carries one text part, then one clean image part', () async {
    final rec = _Recording((_) => _json(200, _answer));

    await rec.send(_mealRequest());

    expect(rec.bodies, hasLength(1));
    final parts = _userParts(rec.bodies.single);
    expect(parts, hasLength(2));
    final text = parts[0]! as Map<String, Object?>;
    final image = parts[1]! as Map<String, Object?>;
    expect(text['type'], 'text');
    expect(image['type'], 'image_url');
    final imageUrl = image['image_url']! as Map<String, Object?>;
    expect(imageUrl.keys, ['url']);
    final url = imageUrl['url']! as String;
    expect(url, startsWith(_dataUrlHead));
    expectNoMetadata(base64Decode(url.substring(_dataUrlHead.length)));
  });

  test('a photo request is non streaming and names openring_meal', () async {
    final rec = _Recording((_) => _json(200, _answer));

    await rec.send(_mealRequest());

    final body = rec.bodies.single;
    expect(body['stream'], isFalse);
    expect(body.containsKey('stream_options'), isFalse);
    final format = body['response_format']! as Map<String, Object?>;
    final schema = format['json_schema']! as Map<String, Object?>;
    expect(schema['name'], 'openring_meal');
  });

  test(
    'a streaming refusal never resends the same non streaming body',
    () async {
      final rec = _Recording(
        (call) => call == 1
            ? _json(400, {
                'error': {'message': 'Unsupported parameter: stream'},
              })
            : _json(200, _answer),
      );

      await rec.send(_mealRequest());

      expect(rec.bodies, hasLength(2));
      expect(rec.bodies.map((b) => b['stream']), everyElement(isFalse));
      final second = rec.bodies[1]['response_format']! as Map<String, Object?>;
      expect(second['type'], 'json_object');
    },
  );

  test('a 400 naming the image stops after one request', () async {
    final rec = _Recording(
      (_) => _json(400, {
        'error': {'message': 'This model does not support image input.'},
      }),
    );

    await expectLater(
      rec.send(_mealRequest()),
      throwsA(isA<AnalysisFailure>().having(isNoVisionFailure, 'vision', true)),
    );
    expect(rec.bodies, hasLength(1));
  });
}
