import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/features/ai/application/vision_probe_controller.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/vision_probe.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/presentation/meal_analyze_flow.dart';
import 'package:open_ring/features/food/presentation/meal_photo_consent_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../application/meal_analysis_harness.dart';

const _seed = 11;

String _probeAnswer() => jsonEncode({
  for (final (i, c) in VisionProbeGrid.random(Random(_seed)).cells.indexed)
    visionProbeCellNames[i]: c.name,
});

AnalysisEvent _says(String text) => AnalysisCompleted(
  text: text,
  finishReason: 'stop',
  usage: const AiTokenUsage(promptTokens: 30, completionTokens: 5),
);

class _Analyze extends ConsumerWidget {
  const new(this.ids);

  final List<int> Function() ids;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: TextButton(
        key: const Key('analyze'),
        onPressed: () => unawaited(analyzeMealPhotos(context, ref, ids())),
        child: const Text('analyze'),
      ),
    ),
  );
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late MealQueueHarness h;
  late List<int> ids;

  setUp(() {
    h = MealQueueHarness()
      ..extraOverrides = [
        visionProbeRandomProvider.overrideWith((_) => Random(_seed)),
      ];
    h.respond = () => h.requests.last.schemaName == visionProbeSchemaName
        ? _says(_probeAnswer())
        : completed();
    ids = [];
  });

  List<String> sentKinds() => [
    for (final r in h.requests)
      if (r.schemaName == visionProbeSchemaName) 'probe' else 'photo',
  ];

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 2400);
    addTearDown(tester.view.reset);
    await h.start();
    ids = [await h.meal()];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: screenHost(_Analyze(() => ids)),
      ),
    );
  }

  Future<void> pumpRouted(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 2400);
    addTearDown(tester.view.reset);
    await h.start();
    ids = [await h.meal()];
    Widget page(String text) => Scaffold(body: Text(text));
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => _Analyze(() => ids)),
        GoRoute(
          path: AppPaths.settingsAiConnection,
          builder: (_, _) => page('connection page'),
        ),
        GoRoute(
          path: AppPaths.settingsAiPhotos,
          builder: (_, _) => page('photos page'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> analyze(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('analyze')));
    await tester.pumpAndSettle();
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  testWidgets('a first Analyze asks consent, probes, then sends the photo', (
    tester,
  ) async {
    h.configStore
      ..mealPhotoConsent = null
      ..profiles.clear();
    await pump(tester);
    await analyze(tester);

    expect(find.byKey(MealPhotoConsentKeys.sheet), findsOneWidget);
    final proceed = find.byKey(MealPhotoConsentKeys.proceed);
    expect(tester.widget<FilledButton>(proceed).onPressed, isNull);
    await tester.tap(find.byKey(MealPhotoConsentKeys.tick));
    await tester.pump();
    await tester.tap(proceed);
    await tester.pumpAndSettle();
    await drain(tester);

    final consent = await h.configStore.readMealPhotoConsent();
    expect(consent?.hostKey, hostKey);
    expect(consent?.policyEffectiveDate, aiCurrentPolicyEffectiveDate);
    expect(find.byKey(MealPhotoConsentKeys.sheet), findsNothing);
    expect(sentKinds(), ['probe', 'photo']);
    expect((await h.row(ids.single)).status, MealAnalysisStatus.done);
    expect(find.text(l10n.foodAiQueued), findsOneWidget);
  });

  testWidgets('a stored consent with an untested model opens on the probe', (
    tester,
  ) async {
    h.configStore.profiles.clear();
    await pump(tester);
    await analyze(tester);
    await drain(tester);

    expect(find.byKey(MealPhotoConsentKeys.tick), findsNothing);
    expect(sentKinds(), ['probe', 'photo']);
  });

  testWidgets('Cancel on the consent step stores and sends nothing', (
    tester,
  ) async {
    h.configStore
      ..mealPhotoConsent = null
      ..profiles.clear();
    await pump(tester);
    await analyze(tester);
    await tester.tap(find.byKey(MealPhotoConsentKeys.cancel));
    await tester.pumpAndSettle();

    expect(await h.configStore.readMealPhotoConsent(), isNull);
    expect(h.requests, isEmpty);
    expect(await h.analyses.byMeal(ids.single), isEmpty);
  });

  testWidgets('Cancel during the probe keeps the consent and sends no photo', (
    tester,
  ) async {
    h.configStore
      ..mealPhotoConsent = null
      ..profiles.clear();
    final never = Completer<AnalysisEvent>();
    h.respond = () => never.future;
    await pump(tester);
    await analyze(tester);
    await tester.tap(find.byKey(MealPhotoConsentKeys.tick));
    await tester.pump();
    await tester.tap(find.byKey(MealPhotoConsentKeys.proceed));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(MealPhotoConsentKeys.probing), findsOneWidget);
    await tester.tap(find.byKey(MealPhotoConsentKeys.cancel));
    await tester.pumpAndSettle();

    expect(await h.configStore.readMealPhotoConsent(), isNotNull);
    expect(sentKinds(), ['probe']);
    expect(await h.analyses.byMeal(ids.single), isEmpty);
  });

  testWidgets('a stored vision no never opens the consent sheet', (
    tester,
  ) async {
    h.configStore
      ..mealPhotoConsent = null
      ..profiles[aiCapabilityProfileKey(hostKey, photoModel)] =
          const AiCapabilityProfile(vision: AiVisionSupport.no);
    await pump(tester);
    await analyze(tester);

    expect(find.byKey(MealPhotoConsentKeys.sheet), findsNothing);
    expect(find.text(l10n.foodAiProbeTextOnly(photoModel)), findsOneWidget);
    expect(h.requests, isEmpty);
    expect(await h.analyses.byMeal(ids.single), isEmpty);
  });

  testWidgets('with the daily limit used, Analyze shows the limit and writes '
      'no row', (tester) async {
    await h.markers.addPhotoUses(aiPhotoDayKey(h.now), 8);
    await pump(tester);
    await analyze(tester);

    expect(find.text(l10n.foodAiLimit(8)), findsOneWidget);
    expect(await h.analyses.byMeal(ids.single), isEmpty);
    expect(h.requests, isEmpty);
  });

  testWidgets('an untested connection points to the connection', (
    tester,
  ) async {
    h.configStore.config = testedConfig.copyWith(clearTested: true);
    await pump(tester);
    await analyze(tester);

    expect(find.text(l10n.foodAiUnavailable), findsOneWidget);
    expect(h.requests, isEmpty);
  });

  testWidgets('a batch runs the sheet once and stops at the daily limit', (
    tester,
  ) async {
    h.configStore
      ..mealPhotoConsent = null
      ..profiles.clear()
      ..config = testedConfig.copyWith(photoDailyLimit: 2);
    await pump(tester);
    ids = [
      ...ids,
      await h.meal(photo: 'meal_2.jpg'),
      await h.meal(photo: 'meal_3.jpg'),
    ];
    await analyze(tester);
    await tester.tap(find.byKey(MealPhotoConsentKeys.tick));
    await tester.pump();
    await tester.tap(find.byKey(MealPhotoConsentKeys.proceed));
    await tester.pumpAndSettle();
    expect(find.text(l10n.foodAiBatchPartial(2)), findsOneWidget);
    await drain(tester);
    await drain(tester);

    expect(sentKinds(), ['probe', 'photo', 'photo']);
    expect(await h.analyses.byMeal(ids.last), isEmpty);
  });

  group('the links go to their screens', () {
    testWidgets('Open the connection from the unavailable line', (
      tester,
    ) async {
      h.configStore.config = testedConfig.copyWith(clearTested: true);
      await pumpRouted(tester);
      await analyze(tester);
      await tester.tap(find.text(l10n.aiGuideOpen));
      await tester.pumpAndSettle();

      expect(find.text('connection page'), findsOneWidget);
    });

    testWidgets('Open the photo settings from the text only line', (
      tester,
    ) async {
      h.configStore.profiles[aiCapabilityProfileKey(hostKey, photoModel)] =
          const AiCapabilityProfile(vision: AiVisionSupport.no);
      await pumpRouted(tester);
      await analyze(tester);
      await tester.tap(find.text(l10n.foodAiOpenPhotos));
      await tester.pumpAndSettle();

      expect(find.text('photos page'), findsOneWidget);
    });

    testWidgets('Open the photo settings from the sheet after a failed probe', (
      tester,
    ) async {
      h.configStore.profiles.clear();
      h.respond = () => _says(
        jsonEncode({for (final name in visionProbeCellNames) name: 'black'}),
      );
      await pumpRouted(tester);
      await analyze(tester);
      await tester.tap(find.byKey(MealPhotoConsentKeys.photos));
      await tester.pumpAndSettle();

      expect(find.byKey(MealPhotoConsentKeys.sheet), findsNothing);
      expect(find.text('photos page'), findsOneWidget);
      expect(await h.analyses.byMeal(ids.single), isEmpty);
    });
  });
}
