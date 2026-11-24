import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_provider_preset.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/presentation/ai_advanced_section.dart';
import 'package:open_ring/features/ai/presentation/ai_connection_screen.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/settings/presentation/settings_routes.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ai_fakes.dart';

const _openRouter = 'https://openrouter.ai/api/v1';
const _model = 'openai/gpt-5.4-mini';

const _tested = AiConfig(
  preset: AiProviderPreset.openRouter,
  baseUrl: _openRouter,
  model: _model,
  keyLastFour: 'ab3X',
  testedAtUtcMs: 1000,
  testedHostKey: 'https://openrouter.ai:443',
  testedModel: _model,
);

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late InMemoryAiConfigStore store;
  late InMemorySecretStore secrets;

  setUp(() async {
    store = InMemoryAiConfigStore()..config = _tested;
    secrets = InMemorySecretStore();
    await secrets.write(aiApiKeySecretName, 'sk-or-secret-ab3X');
  });

  Future<void> pump(
    WidgetTester tester, {
    bool demo = false,
    AiConfigStore? configStore,
    bool open = true,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 5000);
    addTearDown(tester.view.reset);
    final aiRoute = settingsRoute().routes.whereType<GoRoute>().singleWhere(
      (r) => r.path == 'ai-connection',
    );
    final router = GoRouter(
      initialLocation: AppPaths.settingsAiConnection,
      routes: [
        GoRoute(
          path: AppPaths.settings,
          builder: (_, _) => const SizedBox(),
          routes: [aiRoute],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiConfigStoreProvider.overrideWithValue(configStore ?? store),
          secretStoreProvider.overrideWithValue(secrets),
          demoModeStoreProvider.overrideWithValue(
            InMemoryDemoModeStore(enabled: demo),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (!open) return;
    await tester.tap(find.byKey(AiAdvancedKeys.toggle));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Key key, {bool settle = true}) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.tap(find.byKey(key));
    if (settle) {
      await tester.pumpAndSettle();
      return;
    }
    await tester.pump();
  }

  String text(WidgetTester tester, Key key) =>
      tester.widget<TextField>(find.byKey(key)).controller!.text;

  FilledButton saveButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(AiAdvancedKeys.save));

  testWidgets('is collapsed by default and opens with the defaults', (
    tester,
  ) async {
    await pump(tester, open: false);

    expect(find.byKey(AiAdvancedKeys.maxTokens), findsNothing);
    await tap(tester, AiAdvancedKeys.toggle);

    expect(text(tester, AiAdvancedKeys.maxTokens), '4000');
    expect(text(tester, AiAdvancedKeys.tokenCap), isEmpty);
    expect(text(tester, AiAdvancedKeys.priceIn), isEmpty);
    expect(text(tester, AiAdvancedKeys.currency), 'USD');
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(AiAdvancedKeys.timeout(180)))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(AiAdvancedKeys.reasoning(null)))
          .selected,
      isTrue,
    );
    expect(saveButton(tester).onPressed, isNull);
  });

  group('choices save on tap and keep the tested state', () {
    testWidgets('timeout', (tester) async {
      await pump(tester);
      await tap(tester, AiAdvancedKeys.timeout(600));

      expect(store.config.requestTimeoutSeconds, 600);
      expect(store.config.isTestedForCurrentTarget, isTrue);
      expect(store.config.keyLastFour, 'ab3X');
    });

    testWidgets('structured output', (tester) async {
      await pump(tester);
      await tap(
        tester,
        AiAdvancedKeys.structured(AiStructuredOutputMode.jsonObject),
      );

      expect(
        store.config.structuredOutputMode,
        AiStructuredOutputMode.jsonObject,
      );
      expect(store.config.isTestedForCurrentTarget, isTrue);
    });

    testWidgets('streaming', (tester) async {
      await pump(tester);
      await tap(tester, AiAdvancedKeys.streaming(AiStreamingMode.off));

      expect(store.config.streamingMode, AiStreamingMode.off);
      expect(store.config.isTestedForCurrentTarget, isTrue);
    });

    testWidgets('reasoning effort, and back to not sent', (tester) async {
      await pump(tester);
      await tap(tester, AiAdvancedKeys.reasoning(AiReasoningEffort.high));

      expect(store.config.reasoningEffort, AiReasoningEffort.high);
      expect(store.config.isTestedForCurrentTarget, isTrue);

      await tap(tester, AiAdvancedKeys.reasoning(null));
      expect(store.config.reasoningEffort, isNull);
      expect(store.config.toJson().containsKey('reasoningEffort'), isFalse);
    });
  });

  testWidgets('number fields save together with Save', (tester) async {
    await pump(tester);

    await tester.enterText(find.byKey(AiAdvancedKeys.maxTokens), '8000');
    await tester.enterText(find.byKey(AiAdvancedKeys.priceIn), '0,15');
    await tester.enterText(find.byKey(AiAdvancedKeys.priceOut), '0.6');
    await tester.enterText(find.byKey(AiAdvancedKeys.currency), 'EUR');
    await tester.enterText(find.byKey(AiAdvancedKeys.tokenCap), '200000');
    await tester.pump();
    expect(store.config.maxOutputTokens, 4000);

    await tap(tester, AiAdvancedKeys.save);

    expect(store.config.maxOutputTokens, 8000);
    expect(store.config.inputPricePerMillion, 0.15);
    expect(store.config.outputPricePerMillion, 0.6);
    expect(store.config.priceCurrency, 'EUR');
    expect(store.config.monthlyTokenCap, 200000);
    expect(store.config.isTestedForCurrentTarget, isTrue);
    expect(saveButton(tester).onPressed, isNull);
  });

  group('invalid input never saves', () {
    const cases = <(Key, String, String)>[
      (AiAdvancedKeys.maxTokens, '100', 'tokens'),
      (AiAdvancedKeys.maxTokens, '', 'tokens'),
      (AiAdvancedKeys.tokenCap, '0', 'cap'),
      (AiAdvancedKeys.tokenCap, '1.5', 'cap'),
      (AiAdvancedKeys.priceIn, 'abc', 'price'),
      (AiAdvancedKeys.priceOut, '-2', 'price'),
      (AiAdvancedKeys.currency, '', 'currency'),
    ];
    for (final (key, raw, kind) in cases) {
      testWidgets('$key with "$raw"', (tester) async {
        await pump(tester);
        await tester.enterText(find.byKey(AiAdvancedKeys.maxTokens), '9000');
        await tester.enterText(find.byKey(key), raw);
        await tester.pump();

        expect(find.text(l10n.aiAdvancedInvalid(kind)), findsOneWidget);
        expect(saveButton(tester).onPressed, isNull);
        await tap(tester, AiAdvancedKeys.save);
        expect(store.config, _tested);
      });
    }
  });

  group('monthly token cap', () {
    testWidgets('is empty by default and stays out of the JSON', (
      tester,
    ) async {
      await pump(tester);

      expect(text(tester, AiAdvancedKeys.tokenCap), isEmpty);
      expect(find.text(l10n.aiAdvancedTokenCapNone), findsOneWidget);
      expect(store.config.monthlyTokenCap, isNull);
      expect(store.config.toJson().containsKey('monthlyTokenCap'), isFalse);
    });

    testWidgets('clears back to none', (tester) async {
      store.config = _tested.copyWith(monthlyTokenCap: 5000);
      await pump(tester);

      expect(text(tester, AiAdvancedKeys.tokenCap), '5000');
      await tester.enterText(find.byKey(AiAdvancedKeys.tokenCap), '');
      await tester.pump();
      await tap(tester, AiAdvancedKeys.save);

      expect(store.config.monthlyTokenCap, isNull);
      expect(store.config.toJson().containsKey('monthlyTokenCap'), isFalse);
    });
  });

  group('local model note', () {
    testWidgets('shows next to the timeout for a local host', (tester) async {
      store.config = const AiConfig(
        preset: AiProviderPreset.ollama,
        baseUrl: 'http://192.168.1.10:11434/v1',
        model: 'llama3.1',
        requestTimeoutSeconds: 600,
      );
      await pump(tester);

      expect(find.byKey(AiAdvancedKeys.localNote), findsOneWidget);
      expect(find.text(l10n.aiLocalSoftnote), findsOneWidget);
    });

    testWidgets('is hidden for a service on the internet', (tester) async {
      await pump(tester);
      expect(find.byKey(AiAdvancedKeys.localNote), findsNothing);
    });
  });

  testWidgets('demo mode locks every advanced control', (tester) async {
    await pump(tester, demo: true);

    final chips = [
      for (final s in aiAllowedTimeoutSeconds) AiAdvancedKeys.timeout(s),
      for (final m in AiStructuredOutputMode.values)
        AiAdvancedKeys.structured(m),
      for (final m in AiStreamingMode.values) AiAdvancedKeys.streaming(m),
      AiAdvancedKeys.reasoning(null),
      for (final e in AiReasoningEffort.values) AiAdvancedKeys.reasoning(e),
    ];
    for (final key in chips) {
      expect(tester.widget<ChoiceChip>(find.byKey(key)).onSelected, isNull);
    }
    const fields = [
      AiAdvancedKeys.maxTokens,
      AiAdvancedKeys.priceIn,
      AiAdvancedKeys.priceOut,
      AiAdvancedKeys.currency,
      AiAdvancedKeys.tokenCap,
    ];
    for (final key in fields) {
      expect(tester.widget<TextField>(find.byKey(key)).enabled, isFalse);
    }
    tester
            .widget<TextField>(find.byKey(AiAdvancedKeys.tokenCap))
            .controller!
            .text =
        '100';
    await tester.pump();
    expect(saveButton(tester).onPressed, isNull);

    await tap(tester, AiAdvancedKeys.timeout(600));
    await tap(tester, AiAdvancedKeys.save);
    expect(store.config, _tested);
  });

  group('queued writes', () {
    late _GatedStore gated;

    setUp(() => gated = _GatedStore(store));

    testWidgets('choices and Save in a row all land', (tester) async {
      await pump(tester, configStore: gated);
      gated.gate = Completer<void>();

      await tap(tester, AiAdvancedKeys.timeout(600), settle: false);
      await tap(
        tester,
        AiAdvancedKeys.structured(AiStructuredOutputMode.off),
        settle: false,
      );
      await tap(
        tester,
        AiAdvancedKeys.reasoning(AiReasoningEffort.low),
        settle: false,
      );
      await tester.enterText(find.byKey(AiAdvancedKeys.tokenCap), '1000');
      await tester.pump();
      await tap(tester, AiAdvancedKeys.save, settle: false);
      gated.gate!.complete();
      await tester.pumpAndSettle();

      expect(store.config.requestTimeoutSeconds, 600);
      expect(store.config.structuredOutputMode, AiStructuredOutputMode.off);
      expect(store.config.reasoningEffort, AiReasoningEffort.low);
      expect(store.config.monthlyTokenCap, 1000);
    });

    testWidgets('a pending test result survives an advanced change', (
      tester,
    ) async {
      store.config = _tested.copyWith(clearTested: true);
      await pump(tester, configStore: gated);
      gated.gate = Completer<void>();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AiConnectionScreen)),
      );

      final test = container
          .read(aiConfigProvider.notifier)
          .recordTest(
            hostKey: 'https://openrouter.ai:443',
            model: _model,
            profile: AiCapabilityProfile.defaults,
            at: DateTime.utc(2026, 11, 24, 8, 12),
          );
      await tester.pump();
      await tap(tester, AiAdvancedKeys.timeout(60), settle: false);
      gated.gate!.complete();
      await test;
      await tester.pumpAndSettle();

      expect(store.config.isTestedForCurrentTarget, isTrue);
      expect(store.config.requestTimeoutSeconds, 60);
    });
  });
}

