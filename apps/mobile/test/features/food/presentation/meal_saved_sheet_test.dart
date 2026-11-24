import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/food/application/meal_photo_saver.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/presentation/meal_keep_switch.dart';
import 'package:open_ring/features/food/presentation/meal_saved_sheet.dart';

import '../../../helpers/layout_harness.dart';
import '../application/meal_analysis_harness.dart';

class _Open extends StatelessWidget {
  const new(this.sheet, this.closed);

  final Widget sheet;
  final ValueChanged<MealSavedAction?> closed;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        key: const Key('open'),
        onPressed: () async => closed(
          await showModalBottomSheet<MealSavedAction>(
            context: context,
            isScrollControlled: true,
            builder: (_) => sheet,
          ),
        ),
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  late MealQueueHarness h;
  late int mealId;
  late List<MealSavedAction?> closed;

  setUp(() {
    h = MealQueueHarness();
    h.onAnalysisWrite = () =>
        h.container.read(mealAnalysisRevisionProvider.notifier).bump();
    closed = [];
  });

  Future<void> open(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 2400);
    addTearDown(tester.view.reset);
    await h.start();
    mealId = await h.meal();
    final meal = (await h.meals.byId(mealId))!;
    final edit = ValueNotifier(MealEdit.of(meal));
    addTearDown(edit.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: screenHost(
          _Open(
            MealSavedSheet(
              meal: meal,
              time: TimeSource.returned,
              recovered: false,
              today: foodDay(h.now),
              edit: edit,
              ai: MealSavedAiSlot(mealId: mealId),
            ),
            closed.add,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  bool keepEnabled(WidgetTester tester) =>
      tester.widget<SwitchListTile>(find.byKey(MealAiKeys.keep)).onChanged !=
      null;

  testWidgets('Analyze closes the sheet with the analyze action', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(MealAiKeys.analyze));
    await tester.pumpAndSettle();

    expect(find.byType(MealSavedSheet), findsNothing);
    expect(closed, [MealSavedAction.analyze]);
  });

  testWidgets('keep on is stored and hides Analyze', (tester) async {
    await open(tester);
    expect(find.byKey(MealAiKeys.analyze), findsOneWidget);
    await tester.tap(find.byKey(MealAiKeys.keep));
    await tester.pumpAndSettle();

    expect(await h.analyses.keepOnPhone(mealId), isTrue);
    expect(find.byKey(MealAiKeys.analyze), findsNothing);
    await tester.tap(find.byKey(MealAiKeys.keep));
    await tester.pumpAndSettle();
    expect(await h.analyses.keepOnPhone(mealId), isFalse);
    expect(find.byKey(MealAiKeys.analyze), findsOneWidget);
    expect(await h.analyses.byMeal(mealId), isEmpty);
  });

  testWidgets('keep on cancels a queued row and gives the use back', (
    tester,
  ) async {
    await open(tester);
    final day = aiPhotoDayKey(h.now);
    final row = await h.queued(mealId);
    await h.markers.addPhotoUses(day, 1);
    await tester.tap(find.byKey(MealAiKeys.keep));
    await tester.pumpAndSettle();

    final skipped = (await h.analyses.byId(row))!;
    expect(skipped.status, MealAnalysisStatus.skipped);
    expect(skipped.errorKind, MealAnalysisErrorKind.cancelled);
    expect(await h.markers.photoUses(day), 0);
  });

  testWidgets('the switch is off while the photo is being sent', (
    tester,
  ) async {
    await open(tester);
    expect(keepEnabled(tester), isTrue);
    final gate = h.analyses.markGate = Completer<void>();
    await h.queued(mealId);
    unawaited(h.queue.drain());
    await tester.pump();
    await tester.pump();

    expect(keepEnabled(tester), isFalse);
    gate.complete();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(keepEnabled(tester), isTrue);
  });
}
