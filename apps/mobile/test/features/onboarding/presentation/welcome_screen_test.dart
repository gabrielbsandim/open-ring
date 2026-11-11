import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/onboarding/presentation/permissions_screen.dart';
import 'package:open_ring/features/onboarding/presentation/welcome_screen.dart';

import '../../../helpers/onboarding_app.dart';

void main() {
  testWidgets('explains the app and starts with the permissions', (
    tester,
  ) async {
    await pumpOnboardingApp(tester);

    expect(find.text('Your ring, your data.'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(WelcomeScreen.startKey));

    expect(find.byType(PermissionsScreen), findsOneWidget);
    expect(find.text('Step 1 of 4'), findsOneWidget);
  });
}
