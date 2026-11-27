import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_data_eraser.dart';
import 'package:open_ring/features/ai/application/ai_report_providers.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/presentation/ai_module_screen.dart';
import 'package:open_ring/features/ai/presentation/ai_reading_sheets.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/infrastructure/drift_meal_analysis_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/ble_fakes.dart';
import '../../../helpers/database.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/onboarding_app.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart';

const _url = 'https://api.example.com/v1';
const _hostKey = 'https://api.example.com:443';
final _now = DateTime.utc(2026, 11, 25, 12);

final class _GatedModuleStore implements ModuleStore {
  new({this.gate, this.fail = false});

  final Completer<void>? gate;
  final bool fail;
  Set<ModuleId> _enabled = {};
  int writeCalls = 0;

  @override
  Future<Set<ModuleId>> read() async => {..._enabled};

  @override
  Future<void> write(Set<ModuleId> enabled) async {
    writeCalls++;
    await gate?.future;
    if (fail) throw const FileSystemException('disk full');
    _enabled = {...enabled};
  }

  @override
  Future<bool> shortcutDismissed() async => false;

  @override
  Future<void> dismissShortcut({required bool dismissed}) async {}
}

AiReport _report({
  required DateTime at,
  AiReportStatus status = AiReportStatus.done,
  int? prompt,
  int? completion,
}) => AiReport(
  createdAtUtc: at,
  offsetMin: 0,
  kind: 'daily',
  contextSchema: 'health_context_v2',
  contextSha256: 'sha-${at.millisecondsSinceEpoch}',
  detailLevel: 'standard',
  promptVersion: 'v1',
  providerHost: _hostKey,
  model: 'gpt-test',
  status: status,
  promptTokens: prompt,
  completionTokens: completion,
);

AiConfig _tested({int? cap}) => AiConfig(
  baseUrl: _url,
  model: 'gpt-test',
  keyLastFour: 'ab3X',
  testedAtUtcMs: 1,
  testedHostKey: _hostKey,
  testedModel: 'gpt-test',
  monthlyTokenCap: cap,
);

final class _CountingEraser implements AiDataEraser {
  int calls = 0;

  @override
  Future<bool> clear() async {
    calls++;
    return true;
  }
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late InMemoryAiConfigStore configs;
  late SecretStore secrets;
  _CountingEraser? eraser;
  late InMemoryAiReportStore reports;
  late ModuleStore modules;
  late bool demo;
  late int factoryCalls;

  setUp(() {
    configs = InMemoryAiConfigStore()..config = _tested();
    secrets = InMemorySecretStore()..values[aiApiKeySecretName] = 'sk-ab3X';
    reports = InMemoryAiReportStore();
    modules = InMemoryModuleStore({ModuleId.ai});
    demo = false;
    factoryCalls = 0;
    eraser = null;
  });

