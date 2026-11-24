import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_provider_preset.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/infrastructure/http_analysis_model.dart';
import 'package:open_ring/features/ai/presentation/ai_connection_screen.dart';
import 'package:open_ring/features/ai/presentation/ai_key_info_screen.dart';
import 'package:open_ring/features/ai/presentation/ai_models_sheet.dart';
import 'package:open_ring/features/settings/presentation/settings_routes.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/layout_harness.dart';

const _openRouter = 'https://openrouter.ai/api/v1';
const _key = 'sk-or-secret-ab3X';

final class _ListModel implements AnalysisModel {
  Future<List<String>> Function() models = () async => [
    'openai/gpt-5.4-mini',
    'anthropic/claude-sonnet',
    'google/gemini-flash',
  ];

  @override
  Future<List<String>> listModels() => models();

  @override
  Stream<AnalysisEvent> generate(
    AnalysisRequest request, {
    required Future<void> cancel,
  }) => throw UnimplementedError();

  @override
  Future<ConnectionProbe> probe({
    Future<void>? cancel,
    void Function()? onReached,
  }) => throw UnimplementedError();
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late InMemoryAiConfigStore store;
  late InMemorySecretStore secrets;
  late _ListModel model;
  late List<AiConfig> targets;
  late List<String?> keys;
  late KeyedAnalysisModelFactory keyed;

  setUp(() {
    store = InMemoryAiConfigStore();
    secrets = InMemorySecretStore();
    model = _ListModel();
    targets = [];
    keys = [];
    keyed = (config, apiKey) {
      targets.add(config);
      keys.add(apiKey);
      return model;
    };
  });

  Future<void> withSavedKey() async {
    store.config = const AiConfig(
      preset: AiProviderPreset.openRouter,
      baseUrl: _openRouter,
      model: 'openai/gpt-5.4-mini',
      keyLastFour: 'ab3X',
      testedAtUtcMs: 1764000000000,
      testedHostKey: 'https://openrouter.ai:443',
      testedModel: 'openai/gpt-5.4-mini',
    );
    await secrets.write(aiApiKeySecretName, _key);
  }

