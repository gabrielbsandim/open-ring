import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/presentation/ai_photo_settings_screen.dart';
import 'package:open_ring/features/ai/presentation/ai_vision_test_card.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/presentation/meal_photo_pause_card.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../application/meal_analysis_harness.dart';

AiPhotoQueuePause _pause(
  AiPhotoQueuePauseReason reason, {
  String? keyLastFour,
}) => AiPhotoQueuePause(
  reason: reason,
  hostKey: hostKey,
  model: photoModel,
  keyLastFour: keyLastFour ?? testedConfig.keyLastFour,
  atUtcMs: 0,
);

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late MealQueueHarness h;
  late List<int> meals;

  setUp(() {
    h = MealQueueHarness();
    h.onAnalysisWrite = () =>
        h.container.read(mealAnalysisRevisionProvider.notifier).bump();
  });

  Future<void> pump(WidgetTester tester, {int queued = 3}) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 2400);
    addTearDown(tester.view.reset);
    await h.start();
    meals = [
      for (var i = 1; i <= queued; i++) await h.meal(photo: 'meal_$i.jpg'),
    ];
    for (final id in meals) {
      await h.queued(id);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: screenHost(const AiPhotoSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a 401 pause with 3 queued photos reads the count, the key '
      'line and Resume (sends 3 photos)', (tester) async {
    h.configStore.photoQueuePause = _pause(
      AiPhotoQueuePauseReason.unauthorized,
    );
    await pump(tester);

    expect(find.byKey(MealPhotoPauseKeys.card), findsOneWidget);
    expect(find.text(l10n.aiPhotosPausedTitle(3)), findsOneWidget);
    expect(find.text('3 photos waiting. The queue is paused.'), findsOneWidget);
    expect(find.text(l10n.aiPhotosPausedBody), findsOneWidget);
    expect(find.text(l10n.aiErrorKey), findsOneWidget);
    expect(find.text('Resume (sends 3 photos)'), findsOneWidget);
    expect(find.text(l10n.aiGuideOpen), findsOneWidget);
    expect(find.text(l10n.aiPhotosExpiry), findsOneWidget);
    expect(find.byKey(MealPhotoPauseKeys.test), findsNothing);
  });

  testWidgets('Resume sends the 3 rows 1 s apart and the card leaves', (
    tester,
  ) async {
    h.configStore.photoQueuePause = _pause(
      AiPhotoQueuePauseReason.unauthorized,
    );
    final start = tester.binding.clock.now();
    h.elapsed = () => tester.binding.clock.now().difference(start);
    await pump(tester);
    final tapped = tester.binding.clock.now().difference(start);

    await tester.tap(find.byKey(MealPhotoPauseKeys.resume));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(h.sentAt.map((t) => t - tapped), [
      Duration.zero,
      aiPhotoSendSpacing,
      aiPhotoSendSpacing * 2,
    ]);
    expect(h.maxInFlight, 1);
    for (final id in meals) {
      expect((await h.row(id)).status, MealAnalysisStatus.done);
    }
    expect(h.configStore.photoQueuePause, isNull);
    expect(find.byKey(MealPhotoPauseKeys.card), findsNothing);
  });

  for (final (reason, line) in [
    (AiPhotoQueuePauseReason.noCredit, l10n.aiErrorNoCredit),
    (AiPhotoQueuePauseReason.forbidden, l10n.aiErrorForbidden(photoModel)),
  ]) {
    testWidgets('a ${reason.name} pause shows its reason and Resume', (
      tester,
    ) async {
      h.configStore.photoQueuePause = _pause(reason);
      await pump(tester, queued: 1);

      expect(find.text(line), findsOneWidget);
      expect(find.text('Resume (sends 1 photo)'), findsOneWidget);
    });
  }

  testWidgets('a noVision pause offers the photo test instead of Resume', (
    tester,
  ) async {
    h.configStore.photoQueuePause = _pause(AiPhotoQueuePauseReason.noVision);
    await pump(tester);

    expect(
      find.text(l10n.aiPhotosVisionState('no', photoModel)),
      findsOneWidget,
    );
    expect(find.byKey(MealPhotoPauseKeys.resume), findsNothing);
    expect(find.byType(AiVisionTestCard), findsNothing);
    await tester.tap(find.byKey(MealPhotoPauseKeys.test));
    await tester.pumpAndSettle();

    expect(find.byType(AiVisionTestCard), findsOneWidget);
    expect(h.requests, isEmpty);
  });

  testWidgets('a row the next pass would skip is not counted for Resume', (
    tester,
  ) async {
    h.configStore.photoQueuePause = _pause(AiPhotoQueuePauseReason.noCredit);
    await pump(tester, queued: 0);
    final old = await h.meal(photo: 'meal_old.jpg');
    await h.queued(old, at: h.now.subtract(const Duration(days: 8)));
    final other = await h.meal(photo: 'meal_other.jpg');
    await h.queued(
      other,
      target: (
        providerHost: hostKey,
        model: 'text-m',
        promptVersion: photoTarget.promptVersion,
        outputSchema: photoTarget.outputSchema,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.aiPhotosPausedTitle(0)), findsOneWidget);
    expect(find.text(l10n.aiPhotosResume(0)), findsOneWidget);
    expect(find.text('Resume (sends 1 photo)'), findsNothing);

    await h.queued(await h.meal(photo: 'meal_new.jpg'));
    await tester.pumpAndSettle();

    expect(find.text('Resume (sends 1 photo)'), findsOneWidget);
  });

  testWidgets('with no pause the card is absent', (tester) async {
    await pump(tester);

    expect(find.byKey(MealPhotoPauseKeys.card), findsNothing);
  });

  testWidgets('a pause for another key is stale and the card is absent', (
    tester,
  ) async {
    h.configStore.photoQueuePause = _pause(
      AiPhotoQueuePauseReason.unauthorized,
      keyLastFour: '9999',
    );
    await pump(tester);

    expect(find.byKey(MealPhotoPauseKeys.card), findsNothing);
  });
}
