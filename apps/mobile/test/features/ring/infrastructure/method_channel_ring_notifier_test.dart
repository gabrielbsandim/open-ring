import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/domain/ring_alerts.dart';
import 'package:open_ring/features/ring/infrastructure/method_channel_ring_notifier.dart';
import 'package:ring_notifications/ring_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(RingNotificationsChannel.name);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == RingNotificationsChannel.enabledMethod
          ? true
          : null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('enabled reads the platform answer', () async {
    expect(await const MethodChannelRingNotifier().enabled(), isTrue);
  });

  test('a null platform answer reads as not allowed', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);

    expect(await const MethodChannelRingNotifier().enabled(), isFalse);
  });

  test('show sends the text and a link the router serves', () async {
    await const MethodChannelRingNotifier().show(
      const RingNotification(
        id: 7,
        channelName: 'Ring alerts',
        title: 'Title',
        body: 'Body',
      ),
    );

    expect(calls.single.method, RingNotificationsChannel.showMethod);
    expect(calls.single.arguments, {
      'id': 7,
      'channelName': 'Ring alerts',
      'title': 'Title',
      'body': 'Body',
      'link': 'openring://widget/ring',
    });
  });
}