  Future<void> pump(
    WidgetTester tester, {
    double scale = 1,
    Size size = const Size(360, 4000),
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: AppPaths.settingsModuleAi,
      routes: [
        GoRoute(
          path: AppPaths.settingsModuleAi,
          builder: (_, _) => const AiModuleScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await expectNoLayoutOverflow(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            moduleStoreProvider.overrideWithValue(modules),
            aiConfigStoreProvider.overrideWithValue(configs),
            secretStoreProvider.overrideWithValue(secrets),
            aiReportStoreProvider.overrideWithValue(reports),
            demoModeStoreProvider.overrideWithValue(
              InMemoryDemoModeStore(enabled: demo),
            ),
            clockProvider.overrideWithValue(() => _now),
            keyedAnalysisModelFactoryProvider.overrideWithValue(
              (config, apiKey) => throw StateError('built ${++factoryCalls}'),
            ),
            aiRunMarkerStoreProvider.overrideWithValue(
              InMemoryAiRunMarkerStore(),
            ),
            mealAnalysisStoreProvider.overrideWithValue(
              DriftMealAnalysisStore(memoryDatabase()),
            ),
            if (eraser case final fake?)
              aiDataEraserProvider.overrideWithValue(fake),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
    });
  }

  // The page builds lazily, so each check scrolls to its widget; layout
  // overflow is caught along the way.
  Future<void> reach(WidgetTester tester, Finder finder) =>
      expectNoLayoutOverflow(
        () => tester.scrollUntilVisible(
          finder,
          300,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 200,
        ),
      );

  // The longer privacy facts can leave a button under the bottom edge.
  Future<void> reachToTap(WidgetTester tester, Finder finder) async {
    await reach(tester, finder);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  String? detail(WidgetTester tester, Key key) =>
      tester.widget<SettingsTile>(find.byKey(key)).detail;

  const factKeys = [
    AiModuleKeys.adds,
    AiModuleKeys.uses,
    AiModuleKeys.sends,
    AiModuleKeys.stores,
    AiModuleKeys.never,
  ];

  test('route path is /ring/settings/modules/ai', () {
    expect(AppPaths.settingsModuleAi, '/ring/settings/modules/ai');
  });

  for (final scale in const [1.0, 2.0]) {
    testWidgets('off at ${scale}x: pill, five facts, links, foot, turn on, '
        'no tiles', (tester) async {
      modules = InMemoryModuleStore();
      await pump(tester, scale: scale);

      final pill = tester.widget<ModuleStatePill>(
        find.byKey(AiModuleKeys.state),
      );
      expect(pill.on, isFalse);
      expect(pill.label, l10n.modulesOff);
      for (final key in [
        AiModuleKeys.readings,
        AiModuleKeys.connection,
        AiModuleKeys.usage,
      ]) {
        expect(find.byKey(key), findsNothing);
      }
      final storesLine = find.text(
        l10n.moduleAiStores('readings', aiReportKeepCount, aiReportPayloadDays),
      );
      for (final finder in [
        for (final key in factKeys) find.byKey(key),
        storesLine,
        find.byKey(AiModuleKeys.guide),
        find.byKey(AiModuleKeys.formula),
        find.text(l10n.moduleBodyFoot),
        find.text(l10n.moduleAiTurnOn),
        find.text(l10n.moduleAiTurnOnNote),
      ]) {
        await reach(tester, finder);
        expect(finder, findsOneWidget);
      }
      expect(factoryCalls, 0);
    });

    testWidgets('on at ${scale}x: tiles, facts and turn off fit', (
      tester,
    ) async {
      reports.reports.add(_report(at: _now, prompt: 10, completion: 5));
      await pump(tester, scale: scale);

      for (final finder in [
        find.byKey(AiModuleKeys.readings),
        find.byKey(AiModuleKeys.connection),
        find.byKey(AiModuleKeys.usage),
        for (final key in factKeys) find.byKey(key),
        find.text(l10n.moduleAiTurnOff),
        find.text(l10n.moduleAiTurnOffNote),
      ]) {
        await reach(tester, finder);
        expect(finder, findsOneWidget);
      }
    });
  }

  group('connection line', () {
    testWidgets('no address is not connected', (tester) async {
      configs.config = AiConfig.defaults;
      await pump(tester);

      expect(detail(tester, AiModuleKeys.connection), 'Not connected');
    });

    testWidgets('set up but untested names the host', (tester) async {
      configs.config = const AiConfig(baseUrl: _url, model: 'gpt-test');
      await pump(tester);

      expect(
        detail(tester, AiModuleKeys.connection),
        'Set up, not tested · api.example.com',
      );
    });

    testWidgets('consent needed reads as ready', (tester) async {
      configs.consent = null;
      await pump(tester);

      expect(
        detail(tester, AiModuleKeys.connection),
        'Ready: api.example.com · gpt-test',
      );
    });

    testWidgets('ready names host and model', (tester) async {
      configs.consent = const AiConsent(
        consentedAtUtcMs: 0,
        policyEffectiveDate: aiCurrentPolicyEffectiveDate,
        hostKey: _hostKey,
        detailLevel: AiDetailLevel.standard,
        contextSchemaVersion: aiContextSchemaVersion,
      );
      await pump(tester);

      expect(
        detail(tester, AiModuleKeys.connection),
        'Ready: api.example.com · gpt-test',
      );
    });
  });

  group('readings line', () {
    testWidgets('none stored', (tester) async {
      await pump(tester);

      expect(detail(tester, AiModuleKeys.readings), l10n.moduleAiReadingsNone);
    });

    testWidgets('the last done reading of this host and model', (tester) async {
      reports.reports.add(_report(at: _now));
      await pump(tester);

      final line = detail(tester, AiModuleKeys.readings)!;
      expect(line, startsWith('Last: '));
      expect(line, endsWith(', ${l10n.aiReadingKind('daily')}'));
    });

    testWidgets('demo shows the sample line', (tester) async {
      demo = true;
      reports.reports.add(_report(at: _now));
      await pump(tester);

      expect(detail(tester, AiModuleKeys.readings), l10n.aiReadingSampleBy);
      expect(factoryCalls, 0);
    });
  });

  group('usage', () {
    testWidgets('nothing in 30 days', (tester) async {
      await pump(tester);

      expect(detail(tester, AiModuleKeys.usage), 'No readings');
    });

    testWidgets(
      'N readings with reported tokens, and the sheet shows the cap',
      (tester) async {
        configs.config = _tested(cap: 50000);
        reports.reports
          ..add(_report(at: _now, prompt: 100, completion: 20))
          ..add(
            _report(
              at: _now.subtract(const Duration(days: 2)),
              prompt: 30,
              completion: 4,
            ),
          )
          ..add(
            _report(
              at: _now.subtract(const Duration(days: 40)),
              prompt: 999,
              completion: 1,
            ),
          );
        await pump(tester);

        expect(
          detail(tester, AiModuleKeys.usage),
          '2 readings · 154 tokens reported',
        );
        await tester.tap(find.byKey(AiModuleKeys.usage));
        await tester.pumpAndSettle();

        expect(find.byKey(AiSheetKeys.usage30), findsOneWidget);
        expect(find.text(l10n.aiUsage30Title(2)), findsOneWidget);
        expect(find.text('50,000'), findsOneWidget);
        expect(factoryCalls, 0);
      },
    );
  });

  testWidgets('turning on writes the module once, guards a double tap and '
      'says it is on', (tester) async {
    final gate = Completer<void>();
    final store = _GatedModuleStore(gate: gate);
    modules = store;
    await pump(tester);

    final toggle = find.byKey(AiModuleKeys.toggle);
    await reachToTap(tester, toggle);
    await tester.tap(toggle);
    await tester.pump();
    await tester.tap(toggle, warnIfMissed: false);
    await tester.pump();
    expect(store.writeCalls, 1);

    gate.complete();
    await tester.pumpAndSettle();

    expect(store.writeCalls, 1);
    expect(await store.read(), {ModuleId.ai});
    await reach(tester, find.text(l10n.moduleAiTurnOff));
    expect(find.text(l10n.moduleAiTurnOff), findsOneWidget);
    expect(find.text(l10n.moduleAiTurnedOn), findsOneWidget);
    expect(find.text(l10n.modulesView), findsOneWidget);
    expect(factoryCalls, 0);
  });

  testWidgets('a store failure shows the save error and stays off', (
    tester,
  ) async {
    final store = _GatedModuleStore(fail: true);
    modules = store;
    await pump(tester);

    final toggle = find.byKey(AiModuleKeys.toggle);
    await reachToTap(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.text(l10n.syncErrorSaving), findsOneWidget);
    expect(find.text(l10n.moduleAiTurnOn), findsOneWidget);
    expect(
      tester.widget<ModuleStatePill>(find.byKey(AiModuleKeys.state)).on,
      isFalse,
    );
    expect(store.writeCalls, 1);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(store.writeCalls, 2, reason: 'a failure must release the guard');
  });

  testWidgets('opening the screen with AI on reads stores and sends nothing', (
    tester,
  ) async {
    reports.reports.add(_report(at: _now, prompt: 1, completion: 1));
    await pump(tester);

    expect(factoryCalls, 0);
    expect(find.byType(AiModuleScreen), findsOneWidget);
  });

  testWidgets('the real router opens the screen, and turning on builds no '
      'model', (tester) async {
    modules = InMemoryModuleStore();
    final container = await pumpOnboardingApp(
      tester,
      store: InMemoryOnboardingStore(completed: true),
      at: AppPaths.settingsModuleAi,
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(),
        ...onboardingOverrides(),
        moduleStoreProvider.overrideWithValue(modules),
        aiConfigStoreProvider.overrideWithValue(configs),
        secretStoreProvider.overrideWithValue(secrets),
        aiReportStoreProvider.overrideWithValue(reports),
        keyedAnalysisModelFactoryProvider.overrideWithValue(
          (config, apiKey) => throw StateError('built ${++factoryCalls}'),
        ),
      ],
    );

    expect(find.byType(AiModuleScreen), findsOneWidget);
    expect(factoryCalls, 0);

    await tapAndSettle(tester, find.byKey(AiModuleKeys.toggle));

    expect(await modules.read(), {ModuleId.ai});
    expect(container.read(enabledModulesProvider).value, contains(ModuleId.ai));
    await tester.scrollUntilVisible(
      find.byKey(AiModuleKeys.connection),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(AiModuleKeys.connection), findsOneWidget);
    expect(factoryCalls, 0);
  });

  group('AI data', () {
    const consent = AiConsent(
      consentedAtUtcMs: 0,
      policyEffectiveDate: aiCurrentPolicyEffectiveDate,
      hostKey: _hostKey,
      detailLevel: AiDetailLevel.standard,
      contextSchemaVersion: aiContextSchemaVersion,
    );

    String dataLine(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(AiModuleKeys.data),
            matching: find.byType(Text),
          ),
        )
        .data!;

    Future<void> openDialog(WidgetTester tester) async {
      await reachToTap(tester, find.byKey(AiModuleKeys.delete));
      await tester.tap(find.byKey(AiModuleKeys.delete));
      await expectNoLayoutOverflow(tester.pumpAndSettle);
    }

    testWidgets('lists readings, key and consent', (tester) async {
      configs.consent = consent;
      reports.reports
        ..add(_report(at: _now))
        ..add(
          _report(
            at: _now.subtract(const Duration(hours: 1)),
            status: AiReportStatus.failed,
          ),
        );
      await pump(tester);
      await reach(tester, find.byKey(AiModuleKeys.data));

      expect(
        dataLine(tester),
        startsWith(
          '2 readings on this phone. Key saved, ends in ab3X. '
          'Consent given for api.example.com on ',
        ),
      );
    });

    testWidgets('a hidden key reads as saved', (tester) async {
      configs.config = _tested().copyWith(keyLastFour: '');
      await pump(tester);
      await reach(tester, find.byKey(AiModuleKeys.data));

      expect(
        dataLine(tester),
        '0 readings on this phone. ${l10n.moduleAiDataKey('hidden', '')}',
      );
    });

    testWidgets('nothing stored shows the empty line and no Remove', (
      tester,
    ) async {
      configs.config = AiConfig.defaults;
      secrets = InMemorySecretStore();
      await pump(tester);
      await reach(tester, find.byKey(AiModuleKeys.data));

      expect(dataLine(tester), l10n.moduleAiDataEmpty);
      expect(find.byKey(AiModuleKeys.delete), findsNothing);
    });

    testWidgets('demo shows no Remove and never calls the eraser', (
      tester,
    ) async {
      demo = true;
      eraser = _CountingEraser();
      reports.reports.add(_report(at: _now));
      await pump(tester);
      await reach(tester, find.text(l10n.moduleAiTurnOffNote));

      expect(find.byKey(AiModuleKeys.data), findsOneWidget);
      expect(find.byKey(AiModuleKeys.delete), findsNothing);
      expect(eraser!.calls, 0);
    });

    testWidgets('Remove shows with the module off', (tester) async {
      modules = InMemoryModuleStore();
      await pump(tester);
      await reach(tester, find.byKey(AiModuleKeys.delete));

      expect(find.byKey(AiModuleKeys.delete), findsOneWidget);
      expect(find.byKey(AiModuleKeys.readings), findsNothing);
    });

    for (final scale in const [1.0, 2.0]) {
      testWidgets('cancel at ${scale}x shows the notes and writes nothing', (
        tester,
      ) async {
        eraser = _CountingEraser();
        configs.consent = consent;
        reports.reports.add(_report(at: _now));
        await pump(tester, scale: scale, size: const Size(360, 720));
        await openDialog(tester);

        expect(find.text(l10n.moduleAiDeleteTitle), findsOneWidget);
        for (final text in [
          l10n.moduleAiDeleteBody(1),
          l10n.moduleAiDeleteNotes('received', 'api.example.com'),
          l10n.moduleAiDeleteNotes('key', ''),
          l10n.moduleAiDeleteNotes('module', ''),
        ]) {
          await tester.scrollUntilVisible(
            find.text(text),
            100,
            scrollable: find
                .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(find.text(text), findsOneWidget);
        }
        await tester.tap(find.byKey(AiModuleKeys.deleteCancel));
        await tester.pumpAndSettle();

        expect(eraser!.calls, 0);
        expect(configs.config, _tested());
        expect(configs.consent, consent);
        expect(await secrets.read(aiApiKeySecretName), 'sk-ab3X');
        expect(reports.reports, hasLength(1));
        expect(find.byType(SnackBar), findsNothing);
      });
    }

    testWidgets('confirm removes everything and the tiles read empty', (
      tester,
    ) async {
      configs.consent = consent;
      reports.reports.add(_report(at: _now));
      await pump(tester);
      await openDialog(tester);
      await tester.tap(find.byKey(AiModuleKeys.deleteConfirm));
      await tester.pumpAndSettle();

      expect(find.text(l10n.moduleAiDeleted), findsOneWidget);
      expect(configs.config, AiConfig.defaults);
      expect(configs.consent, isNull);
      expect(await secrets.read(aiApiKeySecretName), isNull);
      expect(reports.reports, isEmpty);
      expect(await modules.read(), {ModuleId.ai});
      expect(dataLine(tester), l10n.moduleAiDataEmpty);
      expect(find.byKey(AiModuleKeys.delete), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(AiModuleKeys.readings),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(detail(tester, AiModuleKeys.readings), l10n.moduleAiReadingsNone);
      expect(detail(tester, AiModuleKeys.connection), 'Not connected');
      expect(factoryCalls, 0);
    });

    testWidgets('a keystore failure keeps the config and Remove, and a retry '
        'clears everything', (tester) async {
      final flaky = FlakySecretStore()
        ..values[aiApiKeySecretName] = 'sk-ab3X'
        ..failDeletes = 1;
      secrets = flaky;
      reports.reports.add(_report(at: _now));
      await pump(tester);
      await openDialog(tester);
      await tester.tap(find.byKey(AiModuleKeys.deleteConfirm));
      await tester.pumpAndSettle();

      expect(find.text(l10n.moduleAiDeleteFailed), findsOneWidget);
      expect(reports.reports, isEmpty);
      expect(configs.config, _tested());
      expect(flaky.values[aiApiKeySecretName], 'sk-ab3X');
      expect(
        dataLine(tester),
        '0 readings on this phone. Key saved, ends in ab3X.',
      );

      await openDialog(tester);
      await tester.tap(find.byKey(AiModuleKeys.deleteConfirm));
      await tester.pumpAndSettle();

      expect(find.text(l10n.moduleAiDeleted), findsOneWidget);
      expect(flaky.values, isEmpty);
      expect(configs.config, AiConfig.defaults);
      expect(dataLine(tester), l10n.moduleAiDataEmpty);
      expect(find.byKey(AiModuleKeys.delete), findsNothing);
      expect(factoryCalls, 0);
    });
  });
}
