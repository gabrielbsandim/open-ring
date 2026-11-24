import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/application/vision_probe_controller.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_run_state.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/domain/vision_probe.dart';
import 'package:open_ring/features/ai/infrastructure/http_analysis_model.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';

import '../../../helpers/ai_fakes.dart';

const _host = 'https://api.example.com:443';
const _seed = 11;

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

String _rightAnswer() => jsonEncode({
  for (final (i, c) in VisionProbeGrid.random(Random(_seed)).cells.indexed)
    visionProbeCellNames[i]: c.name,
});

void main() {
  late InMemoryAiConfigStore store;
  late List<Map<String, Object?>> bodies;
  late FutureOr<http.Response> Function() respond;
  late bool demo;

  setUp(() {
    store = InMemoryAiConfigStore()
      ..config = const AiConfig(
        baseUrl: 'https://api.example.com/v1',
        model: 'text-m',
        photoModel: 'vision-m',
      );
    bodies = [];
    respond = () => _says(_rightAnswer());
    demo = false;
  });

  ProviderContainer container() {
    final secrets = InMemorySecretStore()
      ..values[aiApiKeySecretName] = 'sk-test';
    final c = ProviderContainer(
      overrides: [
        aiEnabledProvider.overrideWith((ref) => true),
        aiConfigStoreProvider.overrideWithValue(store),
        secretStoreProvider.overrideWithValue(secrets),
        aiRunMarkerStoreProvider.overrideWithValue(InMemoryAiRunMarkerStore()),
        demoModeStoreProvider.overrideWithValue(
          InMemoryDemoModeStore(enabled: demo),
        ),
        visionProbeRandomProvider.overrideWithValue(Random(_seed)),
        keyedAnalysisModelFactoryProvider.overrideWithValue(
          (config, key) => HttpAnalysisModel(
            baseUrl: config.normalizedUrl!,
            model: config.trimmedModel,
            apiKey: key,
            profileStore: store,
            clientFactory: (_, _) => MockClient((request) async {
              bodies.add(jsonDecode(request.body) as Map<String, Object?>);
              return await respond();
            }),
          ),
        ),
      ],
    )..listen(visionProbeControllerProvider, (_, _) {});
    addTearDown(c.dispose);
    return c;
  }

  Future<VisionProbeState> run(ProviderContainer c) async {
    await c.read(visionProbeControllerProvider.notifier).run();
    final state = c.read(visionProbeControllerProvider);
    return state;
  }

  Future<AiVisionSupport?> stored(String model) async =>
      (await store.readCapabilityProfile(_host, model))?.vision;

  test('a pass stores yes for the photo model and refreshes the vision '
      'provider', () async {
    final c = container();
    expect(await c.read(aiPhotoVisionProvider.future), AiVisionSupport.unknown);

    final state = await run(c);

    expect(state.running, isFalse);
    expect(state.result, AiVisionSupport.yes);
    expect(bodies.single['model'], 'vision-m');
    expect(await stored('vision-m'), AiVisionSupport.yes);
    expect(await c.read(aiPhotoVisionProvider.future), AiVisionSupport.yes);
  });

  test('without a photo model the main model is tested', () async {
    store.config = store.config.copyWith(clearPhotoModel: true);

    expect((await run(container())).result, AiVisionSupport.yes);
    expect(await stored('text-m'), AiVisionSupport.yes);
  });

  test('a 400 refusing image input stores no', () async {
    respond = () => _json(400, {
      'error': {'message': 'model does not support image input'},
    });

    expect((await run(container())).result, AiVisionSupport.no);
    expect(await stored('vision-m'), AiVisionSupport.no);
  });

  test('an unreadable answer leaves unknown', () async {
    respond = () => _says('I see nothing.');

    expect((await run(container())).result, AiVisionSupport.unknown);
    expect(await stored('vision-m'), isNull);
  });

  test('a timeout is a model failure, sent once and never retried', () async {
    respond = () => throw TimeoutException('slow');
    final c = container();

    final state = await run(c);
    await pumpEventQueue();

    final failure = state.failure;
    expect(failure, isA<RunModelFailure>());
    expect(
      (failure! as RunModelFailure).failure.kind,
      AnalysisFailureKind.timeout,
    );
    expect(bodies, hasLength(1));
    expect(await stored('vision-m'), isNull);
  });

  test('cancel aborts the request and sends nothing more', () async {
    final hold = Completer<http.Response>();
    respond = () => hold.future;
    final c = container();

    final running = c.read(visionProbeControllerProvider.notifier).run();
    await pumpEventQueue();
    expect(c.read(visionProbeControllerProvider).running, isTrue);

    c.read(visionProbeControllerProvider.notifier).cancel();
    await running;
    hold.complete(_says(_rightAnswer()));
    await pumpEventQueue();

    final state = c.read(visionProbeControllerProvider);
    expect((state.running, state.result, state.failure), (false, null, null));
    expect(bodies, hasLength(1));
    expect(await stored('vision-m'), isNull);
  });

  test('demo mode sends nothing', () async {
    demo = true;

    final state = await run(container());

    expect(state.result, isNull);
    expect(bodies, isEmpty);
  });
}
