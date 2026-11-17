import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/workout/domain/workout_notifier.dart';
import 'package:open_ring/features/workout/infrastructure/method_channel_workout_notifier.dart';
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
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('6: show sends publicTitle and publicText', () async {
    await MethodChannelWorkoutNotifier().show(
      const WorkoutNotice(
        title: 'Running · Zone 4',
        text: '152 bpm · 3.92 km',
        elapsed: Duration(seconds: 5),
        running: true,
        publicTitle: 'Running',
        publicText: '3.92 km',
      ),
    );

    expect(
      calls.single.arguments,
      allOf(
        containsPair('title', 'Running · Zone 4'),
        containsPair('publicTitle', 'Running'),
        containsPair('publicText', '3.92 km'),
      ),
    );
  });

  test('6: absent public fields are sent as null', () async {
    await MethodChannelWorkoutNotifier().show(
      const WorkoutNotice(
        title: 'Running',
        text: '152 bpm',
        elapsed: Duration(seconds: 5),
        running: true,
      ),
    );

    final arguments = calls.single.arguments as Map<Object?, Object?>;
    expect(arguments.containsKey('publicTitle'), isTrue);
    expect(arguments.containsKey('publicText'), isTrue);
    expect(arguments['publicTitle'], isNull);
    expect(arguments['publicText'], isNull);
  });
}
