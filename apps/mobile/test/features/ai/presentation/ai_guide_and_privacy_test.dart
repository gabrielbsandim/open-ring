import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_provider_preset.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/presentation/ai_connection_screen.dart';
import 'package:open_ring/features/ai/presentation/ai_guide_screen.dart';
import 'package:open_ring/features/ai/presentation/ai_key_info_screen.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/settings/presentation/settings_routes.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ai_fakes.dart';

const _openRouter = 'https://openrouter.ai/api/v1';
const _model = 'openai/gpt-5.4-mini';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late InMemoryAiConfigStore store;
  late InMemorySecretStore secrets;

  setUp(() {
    store = InMemoryAiConfigStore();
    secrets = InMemorySecretStore();
  });

  Future<void> withTestedTarget() async {
    store.config = const AiConfig(
      preset: AiProviderPreset.openRouter,
      baseUrl: _openRouter,
      model: _model,
      keyLastFour: 'ab3X',
      testedAtUtcMs: 1000,
      testedHostKey: 'https://openrouter.ai:443',
      testedModel: _model,
    );
    await secrets.write(aiApiKeySecretName, 'sk-or-secret-ab3X');
  }

  Future<void> pump(WidgetTester tester, {bool demo = false}) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 3000);
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
  }

  group('guide', () {
    testWidgets('opens from the connection screen and leads back to it', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byKey(AiConnectionKeys.guide));
      await tester.pumpAndSettle();

      expect(find.byType(AiGuideScreen), findsOneWidget);
      for (var step = 1; step <= 4; step++) {
        expect(find.byKey(AiGuideKeys.step(step)), findsOneWidget);
      }
      expect(find.text(l10n.aiGuideStep2Title), findsOneWidget);
      expect(find.byKey(AiGuideKeys.cost), findsOneWidget);

      await tester.tap(find.byKey(AiGuideKeys.local));
      await tester.pumpAndSettle();
      expect(find.text(l10n.aiGuideLocalBody), findsOneWidget);

      await tester.tap(find.byKey(AiGuideKeys.open));
      await tester.pumpAndSettle();

      expect(find.byType(AiGuideScreen), findsNothing);
      expect(find.byType(AiConnectionScreen), findsOneWidget);
    });
  });

  group('detail level', () {
    testWidgets('defaults to Standard and persists a change', (tester) async {
      await withTestedTarget();
      await pump(tester);

      expect(
        find.text(l10n.aiDetailHelp(AiDetailLevel.standard.name)),
        findsOneWidget,
      );

      await tester.tap(find.byKey(AiConnectionKeys.detail(AiDetailLevel.full)));
      await tester.pumpAndSettle();

      expect(store.config.detailLevel, AiDetailLevel.full);
      expect(store.config.isTestedForCurrentTarget, isTrue);
      expect(store.config.keyLastFour, 'ab3X');
      expect(
        find.text(l10n.aiDetailHelp(AiDetailLevel.full.name)),
        findsOneWidget,
      );
    });

    testWidgets('keeps unsaved form edits out of the stored config', (
      tester,
    ) async {
      await withTestedTarget();
      await pump(tester);
      await tester.enterText(find.byKey(AiConnectionKeys.model), 'other');
      await tester.pump();

      await tester.tap(
        find.byKey(AiConnectionKeys.detail(AiDetailLevel.minimal)),
      );
      await tester.pumpAndSettle();

      expect(store.config.detailLevel, AiDetailLevel.minimal);
      expect(store.config.model, _model);
    });
  });

  group('imported data switch', () {
    testWidgets('is off by default and persists when turned on', (
      tester,
    ) async {
      await withTestedTarget();
      await pump(tester);

      final tile = find.byKey(AiConnectionKeys.imported);
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);

      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(store.config.importedIncluded, isTrue);
      expect(store.config.isTestedForCurrentTarget, isTrue);
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    });
  });

  group('demo mode', () {
    testWidgets('blocks every connection edit', (tester) async {
      await withTestedTarget();
      await pump(tester, demo: true);

      expect(find.byKey(AiConnectionKeys.demoLocked), findsOneWidget);
      expect(find.text(l10n.aiDemoLocked), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(AiConnectionKeys.address)).enabled,
        isFalse,
      );
      expect(
        tester.widget<TextField>(find.byKey(AiConnectionKeys.model)).enabled,
        isFalse,
      );
      expect(
        tester.widget<FilledButton>(find.byKey(AiConnectionKeys.save)).enabled,
        isFalse,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(AiConnectionKeys.test))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(AiConnectionKeys.keyReplace))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(AiConnectionKeys.imported))
            .onChanged,
        isNull,
      );

      await tester.tap(find.byKey(AiConnectionKeys.service));
      await tester.tap(find.byKey(AiConnectionKeys.detail(AiDetailLevel.full)));
      await tester.pumpAndSettle();

      expect(
        find.byKey(AiConnectionKeys.preset(AiProviderPreset.openAi)),
        findsNothing,
      );
      expect(store.config.detailLevel, AiDetailLevel.standard);
    });

    testWidgets('hides Remove the key on the key info screen', (tester) async {
      await withTestedTarget();
      await pump(tester, demo: true);

      await tester.tap(find.byKey(AiConnectionKeys.keyInfo));
      await tester.pumpAndSettle();

      expect(find.byType(AiKeyInfoScreen), findsOneWidget);
      expect(find.byKey(AiKeyInfoKeys.remove), findsNothing);
    });

    testWidgets('is absent outside demo mode', (tester) async {
      await pump(tester);

      expect(find.byKey(AiConnectionKeys.demoLocked), findsNothing);
    });
  });
}