final class _GatedStore implements AiConfigStore {
  new(this.inner);

  final InMemoryAiConfigStore inner;
  Completer<void>? gate;

  @override
  Future<void> writeConfig(AiConfig config) async {
    await gate?.future;
    await inner.writeConfig(config);
  }

  @override
  Future<AiConfig> readConfig() => inner.readConfig();

  @override
  Future<AiConsent?> readConsent() => inner.readConsent();

  @override
  Future<void> writeConsent(AiConsent consent) => inner.writeConsent(consent);

  @override
  Future<void> clearConsent() => inner.clearConsent();

  @override
  Future<AiMealPhotoConsent?> readMealPhotoConsent() =>
      inner.readMealPhotoConsent();

  @override
  Future<void> writeMealPhotoConsent(AiMealPhotoConsent consent) =>
      inner.writeMealPhotoConsent(consent);

  @override
  Future<void> clearMealPhotoConsent() => inner.clearMealPhotoConsent();

  @override
  Future<AiCapabilityProfile?> readCapabilityProfile(
    String hostKey,
    String model,
  ) => inner.readCapabilityProfile(hostKey, model);

  @override
  Future<void> writeCapabilityProfile(
    String hostKey,
    String model,
    AiCapabilityProfile profile,
  ) => inner.writeCapabilityProfile(hostKey, model, profile);

  @override
  Future<void> clearCapabilityProfiles() => inner.clearCapabilityProfiles();

  @override
  Future<void> clearAll() => inner.clearAll();
}
