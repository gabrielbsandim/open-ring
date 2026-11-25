import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_screen.dart';

import '../features/trajectory/presentation/trajectory_screen_fixtures.dart';
import '../helpers/ble_fakes.dart';
import '../helpers/onboarding_app.dart';
import '../helpers/onboarding_fakes.dart';
import '../helpers/ring_fakes.dart';

void main() {
  test('the trajectory path lives under Today', () {
    expect(AppPaths.trajectory, '/today/trajectory');
  });

  testWidgets('the router builds TrajectoryScreen at the trajectory path', (
    tester,
  ) async {
    await pumpOnboardingApp(
      tester,
      store: InMemoryOnboardingStore(completed: true),
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(),
        ...onboardingOverrides(),
        ...trajectoryOverrides(view: const TrajectoryOff()),
      ],
      at: AppPaths.trajectory,
    );

    expect(find.byType(TrajectoryScreen), findsOneWidget);
  });
}
