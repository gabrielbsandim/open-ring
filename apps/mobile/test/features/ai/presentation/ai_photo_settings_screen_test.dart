import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/application/vision_probe_controller.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/analysis_run_state.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/domain/vision_probe.dart';
import 'package:open_ring/features/ai/presentation/ai_failure_message.dart';
import 'package:open_ring/features/ai/presentation/ai_models_sheet.dart';
import 'package:open_ring/features/ai/presentation/ai_photo_settings_screen.dart';
import 'package:open_ring/features/ai/presentation/ai_vision_test_card.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/layout_harness.dart';

const _host = 'https://api.example.com:443';
const _seed = 11;

const _config = AiConfig(
  baseUrl: 'https://api.example.com/v1',
  model: 'text-m',
  photoModel: 'vision-m',
  testedAtUtcMs: 1764000000000,
  testedHostKey: _host,
  testedModel: 'text-m',
);

AnalysisEvent _says(String text) => AnalysisCompleted(
  text: text,
  finishReason: 'stop',
  usage: const AiTokenUsage(promptTokens: 300, completionTokens: 20),
);

String _rightAnswer() => jsonEncode({
  for (final (i, c) in VisionProbeGrid.random(Random(_seed)).cells.indexed)
    visionProbeCellNames[i]: c.name,
});

final class _FakeModel implements AnalysisModel {
  final List<String> sentTo = [];
  FutureOr<AnalysisEvent> Function() reply = () => _says(_rightAnswer());

  @override
  Future<List<String>> listModels() async => ['cheap-vision', 'text-m'];

