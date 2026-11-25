import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_screen.dart';
import 'package:open_ring/features/trajectory/presentation/what_if_screen.dart';

import '../features/trajectory/support/what_if_fixtures.dart';
import '../helpers/ble_fakes.dart';
import '../helpers/onboarding_app.dart';
import '../helpers/onboarding_fakes.dart';
import '../helpers/ring_fakes.dart';

void main() {
  test('the what if path lives under the trajectory path', () {
    expect(AppPaths.trajectoryWhatIf, '/today/trajectory/what-if');
  });

  testWidgets('the router builds WhatIfScreen at the what if path', (
    tester,
  ) async {
    await pumpOnboardingApp(
      tester,
      store: InMemoryOnboardingStore(completed: true),
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(),
        ...onboardingOverrides(),
        ...whatIfOverrides(),
      ],
      at: AppPaths.trajectoryWhatIf,
    );

    expect(find.byType(WhatIfScreen), findsOneWidget);
    expect(find.byType(TrajectoryScreen), findsNothing);
  });

  testWidgets('tapping the link on the trajectory screen opens the what if', (
    tester,
  ) async {
    await pumpOnboardingApp(
      tester,
      store: InMemoryOnboardingStore(completed: true),
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(),
        ...onboardingOverrides(),
        ...whatIfOverrides(),
      ],
      at: AppPaths.trajectory,
    );

    await tapAndSettle(tester, find.byKey(TrajectoryKeys.whatIfLink));

    expect(find.byType(WhatIfScreen), findsOneWidget);
  });
}
