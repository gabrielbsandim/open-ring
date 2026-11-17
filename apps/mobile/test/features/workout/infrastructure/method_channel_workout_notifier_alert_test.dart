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

  group('7: the channel', () {
    test('names the two alert methods', () {
      expect(RingNotificationsChannel.alertWorkoutMethod, 'alertWorkout');
      expect(
        RingNotificationsChannel.clearWorkoutAlertMethod,
        'clearWorkoutAlert',
      );
    });

    test('alert sends alertWorkout with the four fields', () async {
      await MethodChannelWorkoutNotifier().alert(
        const WorkoutAlert(
          title: 'O anel parou de enviar a FC',
          text: 'O treino continua sendo gravado. Toque para reconectar.',
          channel: 'Avisos do treino',
          reconnect: 'Reconectar',
        ),
      );

      expect(calls.single.method, 'alertWorkout');
      expect(calls.single.arguments, {
        'channelName': 'Avisos do treino',
        'title': 'O anel parou de enviar a FC',
        'text': 'O treino continua sendo gravado. Toque para reconectar.',
        'reconnectLabel': 'Reconectar',
      });
    });

    test('alert sends the default channel and reconnect label', () async {
      await MethodChannelWorkoutNotifier().alert(
        const WorkoutAlert(
          title: 'The ring stopped sending heart rate',
          text: 'The workout is still recording. Tap to reconnect.',
        ),
      );

      expect(
        calls.single.arguments,
        allOf(
          containsPair('channelName', 'Workout alerts'),
          containsPair('reconnectLabel', 'Reconnect'),
        ),
      );
    });

    test('clearAlert sends clearWorkoutAlert with no arguments', () async {
      await MethodChannelWorkoutNotifier().clearAlert();

      expect(calls.single.method, 'clearWorkoutAlert');
      expect(calls.single.arguments, isNull);
    });

    test('a platform error from alert reaches the caller', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'denied'),
      );

      await expectLater(
        MethodChannelWorkoutNotifier().alert(
          const WorkoutAlert(title: 'Ring', text: 'Lost'),
        ),
        throwsA(isA<PlatformException>()),
      );
    });
  });
}
