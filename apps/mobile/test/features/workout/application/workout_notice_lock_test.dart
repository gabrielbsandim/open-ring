import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/workout/application/workout_notice.dart';
import 'package:open_ring/features/workout/domain/workout_notifier.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

void main() {
  final en = workoutLocationNotice(lookupAppLocalizations(const Locale('en')));

  WorkoutSnapshot run({
    WorkoutType type = WorkoutType.running,
    WorkoutStatus status = WorkoutStatus.running,
    bool gps = true,
    double? meters = 3920,
    int? bpm = 152,
    int? zone = 4,
  }) => WorkoutSnapshot(
    type: type,
    status: status,
    gps: gps,
    elapsed: const Duration(seconds: 1421),
    distanceMeters: meters,
    currentPace: const Duration(seconds: 352),
    currentHeartRate: bpm,
    currentZone: zone,
  );

  WorkoutNotice notice(
    WorkoutSnapshot snapshot, {
    bool? hide,
    bool ringLost = false,
    bool gpsLost = false,
    bool confirming = false,
  }) => hide == null
      ? workoutNoticeOf(
          snapshot,
          en,
          UnitSystem.metric,
          ringLost: ringLost,
          gpsLost: gpsLost,
          confirming: confirming,
        )
      : workoutNoticeOf(
          snapshot,
          en,
          UnitSystem.metric,
          ringLost: ringLost,
          gpsLost: gpsLost,
          confirming: confirming,
          hideHeartRate: hide,
        );

  group('1: no hiding keeps the public fields null', () {
    final states = <String, WorkoutNotice Function({bool? hide})>{
      'running': ({hide}) => notice(run(), hide: hide),
      'paused': ({hide}) =>
          notice(run(status: WorkoutStatus.paused), hide: hide),
      'ring lost': ({hide}) => notice(run(), hide: hide, ringLost: true),
      'confirming': ({hide}) => notice(
        run(status: WorkoutStatus.paused),
        hide: hide,
        confirming: true,
      ),
    };

    for (final MapEntry(key: name, value: build) in states.entries) {
      test('$name, by default', () {
        final result = build();

        expect(result.publicTitle, isNull);
        expect(result.publicText, isNull);
      });

      test('$name, with hideHeartRate false', () {
        final result = build(hide: false);

        expect(result.publicTitle, isNull);
        expect(result.publicText, isNull);
      });
    }
  });

  group('2: a GPS run in zone 4 at 152 bpm', () {
    test('the public version names the type and drops the zone', () {
      final result = notice(run(), hide: true);

      expect(result.publicTitle, 'Running');
    });

    test('the public text keeps distance and pace and no bpm', () {
      final result = notice(run(), hide: true);

      expect(result.publicText, '3.92 km · 5:52 /km');
      expect(result.publicText, isNot(contains('bpm')));
    });

    test('the private notice is unchanged', () {
      final result = notice(run(), hide: true);

      expect(result.title, 'Running · Zone 4');
      expect(result.text, '152 bpm · 3.92 km · 5:52 /km');
    });

    test('GPS lost keeps only the GPS message in public', () {
      final result = notice(run(), hide: true, gpsLost: true);

      expect(result.publicText, en.live.gpsLost);
      expect(result.text, '152 bpm · ${en.live.gpsLost}');
    });
  });

  group('3: no GPS', () {
    test('strength with a heart rate shows the recording label', () {
      final result = notice(
        run(type: WorkoutType.strength, gps: false, meters: null, zone: 2),
        hide: true,
      );

      expect(result.publicText, en.live.recording);
      expect(result.publicTitle, en.live.types[WorkoutType.strength]);
      expect(result.text, '152 bpm');
    });
  });

  group('4: ring lost', () {
    test('the public title is the ring lost title', () {
      final result = notice(run(), hide: true, ringLost: true);

      expect(result.publicTitle, en.live.ringLostTitle('Running'));
      expect(result.title, en.live.ringLostTitle('Running'));
    });

    test('the public text drops the placeholder', () {
      final result = notice(run(), hide: true, ringLost: true);

      expect(result.publicText, '3.92 km · 5:52 /km');
      expect(result.publicText, isNot(contains('--')));
      expect(result.publicText, isNot(contains('bpm')));
      expect(result.text, '-- bpm · 3.92 km · 5:52 /km');
    });

    test('an indoor ring lost workout falls back to recording', () {
      final result = notice(
        run(type: WorkoutType.strength, gps: false, meters: null),
        hide: true,
        ringLost: true,
      );

      expect(result.publicText, en.live.recording);
    });
  });

  group('5: paused and confirming carry no heart rate', () {
    test('paused public equals private', () {
      final result = notice(run(status: WorkoutStatus.paused), hide: true);

      expect(result.publicTitle, result.title);
      expect(result.publicText, result.text);
      expect(result.publicTitle, isNotNull);
    });

    test('confirming public equals private', () {
      final result = notice(
        run(status: WorkoutStatus.paused),
        hide: true,
        confirming: true,
      );

      expect(result.publicTitle, result.title);
      expect(result.publicText, result.text);
      expect(result.publicTitle, en.live.confirmTitle);
    });
  });

  group('the public fields take part in equality', () {
    const base = WorkoutNotice(
      title: 'Running',
      text: '148 bpm',
      elapsed: Duration(seconds: 5),
      running: true,
    );

    test('a different public title is not equal', () {
      const other = WorkoutNotice(
        title: 'Running',
        text: '148 bpm',
        elapsed: Duration(seconds: 5),
        running: true,
        publicTitle: 'Running',
      );

      expect(other, isNot(base));
    });

    test('a different public text is not equal', () {
      const other = WorkoutNotice(
        title: 'Running',
        text: '148 bpm',
        elapsed: Duration(seconds: 5),
        running: true,
        publicText: '3 km',
      );

      expect(other, isNot(base));
    });

    test('equal public fields give equal hashes', () {
      const a = WorkoutNotice(
        title: 'Running',
        text: '148 bpm',
        elapsed: Duration(seconds: 5),
        running: true,
        publicTitle: 'Running',
        publicText: '3 km',
      );
      const b = WorkoutNotice(
        title: 'Running',
        text: '148 bpm',
        elapsed: Duration(seconds: 5),
        running: true,
        publicTitle: 'Running',
        publicText: '3 km',
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
