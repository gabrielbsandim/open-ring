import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_report_providers.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/presentation/ai_connection_screen.dart';
import 'package:open_ring/features/ai/presentation/ai_history_row.dart';
import 'package:open_ring/features/ai/presentation/ai_test_connection_sheet.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/infrastructure/drift_meal_analysis_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/modules/presentation/modules_screen.dart';
import 'package:open_ring/features/modules/presentation/offered_module.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_screen.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';
import 'package:open_ring/features/trends/presentation/trends_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/ble_fakes.dart';
import '../../../helpers/database.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/settings_fakes.dart';

const _host = 'api.example.com';

final class _PassingModel implements AnalysisModel {
  int probes = 0;

  @override
  Future<ConnectionProbe> probe({
    Future<void>? cancel,
    void Function()? onReached,
  }) async {
    probes++;
    onReached?.call();
    return const ConnectionProbe(
      profile: AiCapabilityProfile.defaults,
      latency: Duration(milliseconds: 400),
    );
  }

  @override
  Stream<AnalysisEvent> generate(
    AnalysisRequest request, {
    required Future<void> cancel,
  }) => throw StateError('the flow never asks for a reading');

  @override
  Future<List<String>> listModels() => throw UnimplementedError();
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  // The address and key were entered earlier (the module was off), so the
  // flow starts at the switch and ends at a passing test.
  testWidgets('A14e: turn on from Modules, test the connection, the Histórico '
      'row appears and Today shows no AI text', (tester) async {
    final modules = InMemoryModuleStore();
    final configs = InMemoryAiConfigStore()
      ..config = const AiConfig(
        baseUrl: 'https://$_host/v1',
        model: 'gpt-test',
        keyLastFour: 'ab3X',
      );
    final secrets = InMemorySecretStore()
      ..values[aiApiKeySecretName] = 'sk-ab3X';
    final model = _PassingModel();
    await pumpScaled(
      tester,
      const OpenRingApp(),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.light,
      locale: const Locale('en'),
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(),
        ...settingsOverrides(),
        moduleStoreProvider.overrideWithValue(modules),
        aiConfigStoreProvider.overrideWithValue(configs),
        secretStoreProvider.overrideWithValue(secrets),
        aiReportStoreProvider.overrideWithValue(InMemoryAiReportStore()),
        aiRunMarkerStoreProvider.overrideWithValue(InMemoryAiRunMarkerStore()),
        mealAnalysisStoreProvider.overrideWithValue(
          DriftMealAnalysisStore(memoryDatabase()),
        ),
        analysisModelFactoryProvider.overrideWithValue((_) async => model),
      ],
    );

    await tester.tap(find.byKey(AppNavigationBar.destinationKey(AppTab.ring)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RingScreen.settingsKey));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(SettingsScreen.modulesKey));
    await tester.tap(find.byKey(SettingsScreen.modulesKey));
    await tester.pumpAndSettle();

    final toggle = find.byKey(ModulesKeys.toggle(OfferedModule.ai));
    await reveal(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(await modules.read(), {ModuleId.ai});
    expect(find.text(l10n.moduleAiTurnedOn), findsOneWidget);
    await tester.tap(find.text(l10n.modulesView));
    await tester.pumpAndSettle();
    expect(find.byType(AiConnectionScreen), findsOneWidget);

    await reveal(tester, find.byKey(AiConnectionKeys.test));
    await tester.tap(find.byKey(AiConnectionKeys.test));
    await tester.pumpAndSettle();
    expect(find.byKey(AiTestKeys.ready), findsOneWidget);
    expect(model.probes, 1);
    expect(configs.config.testedModel, 'gpt-test');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    GoRouter.of(tester.element(find.byType(AiConnectionScreen)))
        .go(AppPaths.trends);
    await tester.pumpAndSettle();
    expect(find.byType(TrendsScreen), findsOneWidget);
    await reveal(tester, find.byKey(AiHistoryRowKeys.row));
    expect(find.byKey(AiHistoryRowKeys.row), findsOneWidget);

    await tester.tap(find.byKey(AppNavigationBar.destinationKey(AppTab.today)));
    await tester.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);
    for (final text in [
      l10n.moduleAiName,
      l10n.aiHistoryRow,
      _host,
      'gpt-test',
    ]) {
      expect(find.textContaining(text), findsNothing, reason: text);
    }
  });
}
