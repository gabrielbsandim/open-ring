import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/onboarding/domain/app_permissions.dart';
import 'package:open_ring/features/onboarding/presentation/permissions_screen.dart';
import 'package:open_ring/features/onboarding/presentation/profile_screen.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/onboarding_app.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/protocol_lab_fakes.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/settings_fakes.dart';

Future<FakeAppPermissions> _pump(
  WidgetTester tester, [
  Map<AppPermission, PermissionStatus>? statuses,
]) async {
  final permissions = FakeAppPermissions(statuses: statuses);
  await pumpOnboardingApp(
    tester,
    at: AppPaths.onboardingPermissions,
    overrides: [
      ...protocolLabOverrides(),
      ...ringOverrides(),
      ...onboardingOverrides(permissions: permissions),
    ],
  );
  return permissions;
}

FilledButton _continue(WidgetTester tester) => tester.widget(
  find.descendant(
    of: find.byKey(PermissionsKeys.continueAction),
    matching: find.byType(FilledButton),
  ),
);

const Map<AppPermission, PermissionStatus> _everyState = {
  AppPermission.bluetooth: PermissionStatus.granted,
  AppPermission.notifications: PermissionStatus.permanentlyDenied,
  AppPermission.backgroundExecution: PermissionStatus.notApplicable,
  AppPermission.location: PermissionStatus.denied,
};

void main() {
  group('Permissions with every state', () {
    for (final c in layoutMatrix()) {
      testWidgets('lays out without overflow at $c', (tester) async {
        await pumpScaled(
          tester,
          screenHost(const PermissionsScreen()),
          textScaler: c.textScaler,
          brightness: c.brightness,
          locale: c.locale,
          overrides: [
            ...protocolLabOverrides(),
            ...ringOverrides(),
            ...onboardingOverrides(
              permissions: FakeAppPermissions(statuses: {..._everyState}),
            ),
          ],
        );

        await scrollThrough(tester);
        expect(find.byType(PermissionsScreen), findsOneWidget);
      });
    }
  });

  testWidgets('explains each permission before asking for it', (tester) async {
    final permissions = await _pump(tester);

    expect(find.text('Nearby devices (Bluetooth)'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(permissions.requests, isEmpty);
    expect(find.byKey(PermissionsKeys.bluetoothHint), findsOneWidget);
    expect(_continue(tester).onPressed, isNull);
  });

  testWidgets('Bluetooth is required, notifications are optional', (
    tester,
  ) async {
    final permissions = await _pump(tester);

    await tapAndSettle(
      tester,
      find.byKey(PermissionsKeys.allow(AppPermission.bluetooth)),
    );

    expect(permissions.requests, [AppPermission.bluetooth]);
    expect(
      find.byKey(PermissionsKeys.granted(AppPermission.bluetooth)),
      findsOneWidget,
    );
    expect(find.byKey(PermissionsKeys.bluetoothHint), findsNothing);
    expect(
      find.byKey(PermissionsKeys.allow(AppPermission.notifications)),
      findsOneWidget,
    );

    await tapAndSettle(tester, find.byKey(PermissionsKeys.continueAction));

    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('background execution and location have their own cards', (
    tester,
  ) async {
    await _pump(tester);
    final background = find.byKey(
      PermissionsKeys.allow(AppPermission.backgroundExecution),
    );
    final location = find.byKey(PermissionsKeys.allow(AppPermission.location));

    await reveal(tester, background);
    expect(find.text('Background activity'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    await reveal(tester, location);
    expect(find.text('Location'), findsOneWidget);
    expect(find.textContaining('to record your route'), findsOneWidget);
  });

  testWidgets('allowing either new card goes through the permissions port', (
    tester,
  ) async {
    final permissions = await _pump(tester);
    final background = find.byKey(
      PermissionsKeys.allow(AppPermission.backgroundExecution),
    );
    final location = find.byKey(PermissionsKeys.allow(AppPermission.location));

    await reveal(tester, background);
    await tapAndSettle(tester, background);
    await reveal(tester, location);
    await tapAndSettle(tester, location);

    expect(permissions.requests, [
      AppPermission.backgroundExecution,
      AppPermission.location,
    ]);
    expect(
      find.byKey(PermissionsKeys.granted(AppPermission.location)),
      findsOneWidget,
    );
  });

  testWidgets(
    'a card that does not apply offers no action and blocks nothing',
    (tester) async {
      await _pump(tester, {
        AppPermission.bluetooth: PermissionStatus.granted,
        AppPermission.backgroundExecution: PermissionStatus.notApplicable,
      });
      final notApplicable = find.byKey(
        PermissionsKeys.notApplicable(AppPermission.backgroundExecution),
      );

      await reveal(tester, notApplicable);

      expect(find.text('Not needed on this device'), findsOneWidget);
      expect(
        find.byKey(PermissionsKeys.allow(AppPermission.backgroundExecution)),
        findsNothing,
      );
      expect(_continue(tester).onPressed, isNotNull);
    },
  );

  testWidgets('a battery exemption granted in the settings shows on return', (
    tester,
  ) async {
    final permissions = await _pump(tester);
    permissions.statuses[AppPermission.backgroundExecution] =
        PermissionStatus.granted;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    final granted = find.byKey(
      PermissionsKeys.granted(AppPermission.backgroundExecution),
    );

    await reveal(tester, granted);
    expect(granted, findsOneWidget);
  });

  testWidgets('a permanently denied permission opens the settings', (
    tester,
  ) async {
    final permissions = await _pump(tester, {
      AppPermission.bluetooth: PermissionStatus.permanentlyDenied,
    });

    expect(find.text('Open settings'), findsOneWidget);
    await tapAndSettle(
      tester,
      find.byKey(PermissionsKeys.allow(AppPermission.bluetooth)),
    );

    expect(permissions.settingsOpened, 1);
    expect(permissions.requests, isEmpty);
  });

  testWidgets('a permission granted in the settings shows on return', (
    tester,
  ) async {
    final permissions = await _pump(tester, {
      AppPermission.bluetooth: PermissionStatus.permanentlyDenied,
    });
    permissions.statuses[AppPermission.bluetooth] = PermissionStatus.granted;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(
      find.byKey(PermissionsKeys.granted(AppPermission.bluetooth)),
      findsOneWidget,
    );
    expect(_continue(tester).onPressed, isNotNull);
  });
}
