import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/workout/domain/workout_notifier.dart';

void main() {
  const alert = WorkoutAlert(
    title: 'The ring stopped sending heart rate',
    text: 'The workout is still recording. Tap to reconnect.',
  );

  group('1: WorkoutAlert', () {
    test('defaults the channel and the reconnect label to English', () {
      expect(alert.channel, 'Workout alerts');
      expect(alert.reconnect, 'Reconnect');
    });

    test('equal fields are equal with the same hash', () {
      const same = WorkoutAlert(
        title: 'The ring stopped sending heart rate',
        text: 'The workout is still recording. Tap to reconnect.',
        // Explicit defaults: equality must not depend on them being omitted.
        // ignore: avoid_redundant_argument_values
        channel: 'Workout alerts',
        // Same reason: the default spelled out.
        // ignore: avoid_redundant_argument_values
        reconnect: 'Reconnect',
      );

      expect(same, alert);
      expect(same.hashCode, alert.hashCode);
    });

    final others = <String, WorkoutAlert>{
      'title': const WorkoutAlert(
        title: 'Other',
        text: 'The workout is still recording. Tap to reconnect.',
      ),
      'text': const WorkoutAlert(
        title: 'The ring stopped sending heart rate',
        text: 'Other',
      ),
      'channel': const WorkoutAlert(
        title: 'The ring stopped sending heart rate',
        text: 'The workout is still recording. Tap to reconnect.',
        channel: 'Avisos do treino',
      ),
      'reconnect': const WorkoutAlert(
        title: 'The ring stopped sending heart rate',
        text: 'The workout is still recording. Tap to reconnect.',
        reconnect: 'Reconectar',
      ),
    };

    for (final MapEntry(key: field, value: other) in others.entries) {
      test('a different $field is not equal', () {
        expect(other, isNot(alert));
      });
    }
  });

  group('1: WorkoutNoticeLabels alert defaults', () {
    test('are the English alert strings', () {
      const labels = WorkoutNoticeLabels();

      expect(labels.alertChannel, 'Workout alerts');
      expect(labels.ringLostAlertTitle, 'The ring stopped sending heart rate');
      expect(
        labels.ringLostAlertText,
        'The workout is still recording. Tap to reconnect.',
      );
    });
  });

  group('the in-memory notifier', () {
    test('records each alert and each clear', () async {
      final notifier = InMemoryWorkoutNotifier();

      await notifier.alert(alert);
      await notifier.clearAlert();
      await notifier.alert(alert);

      expect(notifier.alerts, [alert, alert]);
      expect(notifier.alertClears, 1);
    });

    test('6: fails on alert when failing is set', () async {
      final notifier = InMemoryWorkoutNotifier()..failing = true;

      await expectLater(
        notifier.alert(alert),
        throwsA(isA<WorkoutNotifierFailure>()),
      );
      expect(notifier.alerts, isEmpty);
    });

    test('6: fails on clearAlert when failing is set', () async {
      final notifier = InMemoryWorkoutNotifier()..failing = true;

      await expectLater(
        notifier.clearAlert(),
        throwsA(isA<WorkoutNotifierFailure>()),
      );
      expect(notifier.alertClears, 0);
    });
  });
}
