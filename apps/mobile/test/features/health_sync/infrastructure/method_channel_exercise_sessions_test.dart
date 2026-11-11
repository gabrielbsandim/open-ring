import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/health_sync/infrastructure/method_channel_exercise_sessions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(MethodChannelExerciseSessions.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final from = DateTime.utc(2026, 10, 11, 9);
  final to = DateTime.utc(2026, 11, 10, 9);
  final start = DateTime.utc(2026, 11, 9, 18);
  final end = DateTime.utc(2026, 11, 9, 18, 40);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('maps each session and skips malformed ones', () async {
    MethodCall? call;
    messenger.setMockMethodCallHandler(channel, (c) async {
      call = c;
      return [
        {
          'id': 'w1',
          'source': 'com.garmin.android.apps.connectmobile',
          'activityType': 'running',
          'start': start.millisecondsSinceEpoch,
          'end': end.millisecondsSinceEpoch,
          'offsetSeconds': -10800,
        },
        {'id': 'broken'},
      ];
    });

    final workouts = await const MethodChannelExerciseSessions().read(
      from: from,
      to: to,
    );

    expect(call!.method, 'read');
    expect(call!.arguments, {
      'from': from.millisecondsSinceEpoch,
      'to': to.millisecondsSinceEpoch,
    });
    expect(workouts.present, {'w1', 'broken'});
    final workout = workouts.records.single;
    expect(workout.recordId, 'w1');
    expect(workout.source, 'com.garmin.android.apps.connectmobile');
    expect(workout.activityType, 'running');
    expect(workout.start, start);
    expect(workout.end, end);
    expect(workout.utcOffset, const Duration(hours: -3));
  });

  test('without a zone offset it uses the phone offset at the start', () {
    final workout = MethodChannelExerciseSessions.workoutOf({
      'id': 'w1',
      'source': 'com.garmin.android.apps.connectmobile',
      'activityType': 'other',
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
      'offsetSeconds': null,
    });

    expect(workout!.utcOffset, start.toLocal().timeZoneOffset);
  });

  test('a platform error reaches the importer', () {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'health_connect_exercise'),
    );

    expect(
      const MethodChannelExerciseSessions().read(from: from, to: to),
      throwsA(isA<PlatformException>()),
    );
  });
}
