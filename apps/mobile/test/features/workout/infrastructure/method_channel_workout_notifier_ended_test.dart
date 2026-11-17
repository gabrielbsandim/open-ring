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

  const saved = WorkoutEndNotice(
    title: 'Treino salvo',
    text: 'Corrida · 40:00 · 6,60 km · FC média 146',
    action: 'Ver resumo do treino',
    link: 'openring://widget/activity/workout-summary/42',
    channel: 'Treino',
  );

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('10: the channel', () {
    test('names the two ended methods', () {
      expect(
        RingNotificationsChannel.showWorkoutEndedMethod,
        'showWorkoutEnded',
      );
      expect(
        RingNotificationsChannel.clearWorkoutEndedMethod,
        'clearWorkoutEnded',
      );
    });

    test('ended sends showWorkoutEnded with the exact map', () async {
      await MethodChannelWorkoutNotifier().ended(saved);

      expect(calls.single.method, 'showWorkoutEnded');
      expect(calls.single.arguments, {
        'channelName': 'Treino',
        'title': 'Treino salvo',
        'text': 'Corrida · 40:00 · 6,60 km · FC média 146',
        'actionLabel': 'Ver resumo do treino',
        'link': 'openring://widget/activity/workout-summary/42',
        'timeoutMs': 3600000,
      });
    });

    test('the failed notice keeps the link with no id', () async {
      await MethodChannelWorkoutNotifier().ended(
        const WorkoutEndNotice(
          title: 'The workout was not saved',
          text: 'Nothing is lost yet. Open the app and try again.',
          action: 'Open',
          link: 'openring://widget/activity/workout-summary',
        ),
      );

      expect(calls.single.arguments, {
        'channelName': 'Workout',
        'title': 'The workout was not saved',
        'text': 'Nothing is lost yet. Open the app and try again.',
        'actionLabel': 'Open',
        'link': 'openring://widget/activity/workout-summary',
        'timeoutMs': 3600000,
      });
    });

    test('clearEnded sends clearWorkoutEnded with no arguments', () async {
      await MethodChannelWorkoutNotifier().clearEnded();

      expect(calls.single.method, 'clearWorkoutEnded');
      expect(calls.single.arguments, isNull);
    });

    test('hide never clears the ended notice', () async {
      await MethodChannelWorkoutNotifier().hide();

      expect(calls.map((c) => c.method), ['hideWorkout']);
    });

    test('a platform error from ended reaches the caller', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'denied'),
      );

      await expectLater(
        MethodChannelWorkoutNotifier().ended(saved),
        throwsA(isA<PlatformException>()),
      );
    });
  });
}
