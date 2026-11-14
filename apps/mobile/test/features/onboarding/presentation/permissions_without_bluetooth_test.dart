import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/onboarding/domain/app_permissions.dart';
import 'package:open_ring/features/onboarding/presentation/permissions_screen.dart';
import 'package:open_ring/features/onboarding/presentation/profile_screen.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/onboarding_app.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart';

void main() {
  testWidgets('continue is enabled with Bluetooth denied', (tester) async {
    await pumpOnboardingApp(
      tester,
      at: AppPaths.onboardingPermissions,
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(),
        ...onboardingOverrides(
          permissions: FakeAppPermissions(
            statuses: {AppPermission.bluetooth: PermissionStatus.denied},
          ),
        ),
      ],
    );

    final button = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(PermissionsKeys.continueAction),
        matching: find.byType(FilledButton),
      ),
    );

    expect(button.onPressed, isNotNull);
  });

  testWidgets('continue with Bluetooth denied opens the profile step', (
    tester,
  ) async {
    final permissions = FakeAppPermissions(
      statuses: {AppPermission.bluetooth: PermissionStatus.permanentlyDenied},
    );
    await pumpOnboardingApp(
      tester,
      at: AppPaths.onboardingPermissions,
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(),
        ...onboardingOverrides(permissions: permissions),
      ],
    );

    await tapAndSettle(tester, find.byKey(PermissionsKeys.continueAction));

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(permissions.requests, isEmpty);
  });
  testWidgets('on iOS continue still waits for Bluetooth', (tester) async {
    await pumpOnboardingApp(
      tester,
      at: AppPaths.onboardingPermissions,
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(),
        ...onboardingOverrides(
          permissions: FakeAppPermissions(
            statuses: {AppPermission.bluetooth: PermissionStatus.denied},
          ),
        ),
      ],
    );

    final button = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(PermissionsKeys.continueAction),
        matching: find.byType(FilledButton),
      ),
    );

    expect(button.onPressed, isNull);
    expect(find.text('Required'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
