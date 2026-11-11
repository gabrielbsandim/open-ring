import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/onboarding/domain/app_permissions.dart';
import 'package:open_ring/features/onboarding/infrastructure/method_channel_app_permissions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(MethodChannelAppPermissions.channelName);
  final calls = <MethodCall>[];

  void answer(Object? Function(MethodCall call) reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return reply(call);
        });
    addTearDown(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  }

  test(
    'status and request pass the permission name and parse the reply',
    () async {
      answer(
        (call) => call.method == 'status' ? 'granted' : 'permanentlyDenied',
      );
      const permissions = MethodChannelAppPermissions();

      expect(
        await permissions.status(AppPermission.bluetooth),
        PermissionStatus.granted,
      );
      expect(
        await permissions.request(AppPermission.notifications),
        PermissionStatus.permanentlyDenied,
      );
      expect(calls.map((c) => (c.method, c.arguments)), [
        ('status', 'bluetooth'),
        ('request', 'notifications'),
      ]);
    },
  );

  test('an unknown reply reads as denied', () async {
    answer((_) => 'maybe');

    expect(
      await const MethodChannelAppPermissions().status(AppPermission.bluetooth),
      PermissionStatus.denied,
    );
  });

  test('openSettings calls the platform', () async {
    answer((_) => null);

    await const MethodChannelAppPermissions().openSettings();

    expect(calls.single.method, 'openSettings');
  });
}
