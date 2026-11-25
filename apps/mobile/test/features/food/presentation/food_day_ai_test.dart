import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/meal_photo_result.dart';
import 'package:open_ring/features/food/application/food_day.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/presentation/food_day_ai.dart';
import 'package:open_ring/features/food/presentation/food_day_screen.dart';
import 'package:open_ring/features/food/presentation/meal_photo_consent_sheet.dart';
import 'package:open_ring/features/food/presentation/meal_photo_pause_card.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../application/meal_analysis_harness.dart';


const _suggestion = MealPhotoSuggestion(
  isFood: MealPhotoFlag.yes,
  kind: MealPhotoKind.main,
  protein: MealPhotoFlag.yes,
  caffeine: MealPhotoFlag.no,
  fried: MealPhotoFlag.no,
  sugaryDrink: MealPhotoFlag.no,
  veg: MealPhotoVeg.some,
  alcohol: MealPhotoAlcohol.none,
  processed: MealPhotoProcessed.notMostly,
);

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late MealQueueHarness h;

  setUp(() {
    h = MealQueueHarness()
      ..extraOverrides = [
        mealCameraProvider.overrideWithValue(FakeMealCamera()),
        // The real one arms a timer for the next food day.
        currentFoodDayProvider.overrideWithValue(
          foodDay(DateTime(2026, 11, 24, 12)),
        ),
      ];
    h.onAnalysisWrite = () =>
        h.container.read(mealAnalysisRevisionProvider.notifier).bump();
  });

  Future<int> sending(int id) async {
    final row = await h.queued(id);
    await h.analyses.markSending(row, now: h.now);
    return row;
  }

  Future<void> done(int id) async {
    final row = await sending(id);
    await h.analyses.complete(row, (
      status: MealAnalysisStatus.done,
      sent: (sha256: 'abc', width: 768, height: 576, bytes: 4100),
      suggestion: _suggestion,
      confidence: MealPhotoConfidence.medium,
      rawText: '{}',
      usage: null,
      cost: null,
      errorKind: null,
    ), now: h.now);
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 3200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: screenHost(const FoodDayScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  Future<List<int>> fourMeals() async {
    await h.start();
    final kept = await h.meal();
    final answered = await h.meal(photo: 'meal_2.jpg');
    final fresh = await h.meal(photo: 'meal_3.jpg');
    final other = await h.meal(photo: 'meal_4.jpg');
    await h.analyses.setKeepOnPhone(kept, keep: true);
    await done(answered);
    return [fresh, other];
  }

  Finder badge(int id, String state) => find.descendant(
    of: find.byKey(FoodDayAiKeys.badge(id)),
    matching: find.text(l10n.foodAiBadge(state)),
  );

  group('badges', () {
    testWidgets('a done row on an untagged meal shows Suggestions until the '
        'person tags it', (tester) async {
      await h.start();
      final id = await h.meal();
      await done(id);
      await pump(tester);

      expect(badge(id, 'suggestions'), findsOneWidget);

      final meal = (await h.meals.byId(id))!;
      final edit = MealEdit.of(meal).withPlace(MealPlace.home);
      await h.container.read(mealEditorProvider).save(meal, edit);
      await tester.pumpAndSettle();

      expect(find.byKey(FoodDayAiKeys.badge(id)), findsNothing);
    });

    testWidgets('queued, sending and failed rows show their badge', (
      tester,
    ) async {
      await h.start();
      final queued = await h.meal();
      final sent = await h.meal(photo: 'meal_2.jpg');
      final failed = await h.meal(photo: 'meal_3.jpg');
      await h.queued(queued);
      await sending(sent);
      await h.analyses.fail(await sending(failed), 'timeout', now: h.now);
      await pump(tester);

      expect(badge(queued, 'queued'), findsOneWidget);
      expect(badge(sent, 'sending'), findsOneWidget);
      expect(badge(failed, 'failed'), findsOneWidget);
    });

    test('a kept meal and a meal with no row have no badge', () {
      final meal = Meal(
        id: 1,
        at: DateTime.utc(2026, 11, 24, 12),
        offsetMinutes: 0,
        photo: 'meal_1.jpg',
        createdAt: DateTime.utc(2026, 11, 24, 12),
      );
      expect(
        foodAiBadgeState(meal, (rows: const [], keep: false), sendingId: null),
        isNull,
      );
      expect(foodAiBadgeState(meal, null, sendingId: null), isNull);
    });
  });

  group('batch', () {
    testWidgets('it counts only fresh photo meals and sends them 1 s apart', (
      tester,
    ) async {
      final fresh = await fourMeals();
      final start = tester.binding.clock.now();
      h.elapsed = () => tester.binding.clock.now().difference(start);
      await pump(tester);

      expect(find.text(l10n.foodAiBatch(2)), findsOneWidget);
      await tester.tap(find.byKey(FoodDayAiKeys.batch));
      await tester.pumpAndSettle();
      expect(find.text(l10n.foodAiBatchQueued(2)), findsOneWidget);
      await drain(tester);

      expect(h.requests, hasLength(2));
      expect(h.sentAt[1] - h.sentAt[0], aiPhotoSendSpacing);
      expect(h.maxInFlight, 1);
      for (final id in fresh) {
        expect((await h.row(id)).status, MealAnalysisStatus.done);
      }
      expect(find.byKey(FoodDayAiKeys.batch), findsNothing);
    });

    testWidgets('with one use left it queues one and says the limit stopped '
        'the rest', (tester) async {
      final fresh = await fourMeals();
      await h.markers.addPhotoUses(aiPhotoDayKey(h.now), 7);
      await pump(tester);
      await tester.tap(find.byKey(FoodDayAiKeys.batch));
      await tester.pumpAndSettle();

      expect(find.text(l10n.foodAiBatchPartial(1)), findsOneWidget);
      expect(await h.analyses.byMeal(fresh.first), hasLength(1));
      expect(await h.analyses.byMeal(fresh.last), isEmpty);
      await drain(tester);
    });

    testWidgets('a first batch with no consent asks once, not per photo', (
      tester,
    ) async {
      final fresh = await fourMeals();
      h.configStore.mealPhotoConsent = null;
      await pump(tester);
      await tester.tap(find.byKey(FoodDayAiKeys.batch));
      await tester.pumpAndSettle();

      expect(find.byKey(MealPhotoConsentKeys.sheet), findsOneWidget);
      await tester.tap(find.byKey(MealPhotoConsentKeys.tick));
      await tester.pump();
      await tester.tap(find.byKey(MealPhotoConsentKeys.proceed));
      await tester.pumpAndSettle();

      expect(find.byKey(MealPhotoConsentKeys.sheet), findsNothing);
      for (final id in fresh) {
        expect(await h.analyses.byMeal(id), hasLength(1));
      }
      expect(find.text(l10n.foodAiBatchQueued(2)), findsOneWidget);
      await drain(tester);
    });

    testWidgets('a holding pause shows its card above the button', (
      tester,
    ) async {
      await fourMeals();
      h.configStore.photoQueuePause = AiPhotoQueuePause(
        reason: AiPhotoQueuePauseReason.noCredit,
        hostKey: hostKey,
        model: photoModel,
        keyLastFour: testedConfig.keyLastFour,
        atUtcMs: 0,
      );
      await pump(tester);

      final card = tester.getTopLeft(find.byKey(MealPhotoPauseKeys.card));
      final button = tester.getTopLeft(find.byKey(FoodDayAiKeys.batch));
      expect(card.dy, lessThan(button.dy));
    });

    testWidgets('demo mode hides the button and the badges', (tester) async {
      h.demo = true;
      await fourMeals();
      await pump(tester);

      expect(find.byKey(FoodDayAiKeys.batch), findsNothing);
      expect(
        find.textContaining(l10n.foodAiBadge('suggestions')),
        findsNothing,
      );
    });

    testWidgets('with AI off the day has no button, badge or analysis text', (
      tester,
    ) async {
      h.modules = {ModuleId.food};
      final fresh = await fourMeals();
      await h.queued(fresh.first);
      await pump(tester);

      expect(find.byKey(FoodDayAiKeys.batch), findsNothing);
      expect(find.byKey(FoodDayAiKeys.badge(fresh.first)), findsNothing);
      expect(
        find.textContaining(RegExp('analy', caseSensitive: false)),
        findsNothing,
      );
    });
  });
}
