import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/application/health_context_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/health_context_assembly.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/presentation/ai_connection_screen.dart';
import 'package:open_ring/features/ai/presentation/ai_context_preview_screen.dart';
import 'package:open_ring/features/ai/presentation/ai_guide_screen.dart';
import 'package:open_ring/features/ai/presentation/ai_key_info_screen.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/layout_harness.dart';

const _payload = BuiltAiPayload(
  contextMap: {'reply_language': 'en'},
  canonicalContextJson: '{}',
  systemPrompt: 'system',
  userMessage: 'user',
  facts: [],
  estimatedTokens: 1,
  contextTokens: 1,
  cacheKey: 'context-sha',
  droppedCount: 0,
);

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late int built;

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    Set<ModuleId> modules = const {},
    double scale = 1,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 2000);
    addTearDown(tester.view.reset);
    await expectNoLayoutOverflow(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
            aiConfigStoreProvider.overrideWithValue(
              InMemoryAiConfigStore()
                ..config = const AiConfig(
                  baseUrl: 'https://api.example.com/v1',
                  model: 'm',
                  keyLastFour: 'ab3X',
                ),
            ),
            secretStoreProvider.overrideWithValue(
              InMemorySecretStore()..values[aiApiKeySecretName] = 'sk-ab3X',
            ),
            aiPayloadProvider.overrideWith(
              (ref, _) async => const AiPayloadReady(_payload),
            ),
            keyedAnalysisModelFactoryProvider.overrideWithValue(
              (config, key) => throw StateError('built ${++built}'),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: screen,
          ),
        ),
      );
      await tester.pumpAndSettle();
    });
  }

  void expectNoControls() {
    for (final type in [
      TextField,
      FilledButton,
      OutlinedButton,
      TextButton,
      SegmentedButton<bool>,
    ]) {
      expect(find.byType(type), findsNothing, reason: '$type');
    }
  }

  setUp(() => built = 0);

  for (final scale in const [1.0, 2.0]) {
    group('with AI off at ${scale}x', () {
      testWidgets('the connection shows only its title and lead', (
        tester,
      ) async {
        await pump(tester, const AiConnectionScreen(), scale: scale);

        expect(find.text(l10n.aiConnectionTitle), findsWidgets);
        expect(find.text(l10n.aiConnectionLead), findsOneWidget);
        expectNoControls();
        expect(built, 0);
      });

      testWidgets('the key info shows only its title and lead', (tester) async {
        await pump(tester, const AiKeyInfoScreen(), scale: scale);

        expect(find.text(l10n.aiKeyInfoTitle), findsWidgets);
        expect(find.text(l10n.aiKeyInfoLead), findsOneWidget);
        expect(find.byKey(AiKeyInfoKeys.saved), findsNothing);
        expectNoControls();
      });

      testWidgets('the preview shows only its title and lead', (tester) async {
        await pump(tester, const AiContextPreviewScreen(), scale: scale);

        expect(find.text(l10n.aiPreviewTitle), findsWidgets);
        expect(
          find.text(l10n.aiPreviewLead('api.example.com')),
          findsOneWidget,
        );
        expect(find.byKey(AiPreviewKeys.ask), findsNothing);
        expectNoControls();
        expect(built, 0);
      });

      testWidgets('the guide stays readable without Open the connection', (
        tester,
      ) async {
        await pump(tester, const AiGuideScreen(), scale: scale);

        expect(find.byKey(AiGuideKeys.step(1)), findsOneWidget);
        expect(find.byKey(AiGuideKeys.open), findsNothing);
        expect(find.text(l10n.aiGuideOpen), findsNothing);
      });
    });
  }

  testWidgets('with AI on the connection shows its form and the guide its '
      'button', (tester) async {
    await pump(tester, const AiConnectionScreen(), modules: {ModuleId.ai});
    expect(find.byType(TextField), findsWidgets);

    await pump(tester, const AiGuideScreen(), modules: {ModuleId.ai});
    await tester.scrollUntilVisible(
      find.byKey(AiGuideKeys.open),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(AiGuideKeys.open), findsOneWidget);
    expect(built, 0);
  });
}
