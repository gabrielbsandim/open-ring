import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_run_state.dart';
import 'package:open_ring/features/ai/domain/meal_photo_result.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/presentation/ai_failure_message.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/food/application/meal_analysis_view.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/presentation/food_meal_screen.dart';
import 'package:open_ring/features/food/presentation/meal_analysis_section.dart';
import 'package:open_ring/features/food/presentation/meal_keep_switch.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../application/meal_analysis_harness.dart';

const _host = 'api.example.com';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late MealQueueHarness h;
  late int mealId;

  setUp(() {
    h = MealQueueHarness();
    h.onAnalysisWrite = () =>
        h.container.read(mealAnalysisRevisionProvider.notifier).bump();
  });

  Future<void> pump(
    WidgetTester tester, {
    Future<void> Function(int mealId)? seed,
    Widget Function(int mealId)? screen,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 2400);
    addTearDown(tester.view.reset);
    await h.start();
    mealId = await h.meal();
    await seed?.call(mealId);
    final body =
        screen?.call(mealId) ??
        Scaffold(
          body: ListView(children: [MealAnalysisSection(mealId: mealId)]),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: screenHost(body),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<int> queued(int id) => h.queued(id);

  Future<int> sending(int id) async {
    final row = await h.queued(id);
    await h.analyses.markSending(row, now: h.now);
    return row;
  }

  Future<void> answered(
    int id,
    MealAnalysisStatus status, {
    String? errorKind,
  }) async {
    final row = await sending(id);
    await h.analyses.complete(row, (
      status: status,
      sent: (sha256: 'abc', width: 768, height: 576, bytes: 4100),
      suggestion: null,
      confidence: MealPhotoConfidence.medium,
      rawText: '{}',
      usage: null,
      cost: null,
      errorKind: errorKind,
    ), now: h.now);
  }

  Future<int> failed(int id, String kind) async {
    final row = await sending(id);
    await h.analyses.fail(row, kind, now: h.now);
    return row;
  }

  Future<int> skipped(int id, String reason) async {
    final row = await h.queued(id);
    await h.analyses.skip(row, reason, now: h.now);
    return row;
  }

  void expectView(MealAnalysisViewKind kind, String text) {
    expect(find.byKey(MealAnalysisKeys.view(kind)), findsOneWidget);
    expect(find.text(text), findsOneWidget, reason: text);
  }

  group('states', () {
    testWidgets('none offers Analyze and the keep switch under the host', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text(l10n.foodAiSectionTitle), findsOneWidget);
      expect(find.text(_host), findsOneWidget);
      expectView(MealAnalysisViewKind.none, l10n.foodAiIntro);
      expect(find.byKey(MealAnalysisKeys.analyze), findsOneWidget);
      expect(find.byKey(MealAiKeys.keep), findsOneWidget);
    });

    testWidgets('kept shows its line and the switch, without Analyze', (
      tester,
    ) async {
      await pump(
        tester,
        seed: (id) => h.analyses.setKeepOnPhone(id, keep: true),
      );

      expectView(MealAnalysisViewKind.kept, l10n.foodAiKept);
      expect(find.byKey(MealAiKeys.keep), findsOneWidget);
      expect(find.byKey(MealAnalysisKeys.analyze), findsNothing);
    });

    testWidgets('queued waits with Cancel', (tester) async {
      await pump(tester, seed: queued);

      expectView(MealAnalysisViewKind.queued, l10n.foodAiWaiting);
      expect(find.byKey(MealAnalysisKeys.cancel), findsOneWidget);
      expect(find.byKey(MealAnalysisKeys.ceiling), findsNothing);
    });

    testWidgets('queued under a reached monthly cap adds the cap line', (
      tester,
    ) async {
      h.configStore.config = testedConfig.copyWith(monthlyTokenCap: 1000);
      await h.markers.addMonthTokens(aiMonthKey(h.now), 1500);
      await pump(
        tester,
        seed: (id) async {
          await queued(id);
          await h.queue.drain();
        },
      );

      expect(h.requests, isEmpty);
      expectView(MealAnalysisViewKind.queued, l10n.foodAiWaiting);
      expect(find.text(l10n.aiErrorCeiling(1500, 1000)), findsOneWidget);
    });

    for (final reason in AiPhotoQueuePauseReason.values) {
      testWidgets('paused for ${reason.name} links the photo settings', (
        tester,
      ) async {
        h.configStore.photoQueuePause = AiPhotoQueuePause(
          reason: reason,
          hostKey: hostKey,
          model: photoModel,
          keyLastFour: testedConfig.keyLastFour,
          atUtcMs: 0,
        );
        await pump(tester, seed: queued);

        expectView(MealAnalysisViewKind.paused, l10n.foodAiPaused(reason.name));
        expect(find.byKey(MealAnalysisKeys.link), findsOneWidget);
      });
    }

    testWidgets('sending names the host, with Cancel and the billing line', (
      tester,
    ) async {
      await pump(tester, seed: sending);

      expectView(MealAnalysisViewKind.sending, l10n.foodAiSending(_host));
      expect(find.byKey(MealAnalysisKeys.cancel), findsOneWidget);
      expect(find.text(l10n.foodAiMayBill), findsOneWidget);
    });

    testWidgets('done names the model, the date and a medium confidence', (
      tester,
    ) async {
      await pump(tester, seed: (id) => answered(id, MealAnalysisStatus.done));

      final date = const DefaultMaterialLocalizations().formatMediumDate(h.now);
      expectView(
        MealAnalysisViewKind.done,
        l10n.foodAiBy(photoModel, date, l10n.aiConfidenceLevel('medium')),
      );
    });

    testWidgets('notFood says the meal did not change', (tester) async {
      await pump(
        tester,
        seed: (id) => answered(id, MealAnalysisStatus.notFood),
      );

      expectView(MealAnalysisViewKind.notFood, l10n.foodAiNotFood);
    });

    testWidgets('rejected offers Try again', (tester) async {
      await pump(
        tester,
        seed: (id) =>
            answered(id, MealAnalysisStatus.rejected, errorKind: 'schema'),
      );

      expectView(MealAnalysisViewKind.rejected, l10n.foodAiRejected);
      expect(find.byKey(MealAnalysisKeys.retry), findsOneWidget);
    });

    String a9(AnalysisFailureKind kind) => aiFailureMessage(
      l10n,
      RunModelFailure(AnalysisFailure(kind: kind)),
      testedConfig.copyWith(model: photoModel),
    )!;

    final failures = {
      'unauthorized': a9(AnalysisFailureKind.unauthorized),
      'timeout': a9(AnalysisFailureKind.timeout),
      'cancelled': l10n.foodAiStopped('cancelled'),
      'interrupted': l10n.foodAiStopped('interrupted'),
      'unexpected': l10n.foodAiStopped('other'),
    };
    for (final MapEntry(key: kind, value: line) in failures.entries) {
      testWidgets('failed with $kind reads its line and offers Try again', (
        tester,
      ) async {
        await pump(tester, seed: (id) => failed(id, kind));

        expectView(MealAnalysisViewKind.failed, line);
        expect(find.byKey(MealAnalysisKeys.retry), findsOneWidget);
      });
    }

    const skips = {
      MealAnalysisErrorKind.expired: 'expired',
      MealAnalysisErrorKind.keptOnPhone: 'keptOnPhone',
      MealAnalysisErrorKind.noConsent: 'noConsent',
      MealAnalysisErrorKind.photoMissing: 'photoMissing',
      MealAnalysisErrorKind.targetChanged: 'targetChanged',
      MealAnalysisErrorKind.urlRejected: 'urlRejected',
    };
    for (final MapEntry(key: kind, value: reason) in skips.entries) {
      testWidgets('skipped as $kind reads its line and offers Analyze again', (
        tester,
      ) async {
        await pump(tester, seed: (id) => skipped(id, kind));

        expectView(MealAnalysisViewKind.skipped, l10n.foodAiSkipped(reason));
        expect(find.byKey(MealAnalysisKeys.again), findsOneWidget);
      });
    }
  });

  group('closed gate', () {
    final cases =
        <String, (void Function(), String Function(AppLocalizations))>{
          'vision unknown': (
            () => h.configStore.profiles.clear(),
            (l) => l.aiPhotosVisionState('unknown', photoModel),
          ),
          'vision no': (
            () =>
                h.configStore.profiles[aiCapabilityProfileKey(
                  hostKey,
                  photoModel,
                )] = const AiCapabilityProfile(
                  vision: AiVisionSupport.no,
                ),
            (l) => l.foodAiProbeTextOnly(photoModel),
          ),
          'no key': (
            () => h.secrets.values.remove(aiApiKeySecretName),
            (l) => l.foodAiUnavailable,
          ),
        };
    for (final MapEntry(key: name, value: (close, line)) in cases.entries) {
      testWidgets('a queued row with $name says so, not that it goes', (
        tester,
      ) async {
        close();
        await pump(tester, seed: queued);
        await h.queue.drain();
        await tester.pumpAndSettle();

        expect(find.text(l10n.foodAiWaiting), findsNothing);
        expectView(MealAnalysisViewKind.closed, line(l10n));
        expect(find.byKey(MealAnalysisKeys.link), findsOneWidget);
        expect(h.requests, isEmpty);
        expect((await h.row(mealId)).status, MealAnalysisStatus.queued);
      });
    }
  });

  group('taps', () {
    testWidgets('Try again on rejected requeues without a new daily use', (
      tester,
    ) async {
      await pump(
        tester,
        seed: (id) =>
            answered(id, MealAnalysisStatus.rejected, errorKind: 'schema'),
      );
      final day = aiPhotoDayKey(h.now);
      final uses = await h.markers.photoUses(day);
      h.queue.toBackground();
      await tester.tap(find.byKey(MealAnalysisKeys.retry));
      await tester.pumpAndSettle();

      expect((await h.row(mealId)).status, MealAnalysisStatus.queued);
      expect(await h.markers.photoUses(day), uses);
      expect(h.requests, isEmpty);
    });

    testWidgets('Cancel on queued skips the row, which reads as none', (
      tester,
    ) async {
      late int row;
      await pump(tester, seed: (id) async => row = await queued(id));
      await tester.tap(find.byKey(MealAnalysisKeys.cancel));
      await tester.pumpAndSettle();

      final stored = (await h.analyses.byId(row))!;
      expect(
        (stored.status, stored.errorKind),
        (MealAnalysisStatus.skipped, MealAnalysisErrorKind.cancelled),
      );
      expectView(MealAnalysisViewKind.none, l10n.foodAiIntro);
    });

    testWidgets('Cancel on sending aborts the request and the row fails as '
        'cancelled', (tester) async {
      final never = Completer<AnalysisEvent>();
      h.respond = () => never.future;
      await pump(tester);
      unawaited(h.queue.enqueue(mealId));
      await tester.pumpAndSettle();
      expect(h.requests, hasLength(1));
      expect(
        find.byKey(MealAnalysisKeys.view(MealAnalysisViewKind.sending)),
        findsOneWidget,
      );

      await tester.tap(find.byKey(MealAnalysisKeys.cancel));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));

      final row = await h.row(mealId);
      expect(
        (row.status, row.errorKind),
        (MealAnalysisStatus.failed, MealAnalysisErrorKind.cancelled),
      );
      expectView(MealAnalysisViewKind.failed, l10n.foodAiStopped('cancelled'));
    });

    testWidgets('Try again on failed resends without a new daily use', (
      tester,
    ) async {
      await pump(tester, seed: (id) => failed(id, 'timeout'));
      final day = aiPhotoDayKey(h.now);
      final uses = await h.markers.photoUses(day);
      await tester.tap(find.byKey(MealAnalysisKeys.retry));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));

      expect(h.requests, hasLength(1));
      expect(await h.markers.photoUses(day), uses);
      expect((await h.row(mealId)).status, MealAnalysisStatus.done);
    });

    testWidgets('Analyze again on an expired skip goes through the Analyze '
        'flow', (tester) async {
      await pump(
        tester,
        seed: (id) => skipped(id, MealAnalysisErrorKind.expired),
      );
      final day = aiPhotoDayKey(h.now);
      await tester.tap(find.byKey(MealAnalysisKeys.again));
      await tester.pumpAndSettle();

      expect(find.text(l10n.foodAiQueued), findsOneWidget);
      expect(await h.markers.photoUses(day), 1);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  testWidgets('demo shows the read only sample, writes nothing and sends '
      'nothing', (tester) async {
    h.demo = true;
    await pump(tester);

    expectView(MealAnalysisViewKind.demo, l10n.aiSampleSummary);
    for (final tag in [l10n.foodKindMain, l10n.foodProtein, l10n.foodVegSome]) {
      expect(
        find.descendant(
          of: find.byKey(MealAnalysisKeys.sample),
          matching: find.text(tag),
        ),
        findsOneWidget,
      );
    }
    expect(find.byKey(MealAnalysisKeys.analyze), findsNothing);
    expect(find.byKey(MealAiKeys.keep), findsNothing);
    final before = await h.meals.byId(mealId);
    await tester.tap(find.text(l10n.foodProtein));
    await tester.pumpAndSettle();

    expect(await h.meals.byId(mealId), before);
    expect(await h.analyses.byMeal(mealId), isEmpty);
    expect(h.requests, isEmpty);
  });

  group('meal screen', () {
    testWidgets('a meal without a photo has no section', (tester) async {
      await pump(tester, screen: (_) => const SizedBox.shrink());
      final bare = await h.meals.add(
        MealDraft(at: h.now, offsetMinutes: -180),
        now: h.now,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: screenHost(FoodMealScreen(mealId: bare.id)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(FoodMealKeys.noPhoto), findsOneWidget);
      expect(find.byKey(MealAnalysisKeys.section), findsNothing);
    });

    testWidgets('with AI off it has no section and no analysis text', (
      tester,
    ) async {
      h.modules = {ModuleId.food};
      await pump(tester, screen: (id) => FoodMealScreen(mealId: id));

      expect(find.byKey(FoodMealKeys.timeTile), findsOneWidget);
      expect(find.byKey(MealAnalysisKeys.section), findsNothing);
      expect(
        find.textContaining(RegExp('analy', caseSensitive: false)),
        findsNothing,
      );
    });

    testWidgets('with AI and Food on it shows the section for a photo', (
      tester,
    ) async {
      await pump(tester, screen: (id) => FoodMealScreen(mealId: id));

      expect(find.byKey(MealAnalysisKeys.section), findsOneWidget);
    });
  });
}
