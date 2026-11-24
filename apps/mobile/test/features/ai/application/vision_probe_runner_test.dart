import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/application/vision_probe_runner.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/domain/vision_probe.dart';
import 'package:open_ring/features/ai/infrastructure/http_analysis_model.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';

import '../../../helpers/ai_fakes.dart';

const _host = 'https://api.example.com:443';
const _seed = 11;
final _now = DateTime.utc(2026, 12, 7, 8, 20);

http.Response _json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response _says(String content) => _json(200, {
  'choices': [
    {
      'message': {'content': content},
      'finish_reason': 'stop',
    },
  ],
  'usage': {'prompt_tokens': 300, 'completion_tokens': 20},
});

String _cells(List<String> names) =>
    jsonEncode({for (var i = 0; i < 4; i++) visionProbeCellNames[i]: names[i]});

String _rightAnswer() => _cells([
  for (final c in VisionProbeGrid.random(Random(_seed)).cells) c.name,
]);

void main() {
  late InMemoryAiConfigStore configStore;
  late InMemoryAiRunMarkerStore markers;
  late InMemorySecretStore secrets;
  late List<Map<String, Object?>> bodies;
  late List<String> models;
  late FutureOr<http.Response> Function() respond;
  late bool enabled;
  late bool demo;

  setUp(() {
    configStore = InMemoryAiConfigStore()
      ..config = const AiConfig(
        baseUrl: 'https://api.example.com/v1',
        model: 'text-m',
        photoModel: 'vision-m',
      );
    markers = InMemoryAiRunMarkerStore();
    secrets = InMemorySecretStore()..values[aiApiKeySecretName] = 'sk-test';
    bodies = [];
    models = [];
    respond = () => _says(_rightAnswer());
    enabled = true;
    demo = false;
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        aiEnabledProvider.overrideWith((ref) => enabled),
        aiConfigStoreProvider.overrideWithValue(configStore),
        secretStoreProvider.overrideWithValue(secrets),
        aiRunMarkerStoreProvider.overrideWithValue(markers),
        demoModeStoreProvider.overrideWithValue(
          InMemoryDemoModeStore(enabled: demo),
        ),
        clockProvider.overrideWithValue(() => _now),
        keyedAnalysisModelFactoryProvider.overrideWithValue((config, key) {
          models.add(config.trimmedModel);
          return HttpAnalysisModel(
            baseUrl: config.normalizedUrl!,
            model: config.trimmedModel,
            apiKey: key,
            profileStore: configStore,
            clientFactory: (_, _) => MockClient((request) async {
              bodies.add(jsonDecode(request.body) as Map<String, Object?>);
              return await respond();
            }),
          );
        }),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<AiVisionSupport?> probe() {
    final run = FutureProvider<AiVisionSupport?>(
      (ref) => runVisionProbe(ref, random: Random(_seed)),
      retry: (_, _) => null,
    );
    return container().read(run.future);
  }

  Future<AiVisionSupport?> stored(String model) async =>
      (await configStore.readCapabilityProfile(_host, model))?.vision;

  test('a pass stores yes under the photo model and adds the tokens', () async {
    expect(await probe(), AiVisionSupport.yes);

    expect(models, ['vision-m']);
    expect(bodies.single['model'], 'vision-m');
    expect(bodies.single['stream'], isFalse);
    expect(await stored('vision-m'), AiVisionSupport.yes);
    expect(await stored('text-m'), isNull);
    expect(markers.monthSum, 320);
  });

  test('a wrong answer stores no', () async {
    respond = () => _says(_cells(['red', 'red', 'red', 'purple']));

    expect(await probe(), AiVisionSupport.no);
    expect(await stored('vision-m'), AiVisionSupport.no);
  });

  test('a 400 refusing image input sends one request and stores no', () async {
    respond = () => _json(400, {
      'error': {'message': 'model does not support image input'},
    });

    expect(await probe(), AiVisionSupport.no);
    expect(bodies, hasLength(1));
    expect(await stored('vision-m'), AiVisionSupport.no);
    expect(markers.monthSum, 0);
  });

  test('a timeout leaves unknown and rethrows', () async {
    respond = () => throw TimeoutException('slow');

    await expectLater(
      probe(),
      throwsA(
        isA<AnalysisFailure>().having(
          (f) => f.kind,
          'kind',
          AnalysisFailureKind.timeout,
        ),
      ),
    );
    expect(await stored('vision-m'), isNull);
  });

  test('an unreadable answer leaves the stored support alone', () async {
    await configStore.writeCapabilityProfile(
      _host,
      'vision-m',
      const AiCapabilityProfile(vision: AiVisionSupport.yes),
    );
    respond = () => _says('I cannot see any image.');

    expect(await probe(), AiVisionSupport.unknown);
    expect(await stored('vision-m'), AiVisionSupport.yes);
  });

  test('a 400 echoing a vision model name steps down, not to no', () async {
    var calls = 0;
    respond = () => ++calls == 1
        ? _json(400, {
            'error': {
              'message':
                  'llama-3.2-11b-vision-instruct does not support '
                  'response_format json_schema',
            },
          })
        : _says(_rightAnswer());

    expect(await probe(), AiVisionSupport.yes);
    expect(bodies, hasLength(2));
    final second = bodies[1]['response_format']! as Map<String, Object?>;
    expect(second['type'], 'json_object');
    expect(await stored('vision-m'), AiVisionSupport.yes);
  });

  test('no photo model targets the main model', () async {
    configStore.config = configStore.config.copyWith(clearPhotoModel: true);

    expect(await probe(), AiVisionSupport.yes);
    expect(models, ['text-m']);
    expect(await stored('text-m'), AiVisionSupport.yes);
  });

  test('a profile the ladder learned keeps its wire fields', () async {
    await configStore.writeCapabilityProfile(
      _host,
      'vision-m',
      const AiCapabilityProfile(limitField: AiLimitField.maxTokens),
    );

    await probe();

    final profile = await configStore.readCapabilityProfile(_host, 'vision-m');
    expect(profile!.limitField, AiLimitField.maxTokens);
    expect(profile.vision, AiVisionSupport.yes);
    expect(bodies.single.containsKey('max_tokens'), isTrue);
  });

  test('refuses in demo mode', () async {
    demo = true;

    expect(await probe(), isNull);
    expect(bodies, isEmpty);
  });

  test('refuses with AI off', () async {
    enabled = false;

    expect(await probe(), isNull);
    expect(bodies, isEmpty);
  });
}
