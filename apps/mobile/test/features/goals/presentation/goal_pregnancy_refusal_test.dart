import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/goals/presentation/goal_pick_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_refusal_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_setup_screen.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';

import '../../../helpers/layout_harness.dart';
import '../goal_fixtures.dart';
import '../goal_picker_harness.dart';
import '../goal_setup_harness.dart';

const _title =
    'During pregnancy and breastfeeding, the app builds no weight goal';
const _body1 =
    'You answered yes, so no weight goal was started. Only the answer and the date were kept.';
const _body2 =
    'Get fitter and Sleep better stay open. When this changes, choose Lose fat again and answer no.';
const _rule =
    'A yes to pregnancy or breastfeeding at the setup of a weight goal.';

Future<GoalSetup> _withYes({bool male = false, bool newestNo = false}) async {
  final setup = await setupPicker(
    profile: male ? maleProfile : femaleProfile,
    trendKg: 78.4,
  );
  await storeScreening(setup, soft: false);
  await storeScreening(setup, pregnant: true, day: 2);
  if (newestNo) await storeScreening(setup, pregnant: false, day: 3);
  return setup;
}

void main() {
  group('16. the pregnancy refusal', () {
    testWidgets('a newest yes shows the refusal with its copy', (tester) async {
      final setup = await _withYes();
      await pumpSetup(tester, setup, at: AppPaths.goalsRefusedPregnancy);

      expect(find.text(_title), findsOneWidget);
      expect(find.text(_body1), findsOneWidget);
      expect(find.text(_body2), findsOneWidget);
      expect(find.textContaining(_rule), findsOneWidget);
      expect(find.byType(GoalPickScreen), findsNothing);
    });

    testWidgets('the buttons lead to Get fitter and to Today', (tester) async {
      final setup = await _withYes();
      final router = await pumpSetup(
        tester,
        setup,
        at: AppPaths.goalsRefusedPregnancy,
      );

      await tapKey(tester, GoalRefusalKeys.primary);

      expect(whereIs(router), AppPaths.goalsPickWith(GoalKind.getFitter));

      router.go(AppPaths.goalsRefusedPregnancy);
      await tester.pumpAndSettle();
      await tapKey(tester, GoalRefusalKeys.secondary);

      expect(whereIs(router), '/today');
      expect(find.text(todayStub), findsOneWidget);
    });

    testWidgets('visiting it writes nothing', (tester) async {
      final setup = await _withYes();
      await pumpSetup(tester, setup, at: AppPaths.goalsRefusedPregnancy);
      await tapKey(tester, GoalRefusalKeys.secondary);

      expect(await setup.store.screenings(), hasLength(2));
      expect(await setup.store.goals(), isEmpty);
    });

    testWidgets('no stored answer shows the picker', (tester) async {
      final setup = await setupPicker();
      await storeScreening(setup, soft: false);
      await pumpSetup(tester, setup, at: AppPaths.goalsRefusedPregnancy);

      expect(find.byType(GoalPickScreen), findsOneWidget);
      expect(find.text(_title), findsNothing);
    });

    testWidgets('a newest no shows the picker', (tester) async {
      final setup = await _withYes(newestNo: true);
      await pumpSetup(tester, setup, at: AppPaths.goalsRefusedPregnancy);

      expect(find.byType(GoalPickScreen), findsOneWidget);
      expect(find.text(_title), findsNothing);
    });

    testWidgets('Goals off is an empty page', (tester) async {
      final setup = await setupPicker(modules: const {ModuleId.body});
      await storeScreening(setup, pregnant: true);
      await pumpSetup(tester, setup, at: AppPaths.goalsRefusedPregnancy);

      expect(find.text(_title), findsNothing);
      expect(find.byType(GoalPickScreen), findsNothing);
    });

    testWidgets('a male with a stored yes can come back and start', (
      tester,
    ) async {
      final setup = await _withYes(male: true);
      final router = await pumpSetup(
        tester,
        setup,
        at: AppPaths.goalsRefusedPregnancy,
      );
      expect(find.text(_title), findsOneWidget);

      router.go(AppPaths.goalsPickWith(GoalKind.loseFat));
      await tester.pumpAndSettle();
      await tapKey(tester, GoalPickKeys.continueButton);

      expect(whereIs(router), AppPaths.goalsSetup);
      expect(find.byKey(GoalSetupKeys.pregnancyNo), findsOneWidget);
      expect(find.byKey(GoalSetupKeys.start), findsNothing);

      await tapKey(tester, GoalSetupKeys.pregnancyNo);
      await tapKey(tester, GoalSetupKeys.start);

      expect(whereIs(router), '/today');
      expect(await setup.store.goals(), hasLength(1));
      final rows = await setup.store.screenings();
      expect(rows.first.pregnantOrBreastfeeding, isFalse);
    });

    testWidgets('a second yes from the setup adds one more row, no goal', (
      tester,
    ) async {
      final setup = await _withYes();
      final router = await pumpSetup(tester, setup);

      await tapKey(tester, GoalSetupKeys.pregnancyYes);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      final rows = await setup.store.screenings();
      expect(
        rows.where((r) => r.pregnantOrBreastfeeding == true),
        hasLength(2),
      );
      expect(await setup.store.goals(), isEmpty);
      expect(whereIs(router), AppPaths.goalsRefusedPregnancy);
    });
  });

  group('17. layout of the refusal', () {
    for (final scale in layoutScales) {
      for (final brightness in layoutBrightnesses) {
        testWidgets('pregnancy at ${scale}x ${brightness.name}', (
          tester,
        ) async {
          final setup = await _withYes();
          await pumpSetup(
            tester,
            setup,
            at: AppPaths.goalsRefusedPregnancy,
            scale: scale,
            brightness: brightness,
            tall: false,
          );

          await expectNoLayoutOverflow(() async {
            await tester.scrollUntilVisible(
              find.byKey(GoalRefusalKeys.secondary),
              200,
              maxScrolls: 200,
            );
          });

          expect(find.text(_title), findsOneWidget);
          final size = tester.getSize(find.byKey(GoalRefusalKeys.primary));
          expect(size.height, greaterThanOrEqualTo(48));
        });
      }
    }
  });
}
