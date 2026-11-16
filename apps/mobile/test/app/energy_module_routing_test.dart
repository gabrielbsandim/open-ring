import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/energy/presentation/energy_formula_screen.dart';
import 'package:open_ring/features/energy/presentation/energy_module_screen.dart';
import 'package:open_ring/features/energy/presentation/energy_screen.dart';

import '../helpers/onboarding_app.dart';
import '../helpers/onboarding_fakes.dart';

void main() {
  testWidgets('back from the formula returns to the Energy module screen', (
    tester,
  ) async {
    final container = await pumpOnboardingApp(
      tester,
      store: InMemoryOnboardingStore(completed: true),
      at: AppPaths.settingsModuleEnergy,
    );
    expect(find.byType(EnergyModuleScreen), findsOneWidget);

    await tapAndSettle(tester, find.byKey(EnergyModuleKeys.formula));
    expect(find.byType(EnergyFormulaScreen), findsOneWidget);

    container.read(appRouterProvider).pop();
    await tester.pumpAndSettle();

    expect(find.byType(EnergyFormulaScreen), findsNothing);
    expect(find.byType(EnergyModuleScreen), findsOneWidget);
    expect(find.byType(EnergyScreen), findsNothing);
  });
}
