import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/presentation/module_change.dart';
import 'package:open_ring/features/modules/presentation/modules_offer_screen.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/onboarding_app.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart';
import '../../food/food_fakes.dart';
import 'module_change_fakes.dart';

final DateTime _now = DateTime.utc(2026, 11, 10, 12);

Future<void> _pump(WidgetTester tester, SpyModuleStore store) =>
    pumpOnboardingApp(
      tester,
      at: AppPaths.onboardingModules,
      store: InMemoryOnboardingStore(completed: true),
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(),
        ...onboardingOverrides(),
        ...foodStoreOverrides(
          meals: TestMealStore(),
          camera: GatedMealCamera(),
          clock: () => _now,
        ),
        clockProvider.overrideWithValue(() => _now),
        moduleStoreProvider.overrideWithValue(store),
      ],
    );

void main() {
  group('the modules step of onboarding, Body off with Trajectory stored', () {
    testWidgets('opens the dialog and cancel stays, clears busy, writes none', (
      tester,
    ) async {
      final store = SpyModuleStore({ModuleId.body, ModuleId.trajectory});
      await _pump(tester, store);

      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.body));
      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.done));
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ModulesOfferScreen)),
      );

      expect(find.byKey(ModuleChangeKeys.confirm), findsOneWidget);
      expect(
        find.text(l10n.moduleBothOffTitle(moduleName(ModuleId.body, l10n))),
        findsOneWidget,
      );

      await tester.tap(find.byKey(ModuleChangeKeys.cancel));
      await tester.pumpAndSettle();

      expect(find.byType(ModulesOfferScreen), findsOneWidget);
      expect(find.byType(TodayScreen), findsNothing);
      expect(store.writes, isEmpty);
      expect(
        tester
            .widget<ActionButton>(find.byKey(ModulesOfferKeys.done))
            .onPressed,
        isNotNull,
      );
    });
  });
}
