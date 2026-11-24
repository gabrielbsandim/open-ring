import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_provider_preset.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/infrastructure/http_analysis_model.dart';
import 'package:open_ring/features/ai/presentation/ai_connection_screen.dart';
import 'package:open_ring/features/ai/presentation/ai_test_connection_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/layout_harness.dart';

const _openRouter = 'https://openrouter.ai/api/v1';
const _host = 'openrouter.ai';
const _hostKey = 'https://openrouter.ai:443';
const _model = 'openai/gpt-5.4-mini';
const _key = 'sk-or-secret-ab3X';
const _local = 'http://192.168.1.10:11434/v1';

typedef _Script = Future<ConnectionProbe> Function(
  Future<void>? cancel,
  void Function()? onReached,
);

final class _ProbeModel implements AnalysisModel {
  _Script script = _passing(AiJsonMode.jsonSchema);
  int calls = 0;
  bool cancelled = false;
  final List<AiConfig> configs = [];

  @override
  Future<ConnectionProbe> probe({
    Future<void>? cancel,
    void Function()? onReached,
  }) {
    calls++;
    unawaited(cancel?.then((_) => cancelled = true));
    return script(cancel, onReached);
  }

  @override
  Stream<AnalysisEvent> generate(
    AnalysisRequest request, {
    required Future<void> cancel,
  }) => throw UnimplementedError();

  @override
  Future<List<String>> listModels() => throw UnimplementedError();
}

_Script _passing(AiJsonMode mode) => (_, onReached) async {
  onReached?.call();
  return ConnectionProbe(
    profile: AiCapabilityProfile(jsonMode: mode),
    latency: const Duration(milliseconds: 400),
  );
};