  /// A real HTTP model whose GET /models records the Authorization header.
  List<String?> recordAuthorization() {
    final seen = <String?>[];
    keyed = (config, apiKey) => HttpAnalysisModel(
      baseUrl: config.normalizedUrl!,
      model: config.trimmedModel,
      apiKey: apiKey,
      clientFactory: (_, _) => MockClient((request) async {
        seen.add(request.headers['authorization']);
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'm-1'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    return seen;
  }

  Widget scope(Widget child) => ProviderScope(
    overrides: [
      aiConfigStoreProvider.overrideWithValue(store),
      secretStoreProvider.overrideWithValue(secrets),
      keyedAnalysisModelFactoryProvider.overrideWithValue(
        (config, apiKey) => keyed(config, apiKey),
      ),
    ],
    child: child,
  );

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(scope(screenHost(screen)));
    await tester.pumpAndSettle();
  }

  String modelText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(AiConnectionKeys.model))
      .controller!
      .text;

  Future<void> openModelsLive(WidgetTester tester) async {
    await tester.tap(find.byKey(AiConnectionKeys.models));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  Future<void> openModels(WidgetTester tester) async {
    await tester.tap(find.byKey(AiConnectionKeys.models));
    await tester.pumpAndSettle();
  }

  group('models sheet', () {
    test('filters case insensitively and sorts by id', () {
      expect(aiFilterModels(['b-Mini', 'a-max', 'c-mini'], 'MINI'), [
        'b-Mini',
        'c-mini',
      ]);
    });

    testWidgets('lists the host models sorted, with the configured target', (
      tester,
    ) async {
      await withSavedKey();
      await pump(tester, const AiConnectionScreen());
      await openModels(tester);

      expect(find.text(l10n.aiModelsTitle('openrouter.ai')), findsOneWidget);
      final ids = tester
          .widgetList<ListTile>(_sheetTiles)
          .map((t) => (t.title! as Text).data)
          .toList();
      expect(ids, [
        'anthropic/claude-sonnet',
        'google/gemini-flash',
        'openai/gpt-5.4-mini',
      ]);
      expect(
        targets.single.normalizedUrl?.hostKey,
        'https://openrouter.ai:443',
      );
    });

    testWidgets('search filters and shows the empty state', (tester) async {
      await withSavedKey();
      await pump(tester, const AiConnectionScreen());
      await openModels(tester);

      await tester.enterText(find.byKey(AiModelsKeys.search), 'GEMINI');
      await tester.pump();
      expect(_sheetTiles, findsOneWidget);
      expect(find.byKey(AiModelsKeys.model('google/gemini-flash')), findsOne);

      await tester.enterText(find.byKey(AiModelsKeys.search), 'nothing');
      await tester.pump();
      expect(find.byKey(AiModelsKeys.empty), findsOneWidget);
      expect(find.text(l10n.aiModelsEmpty), findsOneWidget);
    });

    testWidgets('selection sets the model field', (tester) async {
      await withSavedKey();
      await pump(tester, const AiConnectionScreen());
      await openModels(tester);

      await tester.tap(find.byKey(AiModelsKeys.model('google/gemini-flash')));
      await tester.pumpAndSettle();

      expect(modelText(tester), 'google/gemini-flash');
    });

    testWidgets('closing the sheet keeps a typed free text name', (
      tester,
    ) async {
      await withSavedKey();
      await pump(tester, const AiConnectionScreen());
      await tester.enterText(find.byKey(AiConnectionKeys.model), 'my-own');
      await tester.pump();
      await openModels(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byKey(AiModelsKeys.sheet), findsNothing);
      expect(modelText(tester), 'my-own');
    });

    testWidgets('a failure shows the mapped message', (tester) async {
      await withSavedKey();
      model.models = () async => throw const AnalysisFailure(
        kind: AnalysisFailureKind.unauthorized,
        statusCode: 401,
        detail: 'bad key',
      );
      await pump(tester, const AiConnectionScreen());
      await openModels(tester);

      expect(find.text(l10n.aiErrorKey), findsOneWidget);
    });

    testWidgets('a key typed before saving goes to the models call', (
      tester,
    ) async {
      final seen = recordAuthorization();
      await pump(tester, const AiConnectionScreen());
      await tester.tap(find.byKey(AiConnectionKeys.service));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(AiConnectionKeys.preset(AiProviderPreset.openRouter)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(AiConnectionKeys.apiKey), 'sk-new-1');
      await tester.pump();
      await openModelsLive(tester);

      expect(seen, ['Bearer sk-new-1']);
      expect(find.byKey(AiModelsKeys.model('m-1')), findsOneWidget);
    });

    testWidgets('a replacing key wins over the stored one', (tester) async {
      await withSavedKey();
      final seen = recordAuthorization();
      await pump(tester, const AiConnectionScreen());
      await tester.tap(find.byKey(AiConnectionKeys.keyReplace));
      await tester.pump();
      await tester.enterText(find.byKey(AiConnectionKeys.apiKey), 'sk-new-2');
      await tester.pump();
      await openModelsLive(tester);

      expect(seen, ['Bearer sk-new-2']);
    });

    testWidgets('the stored key goes to its own host', (tester) async {
      await withSavedKey();
      final seen = recordAuthorization();
      await pump(tester, const AiConnectionScreen());
      await openModelsLive(tester);

      expect(seen, ['Bearer $_key']);
    });

    testWidgets('the stored key never goes to another typed host', (
      tester,
    ) async {
      await withSavedKey();
      store.config = store.config.copyWith(clearKeyLastFour: true);
      final seen = recordAuthorization();
      await pump(tester, const AiConnectionScreen());
      await tester.enterText(
        find.byKey(AiConnectionKeys.address),
        'https://api.other.example/v1',
      );
      await tester.pump();
      await openModelsLive(tester);

      expect(seen, [null]);
    });
  });

  group('key info screen', () {
    testWidgets('shows the host and removes the key', (tester) async {
      await withSavedKey();
      await pump(tester, const AiKeyInfoScreen());

      expect(find.text(l10n.aiKeyInfoGoesTo('openrouter.ai')), findsOneWidget);
      expect(find.text(l10n.aiKeyInfoShorebird), findsOneWidget);
      await tester.tap(find.byKey(AiKeyInfoKeys.remove));
      await tester.pumpAndSettle();

      expect(await secrets.read(aiApiKeySecretName), isNull);
      expect(store.config.keyLastFour, isNull);
      expect(store.config.isTestedForCurrentTarget, isFalse);
      expect(find.byKey(AiKeyInfoKeys.remove), findsNothing);
    });

    testWidgets('opens from the key field', (tester) async {
      await withSavedKey();
      // The app's own ai-connection route, under a stub settings parent.
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
        scope(
          MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(AiConnectionKeys.keyInfo));
      await tester.pumpAndSettle();

      expect(find.byType(AiKeyInfoScreen), findsOneWidget);
    });
  });

  group('connection form additions', () {
    testWidgets('paste fills the key field from the clipboard', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? <String, Object?>{'text': '  sk-pasted-9876 \n'}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pump(tester, const AiConnectionScreen());

      await tester.tap(find.byKey(AiConnectionKeys.keyPaste));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(AiConnectionKeys.apiKey),
      );
      expect(field.controller!.text, 'sk-pasted-9876');
    });

    testWidgets('presets show their note and local ones none', (tester) async {
      await withSavedKey();
      await pump(tester, const AiConnectionScreen());
      expect(find.text(l10n.aiNoteOpenRouter), findsOneWidget);

      store.config = const AiConfig(
        preset: AiProviderPreset.ollama,
        baseUrl: 'http://192.168.1.10:11434/v1',
        model: 'llama',
      );
      await tester.pumpWidget(const SizedBox());
      await pump(tester, const AiConnectionScreen());
      expect(find.byKey(AiConnectionKeys.presetNote), findsNothing);
    });

    testWidgets('a non ASCII host shows the unusual characters line', (
      tester,
    ) async {
      await pump(tester, const AiConnectionScreen());
      await tester.enterText(
        find.byKey(AiConnectionKeys.address),
        'https://api.example.com/v1',
      );
      await tester.pump();
      expect(find.byKey(AiConnectionKeys.hostUnusual), findsNothing);

      await tester.enterText(
        find.byKey(AiConnectionKeys.address),
        'https://café.example/v1',
      );
      await tester.pump();
      expect(find.text(l10n.aiHostUnusual), findsOneWidget);
    });
  });
}

final Finder _sheetTiles = find.descendant(
  of: find.byType(AiModelsSheet),
  matching: find.byType(ListTile),
);
