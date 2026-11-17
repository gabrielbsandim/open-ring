import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/workout/application/workout_notice.dart';
import 'package:open_ring/features/workout/domain/workout_notifier.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

const _summaryLink = 'openring://widget/activity/workout-summary';

void main() {
  final ptL10n = lookupAppLocalizations(const Locale('pt'));
  final enL10n = lookupAppLocalizations(const Locale('en'));
  final pt = workoutLocationNotice(ptL10n).live;
  final en = workoutLocationNotice(enL10n).live;

  WorkoutSnapshot ended({
    WorkoutType type = WorkoutType.running,
    bool gps = true,
    int seconds = 2400,
    double? meters = 6600,
    int? average = 146,
  }) => WorkoutSnapshot(
    type: type,
    status: WorkoutStatus.finished,
    gps: gps,
    elapsed: Duration(seconds: seconds),
    distanceMeters: meters,
    averageHeartRate: average,
    currentHeartRate: 171,
    maxHeartRate: 180,
  );

  group('the ended labels come from the ARBs', () {
    test('pt reuses the saved, failed and summary strings', () {
      expect(pt.savedTitle, 'Treino salvo');
      expect(pt.failedTitle, 'O treino não foi salvo');
      expect(pt.viewSummary, ptL10n.workoutViewSummary);
      expect(pt.savedHeartRate(146), 'FC média 146');
      expect(
        pt.failedText,
        'Nada se perdeu ainda. Abra o app e tente de novo.',
      );
      expect(pt.open, 'Abrir');
    });

    test('en has the three new strings', () {
      expect(en.savedTitle, 'Workout saved');
      expect(en.failedTitle, 'The workout was not saved');
      expect(en.viewSummary, enL10n.workoutViewSummary);
      expect(en.savedHeartRate(146), 'Avg HR 146');
      expect(en.failedText, 'Nothing is lost yet. Open the app and try again.');
      expect(en.open, 'Open');
    });
  });

  group('1: a saved run names the type, time, distance and average', () {
    test('a pt run of 40:00, 6,600 m and 146 saved as id 42', () {
      final notice = workoutEndNoticeOf(
        ended(),
        pt,
        UnitSystem.metric,
        workoutId: 42,
      );

      expect(notice.title, 'Treino salvo');
      expect(notice.text, 'Corrida · 40:00 · 6,60 km · FC média 146');
      expect(notice.action, ptL10n.workoutViewSummary);
      expect(notice.link, endsWith('/42'));
      expect(notice.link, '$_summaryLink/42');
    });

    test('the text uses the average, not the last heart rate', () {
      final notice = workoutEndNoticeOf(
        ended(),
        pt,
        UnitSystem.metric,
        workoutId: 42,
      );

      expect(notice.text, isNot(contains('171')));
      expect(notice.text, isNot(contains('180')));
    });

    test('a workout past an hour shows hours', () {
      final notice = workoutEndNoticeOf(
        ended(seconds: 3725),
        pt,
        UnitSystem.metric,
        workoutId: 42,
      );

      expect(notice.text, 'Corrida · 1:02:05 · 6,60 km · FC média 146');
    });

    test('imperial units show miles with the English separator', () {
      final notice = workoutEndNoticeOf(
        ended(),
        en,
        UnitSystem.imperial,
        workoutId: 7,
      );

      expect(notice.title, 'Workout saved');
      expect(notice.text, 'Running · 40:00 · 4.10 mi · Avg HR 146');
      expect(notice.link, '$_summaryLink/7');
    });
  });

  group('2: fields that did not happen leave the text', () {
    test('a run with GPS off has no distance', () {
      final notice = workoutEndNoticeOf(
        ended(gps: false, meters: null),
        pt,
        UnitSystem.metric,
        workoutId: 42,
      );

      expect(notice.text, 'Corrida · 40:00 · FC média 146');
    });

    test('an indoor type has no distance', () {
      final notice = workoutEndNoticeOf(
        ended(type: WorkoutType.strength, gps: false, meters: null),
        pt,
        UnitSystem.metric,
        workoutId: 42,
      );

      expect(notice.text, 'Musculação · 40:00 · FC média 146');
    });

    test('no average heart rate has no heart rate field', () {
      final notice = workoutEndNoticeOf(
        ended(average: null),
        pt,
        UnitSystem.metric,
        workoutId: 42,
      );

      expect(notice.text, 'Corrida · 40:00 · 6,60 km');
    });

    test('neither leaves the type and the time', () {
      final notice = workoutEndNoticeOf(
        ended(
          type: WorkoutType.strength,
          gps: false,
          meters: null,
          average: null,
        ),
        pt,
        UnitSystem.metric,
        workoutId: 42,
      );

      expect(notice.text, 'Musculação · 40:00');
    });
  });

  group('3: a null id is the failed notice', () {
    test('pt says it was not saved and offers Abrir', () {
      final notice = workoutEndNoticeOf(ended(), pt, UnitSystem.metric);

      expect(notice.title, pt.failedTitle);
      expect(notice.text, pt.failedText);
      expect(notice.action, pt.open);
      expect(notice.link, endsWith('workout-summary'));
      expect(notice.link, _summaryLink);
      expect(notice.failed, isTrue);
      expect(notice.publicText, isNull);
    });

    test('both outcomes post on the live channel name', () {
      final saved = workoutEndNoticeOf(
        ended(),
        pt,
        UnitSystem.metric,
        workoutId: 42,
      );
      final failed = workoutEndNoticeOf(ended(), pt, UnitSystem.metric);

      expect(saved.channel, ptL10n.workoutNotificationChannel);
      expect(failed.channel, ptL10n.workoutNotificationChannel);
    });

    test('the failed notice does not depend on the units', () {
      final metric = workoutEndNoticeOf(ended(), en, UnitSystem.metric);
      final imperial = workoutEndNoticeOf(ended(), en, UnitSystem.imperial);

      expect(imperial, metric);
    });
  });

  group('the lock screen heart rate setting', () {
    test('shown leaves no lock screen text', () {
      final notice = workoutEndNoticeOf(
        ended(),
        pt,
        UnitSystem.metric,
        workoutId: 42,
      );

      expect(notice.publicText, isNull);
      expect(notice.failed, isFalse);
    });

    test('hidden gives the text with no heart rate', () {
      final notice = workoutEndNoticeOf(
        ended(),
        pt,
        UnitSystem.metric,
        workoutId: 42,
        hideHeartRate: true,
      );

      expect(notice.text, 'Corrida · 40:00 · 6,60 km · FC média 146');
      expect(notice.publicText, 'Corrida · 40:00 · 6,60 km');
    });

    test('hidden with no average keeps the same text', () {
      final notice = workoutEndNoticeOf(
        ended(average: null),
        pt,
        UnitSystem.metric,
        workoutId: 42,
        hideHeartRate: true,
      );

      expect(notice.publicText, notice.text);
    });

    test('the failed notice has no heart rate to hide', () {
      final notice = workoutEndNoticeOf(
        ended(),
        pt,
        UnitSystem.metric,
        hideHeartRate: true,
      );

      expect(notice.publicText, isNull);
    });
  });

  group('WorkoutEndNotice is a value', () {
    const notice = WorkoutEndNotice(
      title: 'Workout saved',
      text: 'Running · 40:00',
      action: 'See workout summary',
      link: '$_summaryLink/42',
    );

    test('equal fields are equal with the same hash', () {
      const same = WorkoutEndNotice(
        title: 'Workout saved',
        text: 'Running · 40:00',
        action: 'See workout summary',
        link: '$_summaryLink/42',
      );

      expect(same, notice);
      expect(same.hashCode, notice.hashCode);
    });

    final others = <String, WorkoutEndNotice>{
      'title': const WorkoutEndNotice(
        title: 'Other',
        text: 'Running · 40:00',
        action: 'See workout summary',
        link: '$_summaryLink/42',
      ),
      'text': const WorkoutEndNotice(
        title: 'Workout saved',
        text: 'Other',
        action: 'See workout summary',
        link: '$_summaryLink/42',
      ),
      'action': const WorkoutEndNotice(
        title: 'Workout saved',
        text: 'Running · 40:00',
        action: 'Open',
        link: '$_summaryLink/42',
      ),
      'link': const WorkoutEndNotice(
        title: 'Workout saved',
        text: 'Running · 40:00',
        action: 'See workout summary',
        link: '$_summaryLink/43',
      ),
      'channel': const WorkoutEndNotice(
        title: 'Workout saved',
        text: 'Running · 40:00',
        action: 'See workout summary',
        link: '$_summaryLink/42',
        channel: 'Treino',
      ),
      'publicText': const WorkoutEndNotice(
        title: 'Workout saved',
        text: 'Running · 40:00',
        action: 'See workout summary',
        link: '$_summaryLink/42',
        publicText: 'Running · 40:00',
      ),
      'failed': const WorkoutEndNotice(
        title: 'Workout saved',
        text: 'Running · 40:00',
        action: 'See workout summary',
        link: '$_summaryLink/42',
        failed: true,
      ),
    };

    for (final MapEntry(key: field, value: other) in others.entries) {
      test('a different $field is not equal', () {
        expect(other, isNot(notice));
      });
    }
  });
}