_Script _failing(AnalysisFailure failure, {bool reached = false}) =>
    (_, onReached) async {
      if (reached) onReached?.call();
      throw failure;
    };

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final now = DateTime(2026, 11, 24, 8, 12);
  late InMemoryAiConfigStore store;
  late InMemorySecretStore secrets;
  late _ProbeModel model;
  late AnalysisModelFactory factory;

  setUp(() async {
    store = InMemoryAiConfigStore()
      ..config = const AiConfig(
        preset: AiProviderPreset.openRouter,
        baseUrl: _openRouter,
        model: _model,
        keyLastFour: 'ab3X',
      );
    secrets = InMemorySecretStore();
    await secrets.write(aiApiKeySecretName, _key);
    model = _ProbeModel();
    factory = (config) async {
      model.configs.add(config);
      return model;
    };
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiConfigStoreProvider.overrideWithValue(store),
          secretStoreProvider.overrideWithValue(secrets),
          analysisModelFactoryProvider.overrideWithValue(factory),
          clockProvider.overrideWithValue(() => now),
        ],
        child: screenHost(const AiConnectionScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openTest(WidgetTester tester) async {
    await tester.tap(find.byKey(AiConnectionKeys.test));
    await tester.pumpAndSettle();
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  }

  Finder step(int index, AiTestStepState state) =>
      find.byKey(AiTestKeys.step(index, state));

  String messageText(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(AiTestKeys.message),
          matching: find.byType(Text),
        ),
      )
      .data!;

  group('steps', () {
    testWidgets('a passing test marks every step and the ready line', (
      tester,
    ) async {
      await pump(tester);
      await openTest(tester);

      expect(find.text(l10n.aiTestNoData), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        expect(step(i, AiTestStepState.ok), findsOneWidget);
      }
      expect(find.text(l10n.aiTestFormatSchema), findsOneWidget);
      expect(find.byKey(AiTestKeys.ready), findsOneWidget);
      expect(find.byKey(AiTestKeys.details), findsNothing);
    });

    testWidgets('a running test shows reach, then the model step', (
      tester,
    ) async {
      final reach = Completer<void>();
      final answer = Completer<ConnectionProbe>();
      model.script = (_, onReached) async {
        await reach.future;
        onReached?.call();
        return await answer.future;
      };
      await pump(tester);
      await openTest(tester);

      expect(step(0, AiTestStepState.running), findsOneWidget);
      expect(step(1, AiTestStepState.pending), findsOneWidget);
      expect(find.byKey(AiTestKeys.again), findsNothing);

      reach.complete();
      await tester.pumpAndSettle();

      expect(step(1, AiTestStepState.ok), findsOneWidget);
      expect(step(2, AiTestStepState.running), findsOneWidget);
      expect(step(3, AiTestStepState.pending), findsOneWidget);

      answer.complete(
        const ConnectionProbe(
          profile: AiCapabilityProfile(jsonMode: AiJsonMode.jsonObject),
          latency: Duration.zero,
        ),
      );
      await tester.pumpAndSettle();

      expect(step(3, AiTestStepState.ok), findsOneWidget);
      expect(find.text(l10n.aiTestFormatObject), findsOneWidget);
    });

    testWidgets('text only names the stricter checking', (tester) async {
      model.script = _passing(AiJsonMode.none);
      await pump(tester);
      await openTest(tester);

      expect(find.text(l10n.aiTestFormatText), findsOneWidget);
    });

    testWidgets('a failure after reach stops at the model step', (
      tester,
    ) async {
      model.script = _failing(
        const AnalysisFailure(
          kind: AnalysisFailureKind.modelNotFound,
          statusCode: 404,
          detail: 'no such model',
        ),
        reached: true,
      );
      await pump(tester);
      await openTest(tester);

      expect(step(1, AiTestStepState.ok), findsOneWidget);
      expect(step(2, AiTestStepState.failed), findsOneWidget);
      expect(step(3, AiTestStepState.pending), findsOneWidget);
      expect(find.byKey(AiTestKeys.ready), findsNothing);
      expect(find.text('404 · no such model'), findsOneWidget);
    });

    testWidgets('a status on the model list stops at the key step', (
      tester,
    ) async {
      model.script = _failing(
        const AnalysisFailure(
          kind: AnalysisFailureKind.serverError,
          statusCode: 503,
        ),
      );
      await pump(tester);
      await openTest(tester);

      expect(step(0, AiTestStepState.ok), findsOneWidget);
      expect(step(1, AiTestStepState.failed), findsOneWidget);
      expect(find.byKey(AiTestKeys.message), findsNothing);
      expect(find.text('503'), findsOneWidget);
    });

    testWidgets('test again runs a second probe', (tester) async {
      model.script = _failing(
        const AnalysisFailure(kind: AnalysisFailureKind.unreachable),
      );
      await pump(tester);
      await openTest(tester);
      model.script = _passing(AiJsonMode.jsonSchema);

      await tester.tap(find.byKey(AiTestKeys.again));
      await tester.pumpAndSettle();

      expect(model.calls, 2);
      expect(find.byKey(AiTestKeys.ready), findsOneWidget);
    });
  });

  group('error mapping', () {
    final cases = <(String, AnalysisFailure, int, String Function())>[
      (
        'unreachable',
        const AnalysisFailure(kind: AnalysisFailureKind.unreachable),
        0,
        () => l10n.aiErrorUnreachable(_host),
      ),
      (
        'connect timeout',
        const AnalysisFailure(
          kind: AnalysisFailureKind.timeout,
          timeoutStage: TimeoutStage.connect,
        ),
        0,
        () => l10n.aiErrorUnreachable(_host),
      ),
      (
        'tls',
        const AnalysisFailure(kind: AnalysisFailureKind.tls),
        0,
        () => l10n.aiErrorTls(_host),
      ),
      (
        'redirect',
        const AnalysisFailure(
          kind: AnalysisFailureKind.redirect,
          statusCode: 301,
        ),
        0,
        () => l10n.aiErrorRedirect(_host),
      ),
      (
        'cleartext',
        const AnalysisFailure(kind: AnalysisFailureKind.cleartextBlocked),
        0,
        () => l10n.aiConnectionRefusalCleartext(_host),
      ),
      (
        '401',
        const AnalysisFailure(
          kind: AnalysisFailureKind.unauthorized,
          statusCode: 401,
        ),
        1,
        () => l10n.aiErrorKey,
      ),
      (
        'model not found',
        const AnalysisFailure(
          kind: AnalysisFailureKind.modelNotFound,
          statusCode: 404,
        ),
        2,
        () => l10n.aiErrorModelNotFound(_model),
      ),
    ];
    for (final (name, failure, index, message) in cases) {
      testWidgets('$name maps to its line on step $index', (tester) async {
        model.script = _failing(failure, reached: index == 2);
        await pump(tester);
        await openTest(tester);

        expect(step(index, AiTestStepState.failed), findsOneWidget);
        expect(messageText(tester), message());
        expect(store.config.testedAtUtcMs, isNull);
        final silent = failure.statusCode == null && failure.detail.isEmpty;
        expect(
          find.text(l10n.aiErrorDetails),
          silent ? findsNothing : findsOneWidget,
        );
      });
    }

    testWidgets("'403' maps to its line on step 1", (tester) async {
      model.script = _failing(
        const AnalysisFailure(
          kind: AnalysisFailureKind.forbidden,
          statusCode: 403,
        ),
      );
      await pump(tester);
      await openTest(tester);

      expect(step(1, AiTestStepState.failed), findsOneWidget);
      expect(find.text(l10n.aiErrorKey), findsNothing);
      expect(find.byKey(AiTestKeys.message), findsNothing);
      expect(find.text(l10n.aiErrorDetails), findsOneWidget);
      expect(find.text('403'), findsOneWidget);
    });

    testWidgets('a local address gets the same Wi-Fi line', (tester) async {
      store.config = const AiConfig(
        preset: AiProviderPreset.ollama,
        baseUrl: _local,
        model: 'llama3',
      );
      model.script = _failing(
        const AnalysisFailure(kind: AnalysisFailureKind.unreachable),
      );
      await pump(tester);
      await openTest(tester);

      expect(messageText(tester), l10n.aiErrorUnreachableLocal('192.168.1.10'));
    });

    testWidgets('details carry the provider text with the key scrubbed', (
      tester,
    ) async {
      model.script = _failing(
        const AnalysisFailure(
          kind: AnalysisFailureKind.unauthorized,
          statusCode: 401,
          detail: 'Incorrect API key provided: $_key',
        ),
      );
      await pump(tester);
      await openTest(tester);

      expect(find.text(l10n.aiErrorDetails), findsOneWidget);
      expect(
        find.text('401 · Incorrect API key provided: [redacted]'),
        findsOneWidget,
      );
      expect(find.textContaining(_key), findsNothing);
    });
  });

  group('stored result', () {
    testWidgets('a pass stores the profile, the tested state and the caption', (
      tester,
    ) async {
      model.script = _passing(AiJsonMode.jsonObject);
      await pump(tester);
      expect(find.byKey(AiConnectionKeys.tested), findsNothing);

      await openTest(tester);
      await closeSheet(tester);

      expect(store.config.testedHostKey, _hostKey);
      expect(store.config.testedModel, _model);
      expect(store.config.testedAtUtcMs, now.toUtc().millisecondsSinceEpoch);
      expect(store.config.isTestedForCurrentTarget, isTrue);
      expect(
        store.profiles[aiCapabilityProfileKey(_hostKey, _model)]?.jsonMode,
        AiJsonMode.jsonObject,
      );
      expect(
        find.text(l10n.aiTestTested('08:12', 'jsonObject')),
        findsOneWidget,
      );
    });

    testWidgets('a failure stores nothing', (tester) async {
      model.script = _failing(
        const AnalysisFailure(kind: AnalysisFailureKind.unauthorized),
      );
      await pump(tester);
      await openTest(tester);

      expect(store.config.testedAtUtcMs, isNull);
      expect(store.profiles, isEmpty);
    });
  });

  group('running', () {
    testWidgets('closing the sheet cancels the test in flight', (tester) async {
      model.script = (cancel, onReached) async {
        await cancel;
        onReached?.call();
        throw const AnalysisFailure(kind: AnalysisFailureKind.cancelled);
      };
      await pump(tester);
      await openTest(tester);
      expect(model.cancelled, isFalse);

      await closeSheet(tester);

      expect(model.cancelled, isTrue);
      expect(find.byKey(AiTestKeys.sheet), findsNothing);
      expect(store.config.testedAtUtcMs, isNull);
    });

    testWidgets('a double tap starts one test', (tester) async {
      await pump(tester);

      final press = tester
          .widget<OutlinedButton>(find.byKey(AiConnectionKeys.test))
          .onPressed!;

      press();
      press();
      await tester.pumpAndSettle();

      expect(model.calls, 1);
    });

    testWidgets('pending edits are saved before the test', (tester) async {
      await pump(tester);
      await tester.enterText(find.byKey(AiConnectionKeys.model), 'model-y');
      await tester.pump();

      await openTest(tester);

      expect(store.config.model, 'model-y');
      expect(model.configs.single.model, 'model-y');
      expect(store.config.testedModel, 'model-y');
    });

    testWidgets('a declined address switch runs no test', (tester) async {
      await pump(tester);
      await tester.enterText(
        find.byKey(AiConnectionKeys.address),
        'https://api.example.com/v1',
      );
      await tester.pump();

      await openTest(tester);
      await tester.tap(find.byKey(AiConnectionKeys.switchCancel));
      await tester.pumpAndSettle();

      expect(model.calls, 0);
      expect(find.byKey(AiTestKeys.sheet), findsNothing);
    });

    testWidgets('a confirmed switch that deletes the key runs no test', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(
        find.byKey(AiConnectionKeys.address),
        'https://api.example.com/v1',
      );
      await tester.pump();

      await openTest(tester);
      await tester.tap(find.byKey(AiConnectionKeys.switchConfirm));
      await tester.pumpAndSettle();

      expect(store.config.keyLastFour, isNull);
      expect(model.calls, 0);
      expect(find.byKey(AiConnectionKeys.testFillFirst), findsOneWidget);
    });

    testWidgets('an incomplete form asks to fill in and disables the test', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(find.byKey(AiConnectionKeys.model), ' ');
      await tester.pump();

      expect(find.byKey(AiConnectionKeys.testFillFirst), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(AiConnectionKeys.test))
            .enabled,
        isFalse,
      );
    });

    testWidgets('a required key that is missing blocks the test', (
      tester,
    ) async {
      store.config = const AiConfig(
        preset: AiProviderPreset.openRouter,
        baseUrl: _openRouter,
        model: _model,
      );
      await pump(tester);

      expect(find.byKey(AiConnectionKeys.testFillFirst), findsOneWidget);
    });
  });

  testWidgets('the request body carries only the fixed sentence', (
    tester,
  ) async {
    final bodies = <String>[];
    factory = (config) async => HttpAnalysisModel(
      baseUrl: config.normalizedUrl!,
      model: config.trimmedModel,
      apiKey: _key,
      profileStore: store,
      clientFactory: (_, _) => MockClient((request) async {
        bodies.add(request.body);
        if (request.method == 'GET') return http.Response('', 404);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"ok":true}'},
                'finish_reason': 'stop',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await pump(tester);
    await openTest(tester);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.byKey(AiTestKeys.ready), findsOneWidget);

    expect(bodies, hasLength(2));
    final chat = jsonDecode(bodies.last) as Map<String, Object?>;
    expect(chat['messages'], [
      {
        'role': 'system',
        'content': HttpAnalysisModel.probeRequest.systemPrompt,
      },
      {'role': 'user', 'content': probeUserMessage},
    ]);
    expect(bodies.first, isEmpty);
  });
}
