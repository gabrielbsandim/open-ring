import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/workout/application/workout_notice.dart';
import 'package:open_ring/features/workout/domain/workout_recovery.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

// The en copy the 11 ARBs must carry, as placeholders {time} {elapsed}
// {distance}: the title, the body, and the body with no distance.
const enTitle = 'Workout saved until 07:31';
const enBody = 'OpenRing stopped during the workout. 21:00, 3.00 km kept.';
const enBodyNoDistance = 'OpenRing stopped during the workout. 21:00 kept.';

final end = DateTime.utc(2026, 11, 10, 7, 31);
final sameDay = DateTime.utc(2026, 11, 10, 12);
final laterDay = DateTime.utc(2026, 11, 12, 12);

RecoveredWorkout recovered({
  WorkoutType type = WorkoutType.running,
  double? meters = 3000,
  int offsetMinutes = 0,
}) => RecoveredWorkout(
  id: 7,
  type: type,
  start: DateTime.utc(2026, 11, 10, 7, 10),
  end: end,
  elapsed: const Duration(minutes: 21),
  distanceMeters: meters,
  offsetMinutes: offsetMinutes,
);

void main() {
  final pt = workoutLocationNotice(lookupAppLocalizations(const Locale('pt')));
  final en = workoutLocationNotice(lookupAppLocalizations(const Locale('en')));

  test('en title and body name the time, the duration and the distance', () {
    final notice = workoutRecoveredNoticeOf(
      recovered(),
      en.live,
      UnitSystem.metric,
      now: sameDay,
    );

    expect(notice.title, enTitle);
    expect(notice.text, enBody);
    expect(notice.failed, isFalse);
    expect(notice.link, '$workoutSummaryLink/7');
    expect(notice.action, en.live.viewSummary);
    expect(notice.channel, en.live.channel);
  });

  test('criterion 6: in pt the title is Treino salvo até 07:31', () {
    final notice = workoutRecoveredNoticeOf(
      recovered(),
      pt.live,
      UnitSystem.metric,
      now: sameDay,
    );

    expect(notice.title, 'Treino salvo até 07:31');
    expect(notice.text, contains('21:00'));
    expect(notice.text, contains('3,00 km'));
  });

  test('criterion 6: on a later day the title shows the date', () {
    final notice = workoutRecoveredNoticeOf(
      recovered(),
      en.live,
      UnitSystem.metric,
      now: laterDay,
    );

    expect(notice.title, contains('Nov 10'));
    expect(notice.title, contains('07:31'));
  });

  test('criterion 6: an indoor row uses the body with no distance', () {
    final notice = workoutRecoveredNoticeOf(
      recovered(type: WorkoutType.treadmill, meters: null),
      en.live,
      UnitSystem.metric,
      now: sameDay,
    );

    expect(notice.title, enTitle);
    expect(notice.text, enBodyNoDistance);
  });

  test('criterion 6: imperial units show mi', () {
    final notice = workoutRecoveredNoticeOf(
      recovered(),
      en.live,
      UnitSystem.imperial,
      now: sameDay,
    );

    expect(
      notice.text,
      'OpenRing stopped during the workout. 21:00, 1.86 mi kept.',
    );
  });

  test('the time is shown in the offset stored on the row', () {
    final notice = workoutRecoveredNoticeOf(
      recovered(offsetMinutes: -180),
      en.live,
      UnitSystem.metric,
      now: sameDay,
    );

    expect(notice.title, 'Workout saved until 04:31');
  });

  test('a run past one hour shows hours in the duration', () {
    final long = RecoveredWorkout(
      id: 7,
      type: WorkoutType.running,
      start: DateTime.utc(2026, 11, 10, 6),
      end: end,
      elapsed: const Duration(hours: 1, minutes: 31, seconds: 5),
      distanceMeters: 3000,
      offsetMinutes: 0,
    );

    final notice = workoutRecoveredNoticeOf(
      long,
      en.live,
      UnitSystem.metric,
      now: sameDay,
    );

    expect(notice.text, contains('1:31:05'));
  });
}
