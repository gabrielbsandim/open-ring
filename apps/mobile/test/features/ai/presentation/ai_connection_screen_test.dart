import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_provider_preset.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/presentation/ai_connection_screen.dart';
import 'package:open_ring/features/ai/presentation/ai_photo_settings_screen.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/settings/presentation/settings_routes.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/layout_harness.dart';

const _openRouter = 'https://openrouter.ai/api/v1';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late InMemoryAiConfigStore store;
  late InMemorySecretStore secrets;

  setUp(() {
    store = InMemoryAiConfigStore();
    secrets = InMemorySecretStore();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiEnabledProvider.overrideWithValue(true),
          aiConfigStoreProvider.overrideWithValue(store),
          secretStoreProvider.overrideWithValue(secrets),
        ],
        child: screenHost(const AiConnectionScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> withSavedKey() async {
    store.config = const AiConfig(
      preset: AiProviderPreset.openRouter,
      baseUrl: _openRouter,
      model: 'openai/gpt-5.4-mini',
      keyLastFour: 'ab3X',
    );
    await secrets.write(aiApiKeySecretName, 'sk-or-secret-ab3X');
  }

  Future<void> typeUrl(WidgetTester tester, String url) async {
    await tester.enterText(find.byKey(AiConnectionKeys.address), url);
    await tester.pump();
  }

  bool saveEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(AiConnectionKeys.save)).enabled;

  Future<void> pickPreset(WidgetTester tester, AiProviderPreset preset) async {
    await tester.tap(find.byKey(AiConnectionKeys.service));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AiConnectionKeys.preset(preset)));
    await tester.pumpAndSettle();
  }

  group('address refusals', () {
    testWidgets('public http is refused inline and blocks save', (
      tester,
    ) async {
      await pump(tester);
      await typeUrl(tester, 'http://api.example.com/v1');

      expect(
        find.text(l10n.aiConnectionRefusalCleartext('api.example.com')),
        findsOneWidget,
      );
      expect(find.byKey(AiConnectionKeys.notEncrypted), findsNothing);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('user info names the host the request would reach', (
      tester,
    ) async {
      await pump(tester);
      await typeUrl(tester, 'https://api.openai.com@evil.example/v1');

      expect(
        find.text(l10n.aiConnectionRefusalUserInfo('evil.example')),
        findsOneWidget,
      );
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('other invalid addresses get the generic refusal', (
      tester,
    ) async {
      await pump(tester);
      await typeUrl(tester, 'https://api.example.com/v1?x=1');

      expect(find.text(l10n.aiConnectionRefusalInvalid), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('an empty address shows no refusal', (tester) async {
      await pump(tester);

      expect(find.text(l10n.aiConnectionRefusalInvalid), findsNothing);
      expect(saveEnabled(tester), isFalse);
    });
  });

  group('local http', () {
    testWidgets('a private http address shows the not encrypted warning', (
      tester,
    ) async {
      await pump(tester);
      await typeUrl(tester, 'http://192.168.1.10:11434/v1');

      expect(find.byKey(AiConnectionKeys.notEncrypted), findsOneWidget);
      expect(find.text(l10n.aiConnectionNotEncrypted), findsOneWidget);
      expect(
        find.text(
          l10n.aiConnectionRequestsGoTo(
            'http://192.168.1.10:11434/v1/chat/completions',
          ),
        ),
        findsOneWidget,
      );
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('https shows no warning', (tester) async {
      await pump(tester);
      await typeUrl(tester, _openRouter);

      expect(find.byKey(AiConnectionKeys.notEncrypted), findsNothing);
      expect(find.byKey(AiConnectionKeys.requestsGoTo), findsOneWidget);
    });
  });

  group('saved key', () {
    testWidgets('shows only the last four and never the key', (tester) async {
      await withSavedKey();
      await pump(tester);

      expect(find.text(l10n.aiConnectionKeySaved('ab3X')), findsOneWidget);
      expect(find.byKey(AiConnectionKeys.apiKey), findsNothing);
      expect(find.textContaining('sk-or-secret'), findsNothing);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('a key too short to reveal shows Saved only', (tester) async {
      store.config = const AiConfig(baseUrl: _openRouter, keyLastFour: '');
      await pump(tester);

      expect(find.text(l10n.aiConnectionKeySaved('hidden')), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('replace opens an empty obscured field', (tester) async {
      await withSavedKey();
      await pump(tester);

      await tester.tap(find.byKey(AiConnectionKeys.keyReplace));
      await tester.pump();

      final field = tester.widget<TextField>(
        find.byKey(AiConnectionKeys.apiKey),
      );
      expect(field.obscureText, isTrue);
      expect(field.controller!.text, isEmpty);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.keyboardType, TextInputType.visiblePassword);
    });
  });

  group('save', () {
    testWidgets('writes the config and the key to the secret store', (
      tester,
    ) async {
      await pump(tester);
      await pickPreset(tester, AiProviderPreset.openRouter);
      await tester.enterText(
        find.byKey(AiConnectionKeys.apiKey),
        ' sk-or-1234ab3X ',
      );
      await tester.enterText(find.byKey(AiConnectionKeys.model), 'm-1 ');
      await tester.pump();

      await tester.tap(find.byKey(AiConnectionKeys.save));
      await tester.pumpAndSettle();

      expect(store.config.preset, AiProviderPreset.openRouter);
      expect(store.config.baseUrl, _openRouter);
      expect(store.config.model, 'm-1');
      expect(store.config.keyLastFour, 'ab3X');
      expect(await secrets.read(aiApiKeySecretName), 'sk-or-1234ab3X');
      expect(find.text(l10n.aiConnectionKeySaved('ab3X')), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('a preset fills the address and its defaults, not a model', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(find.byKey(AiConnectionKeys.model), 'kept?');
      await pickPreset(tester, AiProviderPreset.ollama);

      expect(
        tester
            .widget<TextField>(find.byKey(AiConnectionKeys.model))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text(l10n.aiConnectionKeyOptional), findsOneWidget);
      await typeUrl(tester, 'http://192.168.1.10:11434/v1');
      await tester.tap(find.byKey(AiConnectionKeys.save));
      await tester.pumpAndSettle();

      expect(store.config.preset, AiProviderPreset.ollama);
      expect(store.config.model, isEmpty);
      expect(store.config.requestTimeoutSeconds, 600);
      expect(store.config.contextWindow, AiContextWindow.compact);
      expect(secrets.values, isEmpty);
    });

    testWidgets('a path change on the same host keeps the key silently', (
      tester,
    ) async {
      await withSavedKey();
      await pump(tester);
      await typeUrl(tester, 'https://openrouter.ai/api/v2');

      await tester.tap(find.byKey(AiConnectionKeys.save));
      await tester.pumpAndSettle();

      expect(find.byKey(AiConnectionKeys.switchDialog), findsNothing);
      expect(store.config.baseUrl, 'https://openrouter.ai/api/v2');
      expect(await secrets.read(aiApiKeySecretName), 'sk-or-secret-ab3X');
    });
  });

  testWidgets('without a saved key a service switch neither asks nor saves', (
    tester,
  ) async {
    store.config = const AiConfig(
      preset: AiProviderPreset.openRouter,
      baseUrl: _openRouter,
    );
    await pump(tester);
    await pickPreset(tester, AiProviderPreset.groq);

    expect(find.byKey(AiConnectionKeys.switchDialog), findsNothing);
    expect(find.text(AiProviderPreset.groq.baseUrl), findsOneWidget);
    expect(store.config.preset, AiProviderPreset.openRouter);
    expect(store.config.baseUrl, _openRouter);
    expect(saveEnabled(tester), isTrue);
  });

  testWidgets('a service switch empties a typed key', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(AiConnectionKeys.apiKey), 'sk-typed');
    await pickPreset(tester, AiProviderPreset.groq);

    expect(
      tester
          .widget<TextField>(find.byKey(AiConnectionKeys.apiKey))
          .controller!
          .text,
      isEmpty,
    );
  });

  group('host change with a saved key', () {
    testWidgets('switching service deletes the key after confirm', (
      tester,
    ) async {
      await withSavedKey();
      await pump(tester);
      await pickPreset(tester, AiProviderPreset.groq);

      expect(find.byKey(AiConnectionKeys.switchDialog), findsOneWidget);
      expect(
        find.text(l10n.aiConnectionSwitchBody('openrouter.ai')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(AiConnectionKeys.switchConfirm));
      await tester.pumpAndSettle();

      expect(await secrets.read(aiApiKeySecretName), isNull);
      expect(store.config.preset, AiProviderPreset.groq);
      expect(store.config.baseUrl, AiProviderPreset.groq.baseUrl);
      expect(store.config.model, isEmpty);
      expect(store.config.keyLastFour, isNull);
      expect(find.byKey(AiConnectionKeys.apiKey), findsOneWidget);
    });

    testWidgets('cancel keeps the service, the address and the key', (
      tester,
    ) async {
      await withSavedKey();
      await pump(tester);
      await pickPreset(tester, AiProviderPreset.groq);

      await tester.tap(find.byKey(AiConnectionKeys.switchCancel));
      await tester.pumpAndSettle();

      expect(await secrets.read(aiApiKeySecretName), 'sk-or-secret-ab3X');
      expect(store.config.baseUrl, _openRouter);
      expect(find.text('OpenRouter'), findsOneWidget);
      expect(find.text(_openRouter), findsOneWidget);
    });

    testWidgets('a typed new host asks on save, then deletes the key', (
      tester,
    ) async {
      await withSavedKey();
      await pump(tester);
      await typeUrl(tester, 'https://api.other.example/v1');

      await tester.tap(find.byKey(AiConnectionKeys.save));
      await tester.pumpAndSettle();
      expect(find.byKey(AiConnectionKeys.switchDialog), findsOneWidget);
      await tester.tap(find.byKey(AiConnectionKeys.switchConfirm));
      await tester.pumpAndSettle();

      expect(await secrets.read(aiApiKeySecretName), isNull);
      expect(store.config.baseUrl, 'https://api.other.example/v1');
      expect(store.config.keyLastFour, isNull);
    });

    testWidgets('a key typed for the old service never reaches the new one', (
      tester,
    ) async {
      await withSavedKey();
      await pump(tester);
      await tester.tap(find.byKey(AiConnectionKeys.keyReplace));
      await tester.pump();
      await tester.enterText(
        find.byKey(AiConnectionKeys.apiKey),
        'sk-or-typed-9999',
      );
      await pickPreset(tester, AiProviderPreset.groq);
      await tester.tap(find.byKey(AiConnectionKeys.switchConfirm));
      await tester.pumpAndSettle();

      expect(await secrets.read(aiApiKeySecretName), isNull);
      expect(store.config.keyLastFour, isNull);
      expect(
        tester
            .widget<TextField>(find.byKey(AiConnectionKeys.apiKey))
            .controller!
            .text,
        isEmpty,
      );
    });

    testWidgets('a preset without an address changes nothing until saved', (
      tester,
    ) async {
      await withSavedKey();
      final before = store.config;
      await pump(tester);
      await tester.tap(find.byKey(AiConnectionKeys.keyReplace));
      await tester.pump();
      await pickPreset(tester, AiProviderPreset.ollama);

      expect(find.byKey(AiConnectionKeys.switchDialog), findsNothing);
      expect(find.byKey(AiConnectionKeys.keySaved), findsOneWidget);
      expect(store.config, before);
      expect(await secrets.read(aiApiKeySecretName), 'sk-or-secret-ab3X');
      expect(saveEnabled(tester), isFalse);

      await typeUrl(tester, 'http://192.168.1.10:11434/v1');
      await tester.tap(find.byKey(AiConnectionKeys.save));
      await tester.pumpAndSettle();
      expect(find.byKey(AiConnectionKeys.switchDialog), findsOneWidget);
      await tester.tap(find.byKey(AiConnectionKeys.switchConfirm));
      await tester.pumpAndSettle();

      expect(await secrets.read(aiApiKeySecretName), isNull);
      expect(store.config.preset, AiProviderPreset.ollama);
      expect(store.config.baseUrl, 'http://192.168.1.10:11434/v1');
    });

    testWidgets('a typed new host cancelled saves nothing', (tester) async {
      await withSavedKey();
      await pump(tester);
      await typeUrl(tester, 'https://api.other.example/v1');

      await tester.tap(find.byKey(AiConnectionKeys.save));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AiConnectionKeys.switchCancel));
      await tester.pumpAndSettle();

      expect(store.config.baseUrl, _openRouter);
      expect(await secrets.read(aiApiKeySecretName), 'sk-or-secret-ab3X');
    });
  });

  group('the meal photos tile', () {
    const tested = AiConfig(
      baseUrl: 'https://api.example.com/v1',
      model: 'm',
      testedAtUtcMs: 1764000000000,
      testedHostKey: 'https://api.example.com:443',
      testedModel: 'm',
    );

    Future<void> pumpRouted(WidgetTester tester, Set<ModuleId> modules) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(800, 2400);
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
            aiConfigStoreProvider.overrideWithValue(store),
            secretStoreProvider.overrideWithValue(secrets),
            moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
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
    }

    for (final (name, modules, config) in [
      ('Food off', {ModuleId.ai}, tested),
      ('AI off', {ModuleId.food}, tested),
      (
        'an untested target',
        {ModuleId.ai, ModuleId.food},
        tested.copyWith(clearTested: true),
      ),
    ]) {
      testWidgets('is absent with $name', (tester) async {
        store.config = config;
        await pumpRouted(tester, modules);

        expect(find.byKey(AiConnectionKeys.photos), findsNothing);
      });
    }

    testWidgets('with AI and Food on and a tested target it opens the '
        'screen', (tester) async {
      store.config = tested;
      await pumpRouted(tester, {ModuleId.ai, ModuleId.food});

      await tester.tap(find.byKey(AiConnectionKeys.photos));
      await tester.pumpAndSettle();

      expect(find.byType(AiPhotoSettingsScreen), findsOneWidget);
      expect(find.text(l10n.aiPhotosLead), findsOneWidget);
    });
  });
}
