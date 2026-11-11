import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/workout/domain/location_fix.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

import '../../../helpers/workout_fakes.dart';

DateTime at(int seconds) => workoutStart.add(Duration(seconds: seconds));

WorkoutSession running({
  WorkoutType type = WorkoutType.running,
  WorkoutProfile profile = const WorkoutProfile(),
}) => WorkoutSession(type: type, profile: profile)..start(workoutStart);

void runAt(
  WorkoutSession session, {
  required int from,
  required int to,
  required double speed,
  double startMeters = 0,
}) {
  for (var s = from; s <= to; s++) {
    session.addFix(
      fixAt(
        Duration(seconds: s),
        northMeters: startMeters + (s - from) * speed,
      ),
    );
  }
}

void main() {
  group('state machine', () {
    test('moves idle, running, paused, running, finished', () {
      final session = WorkoutSession(type: WorkoutType.running);
      expect(session.status, WorkoutStatus.idle);

      session.start(at(0));
      expect(session.status, WorkoutStatus.running);
      session.pause(at(10));
      expect(session.status, WorkoutStatus.paused);
      session.resume(at(20));
      expect(session.status, WorkoutStatus.running);
      session.finish(at(30));

      expect(session.status, WorkoutStatus.finished);
      expect(session.startedAt, at(0));
      expect(session.endedAt, at(30));
    });

    test('rejects transitions the current state does not allow', () {
      final session = WorkoutSession(type: WorkoutType.walking);

      expect(() => session.pause(at(1)), throwsStateError);
      expect(() => session.finish(at(1)), throwsStateError);
      session.start(at(0));
      expect(() => session.start(at(1)), throwsStateError);
      expect(() => session.resume(at(1)), throwsStateError);
      session.finish(at(2));
      expect(() => session.discard(at(3)), throwsStateError);
      expect(() => session.pause(at(3)), throwsStateError);
    });

    test('a discarded session cannot be finished or read as finished', () {
      final session = running()..discard(at(5));

      expect(session.status, WorkoutStatus.discarded);
      expect(() => session.finish(at(6)), throwsStateError);
      expect(session.finished, throwsStateError);
    });
  });

  group('elapsed time', () {
    test('excludes every pause and freezes while paused', () {
      final session = running();

      expect(session.elapsedAt(at(10)), const Duration(seconds: 10));
      session.pause(at(10));
      expect(session.elapsedAt(at(70)), const Duration(seconds: 10));
      session.resume(at(70));
      expect(session.elapsedAt(at(80)), const Duration(seconds: 20));
      session
        ..pause(at(90))
        ..resume(at(100))
        ..finish(at(130));

      expect(session.elapsedAt(at(999)), const Duration(seconds: 60));
      expect(session.pauses.map((p) => (p.start, p.end)), [
        (at(10), at(70)),
        (at(90), at(100)),
      ]);
    });

    test('finishing while paused closes the open pause at the end', () {
      final session = running()
        ..pause(at(60))
        ..finish(at(120));

      expect(session.elapsedAt(at(500)), const Duration(seconds: 60));
      expect(session.pauses.single.duration, const Duration(seconds: 60));
    });

    test(
      'a clock that steps back gives an empty pause, not a negative one',
      () {
        final session = running()
          ..pause(at(10))
          ..resume(at(5));

        expect(session.pauses.single.duration, Duration.zero);
        expect(session.elapsedAt(at(20)), const Duration(seconds: 20));
      },
    );
  });

  group('GPS filtering', () {
    test('drops fixes worse than 25 m or with no usable accuracy', () {
      final session = running();

      expect(
        session.addFix(
          fixAt(Duration.zero, northMeters: 0, accuracyMeters: 25),
        ),
        FixVerdict.accepted,
      );
      for (final accuracy in [25.1, double.nan, -1.0, double.infinity]) {
        expect(
          session.addFix(
            fixAt(
              const Duration(seconds: 1),
              northMeters: 3,
              accuracyMeters: accuracy,
            ),
          ),
          FixVerdict.inaccurate,
          reason: '$accuracy m',
        );
      }
      expect(session.snapshotAt(at(1)).trackPoints, 1);
    });

    test('drops a fix implying more than 12 m/s and keeps the reference', () {
      final session = running()..addFix(fixAt(Duration.zero, northMeters: 0));

      expect(
        session.addFix(fixAt(const Duration(seconds: 1), northMeters: 12.5)),
        FixVerdict.tooFast,
      );
      expect(
        session.addFix(fixAt(const Duration(seconds: 2), northMeters: 23.5)),
        FixVerdict.accepted,
      );
      expect(session.distanceMeters, closeTo(23.5, 1e-6));
    });

    test('drops fixes out of order, before the start or off the globe', () {
      final session = running()
        ..addFix(fixAt(const Duration(seconds: 5), northMeters: 0));

      expect(
        session.addFix(fixAt(const Duration(seconds: 5), northMeters: 1)),
        FixVerdict.outOfOrder,
      );
      expect(
        session.addFix(fixAt(const Duration(seconds: -1), northMeters: 1)),
        FixVerdict.outOfOrder,
      );
      expect(
        session.addFix(
          LocationFix(at: at(6), latitude: 91, longitude: 0, accuracyMeters: 5),
        ),
        FixVerdict.invalid,
      );
    });

    test('ignores fixes while paused and never bridges a pause', () {
      final session = running();
      runAt(session, from: 0, to: 10, speed: 3);
      session.pause(at(10));

      expect(
        session.addFix(fixAt(const Duration(seconds: 30), northMeters: 60)),
        FixVerdict.notRunning,
      );
      session.resume(at(70));
      expect(
        session.addFix(fixAt(const Duration(seconds: 69), northMeters: 300)),
        FixVerdict.outOfOrder,
      );
      runAt(session, from: 71, to: 81, speed: 3, startMeters: 300);

      expect(session.distanceMeters, closeTo(60, 1e-6));
      expect(session.route.segments.map((s) => s.length), [11, 11]);
      expect(session.route.distanceMeters, closeTo(60, 1e-6));
    });
  });

  group('pace', () {
    test('current pace covers the last 30 s, average the whole session', () {
      final session = running();
      runAt(session, from: 0, to: 20, speed: 2);
      runAt(session, from: 21, to: 50, speed: 4, startMeters: 44);

      final snapshot = session.snapshotAt(at(50));

      expect(snapshot.distanceMeters, closeTo(160, 1e-6));
      expect(snapshot.currentPace!.inMilliseconds, closeTo(250000, 1));
      expect(snapshot.averagePace!.inMilliseconds, closeTo(312500, 1));
    });

    test('current pace waits for two fixes after a resume', () {
      final session = running();
      runAt(session, from: 0, to: 30, speed: 3);
      expect(session.currentPaceAt(at(30))!.inMilliseconds, closeTo(333333, 1));

      session
        ..pause(at(30))
        ..resume(at(40))
        ..addFix(fixAt(const Duration(seconds: 41), northMeters: 200));

      expect(session.currentPaceAt(at(41)), isNull);
      expect(session.averagePaceAt(at(41)), isNotNull);
    });

    test('current pace goes empty when fixes stop arriving', () {
      final session = running();
      runAt(session, from: 0, to: 30, speed: 3);

      expect(session.currentPaceAt(at(61)), isNull);
    });

    test('there is no pace below 5 m or while paused', () {
      final session = running();
      runAt(session, from: 0, to: 4, speed: 1);

      expect(session.averagePaceAt(at(4)), isNull);
      expect(session.currentPaceAt(at(4)), isNull);
      runAt(session, from: 5, to: 10, speed: 3, startMeters: 4);
      session.pause(at(10));
      expect(session.currentPaceAt(at(10)), isNull);
    });

    test('an indoor workout reports no distance or pace', () {
      final snapshot = running(type: WorkoutType.other).snapshotAt(at(60));

      expect(snapshot.distanceMeters, isNull);
      expect(snapshot.currentPace, isNull);
      expect(snapshot.averagePace, isNull);
    });
  });

  group('heart rate', () {
    test('keeps plausible readings while running, with average and max', () {
      final session = running();

      expect(session.addHeartRate(29, at(1)), isFalse);
      expect(session.addHeartRate(221, at(1)), isFalse);
      session
        ..addHeartRate(120, at(1))
        ..addHeartRate(141, at(2))
        ..pause(at(3));
      expect(session.addHeartRate(180, at(4)), isFalse);
      session
        ..resume(at(5))
        ..addHeartRate(130, at(6));

      expect(session.heartRate.map((s) => s.bpm), [120, 141, 130]);
      expect(session.averageHeartRate, 130);
      expect(session.maxHeartRate, 141);
    });

    test(
      'the current zone follows 220 minus age and goes stale after 10 s',
      () {
        final session = running(
          profile: WorkoutProfile(zones: HeartRateZones(age: 30)),
        )..addHeartRate(150, at(20));

        final live = session.snapshotAt(at(30));
        expect(live.currentHeartRate, 150);
        expect(live.currentZone, 3);

        session.addHeartRate(172, at(31));
        expect(session.snapshotAt(at(31)).currentZone, 5);
        session.addHeartRate(90, at(32));
        expect(session.snapshotAt(at(32)).currentZone, isNull);

        final stale = session.snapshotAt(at(43));
        expect(stale.currentHeartRate, isNull);
        expect(stale.currentZone, isNull);
      },
    );

    test('a longer hold keeps the last reading until it runs out', () {
      final session =
          WorkoutSession(
              type: WorkoutType.running,
              heartRateHold: const Duration(seconds: 30),
            )
            ..start(workoutStart)
            ..addHeartRate(80, at(20));

      expect(session.snapshotAt(at(49)).currentHeartRate, 80);
      expect(session.snapshotAt(at(50)).currentHeartRate, 80);
      expect(session.snapshotAt(at(51)).currentHeartRate, isNull);
    });

    test('a reading from before the link restarted is not current', () {
      final session =
          WorkoutSession(
              type: WorkoutType.running,
              heartRateHold: const Duration(seconds: 30),
            )
            ..start(workoutStart)
            ..heartRateLinkStart = at(0)
            ..addHeartRate(80, at(5))
            ..heartRateLinkStart = at(10);

      expect(session.snapshotAt(at(11)).currentHeartRate, isNull);
      expect(session.averageHeartRate, 80);

      session.addHeartRate(90, at(12));
      expect(session.snapshotAt(at(12)).currentHeartRate, 90);
    });

    test('without zones there is no current zone', () {
      final session = running()..addHeartRate(150, at(1));

      expect(session.snapshotAt(at(1)).currentHeartRate, 150);
      expect(session.snapshotAt(at(1)).currentZone, isNull);
    });
  });

  group('energy', () {
    test('is (MET - 1) x weight x moving hours', () {
      final session =
          running(profile: const WorkoutProfile(weightKilograms: 70))
            ..pause(at(600))
            ..resume(at(1200))
            ..finish(at(2400));

      expect(session.activeKilocaloriesAt(at(2400)), closeTo(308, 1e-9));
      expect(session.finished().activeKilocalories, closeTo(308, 1e-9));
    });

    test('is unknown without a weight', () {
      expect(running().activeKilocaloriesAt(at(600)), isNull);
    });
  });

  test('the finished record carries every series of the session', () {
    final session = running(profile: const WorkoutProfile(weightKilograms: 60));
    runAt(session, from: 0, to: 10, speed: 3);
    session
      ..addHeartRate(140, at(5))
      ..pause(at(10))
      ..resume(at(20))
      ..finish(at(30));

    final workout = session.finished();

    expect(workout.type, WorkoutType.running);
    expect((workout.start, workout.end), (at(0), at(30)));
    expect(workout.elapsed, const Duration(seconds: 20));
    expect(workout.distanceMeters, closeTo(30, 1e-6));
    expect(workout.heartRate.single.bpm, 140);
    expect(workout.route.points, hasLength(11));
    expect(workout.route.points.first.accuracyMeters, 5);
    expect(workout.pauses.single.start, at(10));
    expect(workout.averageHeartRate, 140);
  });

  group('GPS choice', () {
    test('an outdoor type with GPS off takes no fixes and has no distance', () {
      final session = WorkoutSession(type: WorkoutType.running, gps: false)
        ..start(workoutStart);

      expect(
        session.addFix(fixAt(const Duration(seconds: 1), northMeters: 0)),
        FixVerdict.notRunning,
      );
      final snapshot = session.snapshotAt(at(10));
      expect(snapshot.gps, isFalse);
      expect(snapshot.distanceMeters, isNull);
      session.finish(at(10));
      expect(session.finished().gps, isFalse);
      expect(session.finished().distanceMeters, isNull);
    });

    test('other turns GPS on when asked and an indoor type never does', () {
      final other = WorkoutSession(type: WorkoutType.other, gps: true);
      final yoga = WorkoutSession(type: WorkoutType.yoga, gps: true);

      expect(other.gps, isTrue);
      expect(yoga.gps, isFalse);
      expect(WorkoutSession(type: WorkoutType.other).gps, isFalse);
      expect(WorkoutSession(type: WorkoutType.hiking).gps, isTrue);
    });

    test('energy of a new type uses its MET', () {
      final session = running(
        type: WorkoutType.yoga,
        profile: const WorkoutProfile(weightKilograms: 60),
      );

      expect(
        session.activeKilocaloriesAt(at(3600)),
        closeTo((2.5 - 1) * 60, 1e-9),
      );
    });
  });
}
