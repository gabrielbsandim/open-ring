import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/open_score/presentation/day_score_formula_screen.dart';
import 'package:open_ring/features/open_score/presentation/day_score_receipt_screen.dart';
import 'package:open_ring/features/open_score/presentation/open_score_module_screen.dart';

import '../helpers/ble_fakes.dart';
import '../helpers/onboarding_app.dart';
import '../helpers/onboarding_fakes.dart';
import '../helpers/ring_fakes.dart';

String _iso(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

String _dayLabel(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(DayScoreReceiptKeys.day)).data!;

void main() {
  testWidgets('back from the formula returns to the Open Score module screen', (
    tester,
  ) async {
    final container = await pumpOnboardingApp(
      tester,
      store: InMemoryOnboardingStore(completed: true),
      at: AppPaths.settingsModuleOpenScore,
    );

    await tapAndSettle(tester, find.byKey(OpenScoreModuleKeys.formula));
    expect(find.byType(DayScoreFormulaScreen), findsOneWidget);

    container.read(appRouterProvider).pop();
    await tester.pumpAndSettle();

    expect(find.byType(OpenScoreModuleScreen), findsOneWidget);
    expect(find.byType(DayScoreReceiptScreen), findsNothing);
  });

  testWidgets('back from the formula returns to the receipt of the same day', (
    tester,
  ) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final container = await pumpOnboardingApp(
      tester,
      store: InMemoryOnboardingStore(completed: true),
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(),
        ...onboardingOverrides(),
        moduleStoreProvider.overrideWithValue(
          InMemoryModuleStore({ModuleId.openScore}),
        ),
      ],
    );
    final today = await _open(tester, container, AppPaths.dayScore);
    final past = await _open(
      tester,
      container,
      AppPaths.dayScoreOn(_iso(yesterday)),
    );
    expect(past, isNot(today));

    final link = find.byKey(DayScoreReceiptKeys.formula);
    await tester.scrollUntilVisible(
      link,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    // Centred, so the tab bar at the bottom does not take the tap.
    await Scrollable.ensureVisible(tester.element(link), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(DayScoreFormulaScreen), findsOneWidget);

    container.read(appRouterProvider).pop();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(DayScoreReceiptKeys.day),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(_dayLabel(tester), past);
  });
}

Future<String> _open(
  WidgetTester tester,
  ProviderContainer container,
  String location,
) async {
  container.read(appRouterProvider).go(location);
  await tester.pumpAndSettle();
  return _dayLabel(tester);
}