  @override
  Stream<AnalysisEvent> generate(
    AnalysisRequest request, {
    required Future<void> cancel,
  }) async* {
    final stopped = cancel.then<AnalysisEvent>(
      (_) => throw const AnalysisFailure(kind: AnalysisFailureKind.cancelled),
    );
    yield await Future.any([Future(reply), stopped]);
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late InMemoryAiConfigStore store;
  late _FakeModel model;
  late bool demo;
  late Set<ModuleId> modules;

  setUp(() {
    store = InMemoryAiConfigStore()..config = _config;
    model = _FakeModel();
    demo = false;
    modules = {ModuleId.ai, ModuleId.food};
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 2400);
    addTearDown(tester.view.reset);
    final secrets = InMemorySecretStore()
      ..values[aiApiKeySecretName] = 'sk-test';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
          aiConfigStoreProvider.overrideWithValue(store),
          secretStoreProvider.overrideWithValue(secrets),
          aiRunMarkerStoreProvider.overrideWithValue(
            InMemoryAiRunMarkerStore(),
          ),
          demoModeStoreProvider.overrideWithValue(
            InMemoryDemoModeStore(enabled: demo),
          ),
          visionProbeRandomProvider.overrideWith((_) => Random(_seed)),
          keyedAnalysisModelFactoryProvider.overrideWithValue((config, _) {
            model.sentTo.add(config.trimmedModel);
            return model;
          }),
        ],
        child: screenHost(const AiPhotoSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  String visionLine(String state, String target) =>
      l10n.aiPhotosVisionState(state, target);

  Future<void> runTest(WidgetTester tester) async {
    await tester.tap(find.byKey(AiPhotoKeys.vision));
    await tester.pumpAndSettle();
    expect(find.text(l10n.aiPhotosVisionBody), findsOneWidget);
    await tester.tap(find.byKey(AiVisionTestKeys.run));
    await tester.pumpAndSettle();
  }

  testWidgets('with AI or Food off the screen shows no control', (
    tester,
  ) async {
    for (final off in [ModuleId.ai, ModuleId.food]) {
      modules = {ModuleId.ai, ModuleId.food}..remove(off);
      await pump(tester);

      expect(find.byKey(AiPhotoKeys.vision), findsNothing);
      expect(find.byKey(AiPhotoKeys.limit), findsNothing);
    }
  });

  testWidgets('the four tiles and the sends note show', (tester) async {
    await pump(tester);

    expect(find.text(visionLine('unknown', 'vision-m')), findsOneWidget);
    expect(find.text('vision-m'), findsOneWidget);
    expect(find.text(l10n.aiPhotosLimitValue(8)), findsOneWidget);
    expect(find.text(l10n.aiPhotosConsentNone), findsOneWidget);
    expect(find.text(l10n.aiPhotosSends), findsOneWidget);
    expect(find.byKey(AiPhotoKeys.withdraw), findsNothing);
  });

  group('the photo reading test', () {
    testWidgets('a pass stores yes for the photo model and the tile reads '
        'it', (tester) async {
      await pump(tester);
      await runTest(tester);

      expect(model.sentTo, ['vision-m']);
      expect(
        (await store.readCapabilityProfile(_host, 'vision-m'))?.vision,
        AiVisionSupport.yes,
      );
      expect(find.text(visionLine('yes', 'vision-m')), findsNWidgets(2));
      expect(find.text(l10n.aiTestAgain), findsOneWidget);
    });

    testWidgets('an unreadable answer shows its line and stores nothing', (
      tester,
    ) async {
      model.reply = () => _says('I see no image.');
      await pump(tester);
      await runTest(tester);

      expect(find.text(l10n.aiPhotosVisionUnreadable), findsOneWidget);
      expect(find.text(visionLine('unknown', 'vision-m')), findsOneWidget);
      expect(await store.readCapabilityProfile(_host, 'vision-m'), isNull);
    });

    testWidgets('a timeout shows the failure line and leaves unknown', (
      tester,
    ) async {
      const failure = AnalysisFailure(
        kind: AnalysisFailureKind.timeout,
        timeoutStage: TimeoutStage.total,
      );
      model.reply = () => throw failure;
      await pump(tester);
      await runTest(tester);

      final line = aiFailureMessage(
        l10n,
        const RunModelFailure(failure),
        _config.copyWith(model: 'vision-m'),
      )!;
      expect(find.text(line), findsOneWidget);
      expect(model.sentTo, hasLength(1));
      expect(await store.readCapabilityProfile(_host, 'vision-m'), isNull);
    });

    testWidgets('Cancel aborts and sends nothing more', (tester) async {
      final hold = Completer<AnalysisEvent>();
      model.reply = () => hold.future;
      await pump(tester);
      await tester.tap(find.byKey(AiPhotoKeys.vision));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AiVisionTestKeys.run));
      await tester.pump();

      expect(
        find.text(l10n.aiPhotosVisionRunning('api.example.com')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(AiVisionTestKeys.cancel));
      await tester.pumpAndSettle();
      hold.complete(_says(_rightAnswer()));
      await tester.pumpAndSettle();

      expect(find.byKey(AiVisionTestKeys.running), findsNothing);
      expect(find.byKey(AiVisionTestKeys.result), findsNothing);
      expect(model.sentTo, hasLength(1));
      expect(await store.readCapabilityProfile(_host, 'vision-m'), isNull);
    });
  });

  group('the photo model', () {
    testWidgets('a picked model is stored and the vision line follows it', (
      tester,
    ) async {
      store.config = _config.copyWith(clearPhotoModel: true);
      await store.writeCapabilityProfile(
        _host,
        'text-m',
        const AiCapabilityProfile(vision: AiVisionSupport.no),
      );
      await pump(tester);
      expect(find.text(visionLine('no', 'text-m')), findsOneWidget);
      expect(find.text(l10n.aiPhotosModelSame), findsOneWidget);

      await tester.tap(find.byKey(AiPhotoKeys.model));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AiModelsKeys.model('cheap-vision')));
      await tester.pumpAndSettle();

      expect(store.config.photoModel, 'cheap-vision');
      expect(find.text(visionLine('unknown', 'cheap-vision')), findsOneWidget);
    });

    testWidgets('Use the main model clears it', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(AiPhotoKeys.modelClear));
      await tester.pumpAndSettle();

      expect(store.config.photoModel, isNull);
      expect(find.text(visionLine('unknown', 'text-m')), findsOneWidget);
      expect(find.byKey(AiPhotoKeys.modelClear), findsNothing);
    });
  });

  group('the daily limit', () {
    Future<void> tapTimes(WidgetTester tester, Key key, int times) async {
      for (var i = 0; i < times; i++) {
        await tester.tap(find.byKey(key));
        await tester.pumpAndSettle();
      }
    }

    bool enabled(WidgetTester tester, Key key) =>
        tester.widget<IconButton>(find.byKey(key)).onPressed != null;

    testWidgets('the stepper stops at 30', (tester) async {
      store.config = _config.copyWith(photoDailyLimit: 29);
      await pump(tester);

      await tapTimes(tester, AiPhotoKeys.limitMore, 1);

      expect(store.config.photoDailyLimit, 30);
      expect(find.text(l10n.aiPhotosLimitValue(30)), findsOneWidget);
      expect(enabled(tester, AiPhotoKeys.limitMore), isFalse);
    });

    testWidgets('the stepper stops at 1', (tester) async {
      store.config = _config.copyWith(photoDailyLimit: 3);
      await pump(tester);

      await tapTimes(tester, AiPhotoKeys.limitLess, 2);

      expect(store.config.photoDailyLimit, 1);
      expect(find.text(l10n.aiPhotosLimitValue(1)), findsOneWidget);
      expect(enabled(tester, AiPhotoKeys.limitLess), isFalse);
      expect(enabled(tester, AiPhotoKeys.limitMore), isTrue);
    });
  });

  testWidgets('Withdraw clears the consent and shows the snackbar', (
    tester,
  ) async {
    store.mealPhotoConsent = AiMealPhotoConsent(
      consentedAtUtcMs: DateTime(2026, 12, 7).millisecondsSinceEpoch,
      policyEffectiveDate: aiCurrentPolicyEffectiveDate,
      hostKey: _host,
    );
    await pump(tester);
    final given = l10n.aiConsentGiven('api.example.com', '#').split('#');
    expect(find.textContaining(given.first), findsOneWidget);

    await tester.tap(find.byKey(AiPhotoKeys.withdraw));
    await tester.pumpAndSettle();

    expect(store.mealPhotoConsent, isNull);
    expect(find.text(l10n.aiPhotosWithdrawn), findsOneWidget);
    expect(find.text(l10n.aiPhotosConsentNone), findsOneWidget);
  });

  testWidgets('demo mode shows the lock, disables every control and sends '
      'nothing', (tester) async {
    demo = true;
    store
      ..config = _config.copyWith(photoDailyLimit: 5)
      ..mealPhotoConsent = const AiMealPhotoConsent(
        consentedAtUtcMs: 1,
        policyEffectiveDate: aiCurrentPolicyEffectiveDate,
        hostKey: _host,
      );
    await pump(tester);

    expect(find.byKey(AiPhotoKeys.demoLocked), findsOneWidget);
    for (final key in [
      AiPhotoKeys.vision,
      AiPhotoKeys.model,
      AiPhotoKeys.modelClear,
      AiPhotoKeys.limitLess,
      AiPhotoKeys.limitMore,
      AiPhotoKeys.withdraw,
    ]) {
      await tester.tap(find.byKey(key), warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    expect(find.byKey(AiVisionTestKeys.card), findsNothing);
    expect(find.byKey(AiModelsKeys.sheet), findsNothing);
    expect(store.config, _config.copyWith(photoDailyLimit: 5));
    expect(store.mealPhotoConsent, isNotNull);
    expect(model.sentTo, isEmpty);
  });
}
