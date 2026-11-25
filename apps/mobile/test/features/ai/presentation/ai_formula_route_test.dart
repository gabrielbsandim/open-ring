import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/presentation/ai_formula_screen.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/onboarding_app.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart';

void main() {
  testWidgets('the app formula route opens the screen with AI off', (
    tester,
  ) async {
    final container = await pumpOnboardingApp(
      tester,
      store: InMemoryOnboardingStore(completed: true),
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(),
        ...onboardingOverrides(),
        aiEnabledProvider.overrideWith((ref) => false),
      ],
    );
    container.read(appRouterProvider).go(AppPaths.aiFormula);
    await tester.pumpAndSettle();

    expect(find.byType(AiFormulaScreen), findsOneWidget);
    expect(find.byKey(AiFormulaKeys.intro), findsOneWidget);
  });
}
