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

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
  });

  Future<void> incoming(Object? argument) => messenger.handlePlatformMessage(
    RingNotificationsChannel.name,
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('workoutAction', argument),
    ),
    (_) {},
  );

  test(
    '8: show sends showWorkout with title, text, elapsedMs, running',
    () async {
      await MethodChannelWorkoutNotifier().show(
        const WorkoutNotice(
          title: 'Running',
          text: '148 bpm',
          elapsed: Duration(minutes: 2, seconds: 5),
          running: false,
        ),
      );

      expect(calls.single.method, 'showWorkout');
      expect(
        calls.single.arguments,
        allOf(
          containsPair('title', 'Running'),
          containsPair('text', '148 bpm'),
          containsPair('elapsedMs', 125000),
          containsPair('running', false),
        ),
      );
    },
  );

  test('8: hide sends hideWorkout with no arguments', () async {
    await MethodChannelWorkoutNotifier().hide();

    expect(calls.single.method, 'hideWorkout');
    expect(calls.single.arguments, isNull);
  });

  test('8: workoutAction values map to the enum', () async {
    final notifier = MethodChannelWorkoutNotifier();
    final received = <WorkoutNoticeAction>[];
    final sub = notifier.actions.listen(received.add);

    await incoming('pause');
    await incoming('resume');
    await incoming('stop');
    await pumpEventQueue();
    await sub.cancel();

    expect(received, [
      WorkoutNoticeAction.pause,
      WorkoutNoticeAction.resume,
      WorkoutNoticeAction.stop,
    ]);
  });

  test('8: an unknown or missing workoutAction value emits nothing', () async {
    final notifier = MethodChannelWorkoutNotifier();
    final received = <WorkoutNoticeAction>[];
    final sub = notifier.actions.listen(received.add);

    await incoming('dance');
    await incoming(null);
    await incoming(7);
    await incoming('stop');
    await pumpEventQueue();
    await sub.cancel();

    expect(received, [WorkoutNoticeAction.stop]);
  });

  test(
    'N3: show sends confirming, ringLost and the three new labels',
    () async {
      await MethodChannelWorkoutNotifier().show(
        const WorkoutNotice(
          title: 'Encerrar e salvar o treino?',
          text: '23:41 · 3,92 km · pausado',
          elapsed: Duration(seconds: 1421),
          running: false,
          confirming: true,
          ringLost: true,
          labels: WorkoutNoticeLabels(
            save: 'Salvar',
            keep: 'Continuar',
            reconnect: 'Reconectar',
          ),
        ),
      );

      expect(calls.single.method, 'showWorkout');
      expect(
        calls.single.arguments,
        allOf(
          containsPair('confirming', true),
          containsPair('ringLost', true),
          containsPair('saveLabel', 'Salvar'),
          containsPair('keepLabel', 'Continuar'),
          containsPair('reconnectLabel', 'Reconectar'),
          containsPair('title', 'Encerrar e salvar o treino?'),
          containsPair('running', false),
        ),
      );
    },
  );

  test('N3: a plain notice sends false flags and the English labels', () async {
    await MethodChannelWorkoutNotifier().show(
      const WorkoutNotice(
        title: 'Running',
        text: '148 bpm',
        elapsed: Duration(seconds: 3),
        running: true,
      ),
    );

    expect(
      calls.single.arguments,
      allOf(
        containsPair('confirming', false),
        containsPair('ringLost', false),
        containsPair('saveLabel', 'Save'),
        containsPair('keepLabel', 'Continue'),
        containsPair('reconnectLabel', 'Reconnect'),
      ),
    );
  });

  test('N3: save, keep and reconnect taps map to the enum', () async {
    final notifier = MethodChannelWorkoutNotifier();
    final received = <WorkoutNoticeAction>[];
    final sub = notifier.actions.listen(received.add);

    await incoming('save');
    await incoming('keep');
    await incoming('reconnect');
    await pumpEventQueue();
    await sub.cancel();

    expect(received, [
      WorkoutNoticeAction.save,
      WorkoutNoticeAction.keep,
      WorkoutNoticeAction.reconnect,
    ]);
  });
}
