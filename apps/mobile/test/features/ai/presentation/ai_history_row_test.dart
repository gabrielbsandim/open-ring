import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/presentation/ai_history_row.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/trends/presentation/trends_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/metrics_fakes.dart';

const _url = 'https://api.example.com/v1';
const _hostKey = 'https://api.example.com:443';

final class _SlowSecretStore implements SecretStore {
  final Completer<void> gate = Completer<void>();
  final Map<String, String> values = {};
  int reads = 0;

  @override
  Future<String?> read(String name) async {
    reads++;
    await gate.future;
    return values[name];
  }

  @override
  Future<void> write(String name, String value) async => values[name] = value;

  @override
  Future<void> delete(String name) async => values.remove(name);
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late InMemoryAiConfigStore configs;
  late SecretStore secrets;
  late Set<ModuleId> modules;
  late bool demo;

  setUp(() {
    configs = InMemoryAiConfigStore()
      ..config = AiConfig(
        baseUrl: _url,
        model: 'gpt-test',
        keyLastFour: 'ab3X',
        testedAtUtcMs: 1,
        testedHostKey: const AiConfig(baseUrl: _url).hostKey,
        testedModel: 'gpt-test',
      );
    secrets = InMemorySecretStore()..values[aiApiKeySecretName] = 'sk-ab3X';
    modules = {ModuleId.ai};
    demo = false;
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 4000);
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: AppPaths.trends,
      routes: [
        GoRoute(
          path: AppPaths.trends,
          builder: (_, _) => const TrendsScreen(),
          routes: [
            GoRoute(
              path: 'ai',
              builder: (_, _) => const Text('readings screen'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...metricsOverrides(fullDataScenario),
          moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
          aiConfigStoreProvider.overrideWithValue(configs),
          secretStoreProvider.overrideWithValue(secrets),
          demoModeStoreProvider.overrideWithValue(
            InMemoryDemoModeStore(enabled: demo),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final row = find.byKey(AiHistoryRowKeys.row);

  testWidgets('a tested connection shows the row last, with host and model', (
    tester,
  ) async {
    await pump(tester);

    expect(row, findsOneWidget);
    expect(find.text(l10n.aiHistoryRow), findsOneWidget);
    expect(find.text('api.example.com · gpt-test'), findsOneWidget);
    expect(
      tester.getTopLeft(row).dy,
      greaterThan(tester.getTopLeft(find.byType(EstimateNote)).dy),
    );
  });

  testWidgets('consent still needed keeps the row', (tester) async {
    configs.consent = null;
    await pump(tester);

    expect(row, findsOneWidget);
  });

  testWidgets('a ready connection keeps the row', (tester) async {
    configs.consent = const AiConsent(
      consentedAtUtcMs: 0,
      policyEffectiveDate: aiCurrentPolicyEffectiveDate,
      hostKey: _hostKey,
      detailLevel: AiDetailLevel.standard,
      contextSchemaVersion: aiContextSchemaVersion,
    );
    await pump(tester);

    expect(row, findsOneWidget);
  });

  testWidgets('tapping the row opens the readings screen', (tester) async {
    await pump(tester);
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('readings screen'), findsOneWidget);
  });

  testWidgets('no row with the AI module off, and nothing AI is read', (
    tester,
  ) async {
    modules = {};
    final slow = _SlowSecretStore();
    secrets = slow;
    await pump(tester);

    expect(row, findsNothing);
    expect(find.text(l10n.aiHistoryRow), findsNothing);
    expect(find.byType(EstimateNote), findsOneWidget);
    expect(slow.reads, 0);
  });

  testWidgets('no row while the connection is untested', (tester) async {
    configs.config = const AiConfig(
      baseUrl: _url,
      model: 'gpt-test',
      keyLastFour: 'ab3X',
    );
    await pump(tester);

    expect(row, findsNothing);
  });

  testWidgets('no row while the key is missing', (tester) async {
    secrets = InMemorySecretStore();
    await pump(tester);

    expect(row, findsNothing);
  });

  testWidgets('no row while availability is loading', (tester) async {
    final slow = _SlowSecretStore()..values[aiApiKeySecretName] = 'sk-ab3X';
    secrets = slow;
    await pump(tester);

    expect(row, findsNothing);

    slow.gate.complete();
    await tester.pumpAndSettle();
    expect(row, findsOneWidget);
  });

  testWidgets('demo mode shows the row without a tested connection', (
    tester,
  ) async {
    demo = true;
    configs.config = AiConfig.defaults;
    await pump(tester);

    expect(row, findsOneWidget);
    expect(find.text(l10n.aiReadingSampleBy), findsOneWidget);
  });

  testWidgets('demo mode with the AI module off shows no row', (tester) async {
    demo = true;
    modules = {};
    await pump(tester);

    expect(row, findsNothing);
  });
}
