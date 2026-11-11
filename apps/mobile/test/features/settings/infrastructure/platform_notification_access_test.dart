import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/onboarding/domain/app_permissions.dart';
import 'package:open_ring/features/settings/infrastructure/platform_notification_access.dart';

import '../../../helpers/onboarding_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/notification_settings');

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('reports the notification permission', () async {
    final permissions = FakeAppPermissions(
      statuses: {AppPermission.notifications: PermissionStatus.granted},
    );

    expect(
      await PlatformNotificationAccess(permissions, channel).enabled(),
      true,
    );
    permissions.statuses[AppPermission.notifications] =
        PermissionStatus.permanentlyDenied;
    expect(
      await PlatformNotificationAccess(permissions, channel).enabled(),
      false,
    );
  });

  test('opens the notification page when the platform has one', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
    final permissions = FakeAppPermissions();

    await PlatformNotificationAccess(permissions, channel).openSettings();

    expect(calls, [PlatformNotificationAccess.openMethod]);
    expect(permissions.settingsOpened, 0);
  });

  test('falls back to the app settings page elsewhere', () async {
    final permissions = FakeAppPermissions();

    await PlatformNotificationAccess(permissions, channel).openSettings();

    expect(permissions.settingsOpened, 1);
  });
}
