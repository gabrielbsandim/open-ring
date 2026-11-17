import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/workout/application/workout_notice.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/workout_fakes.dart';

void main() {
  final pt = workoutLocationNotice(lookupAppLocalizations(const Locale('pt')));
  final en = workoutLocationNotice(lookupAppLocalizations(const Locale('en')));

  WorkoutSnapshot run({
    WorkoutType type = WorkoutType.running,
    WorkoutStatus status = WorkoutStatus.running,
    bool gps = true,
    int seconds = 1421,
    double? meters = 3920,
    Duration? pace = const Duration(seconds: 352),
    int? bpm = 152,
    int? zone = 4,
  }) => WorkoutSnapshot(
    type: type,
    status: status,
    gps: gps,
    elapsed: Duration(seconds: seconds),
    distanceMeters: meters,
    currentPace: pace,
    currentHeartRate: bpm,
    currentZone: zone,
  );

  group('title names the type and the zone', () {
    test('a run in zone 4', () {
      final notice = workoutNoticeOf(run(), pt, UnitSystem.metric);

      expect(notice.title, 'Corrida · Zona 4');
      expect(notice.text, '152 bpm · 3,92 km · 5:52 /km');
    });

    test('no zone keeps the type alone', () {
      final notice = workoutNoticeOf(run(zone: null), pt, UnitSystem.metric);

      expect(notice.title, 'Corrida');
    });

    test('a zone with no heart rate keeps the type alone', () {
      final notice = workoutNoticeOf(run(bpm: null), pt, UnitSystem.metric);

      expect(notice.title, 'Corrida');
    });

    test('strength has no generic title', () {
      final notice = workoutNoticeOf(
        run(type: WorkoutType.strength, gps: false, meters: null, zone: 2),
        pt,
        UnitSystem.metric,
      );

      expect(notice.title, 'Musculação · Zona 2');
      expect(notice.text, '152 bpm');
    });

    test('labels with no type names keep the old title', () {
      final notice = workoutNoticeOf(run(), testNotice, UnitSystem.metric);

      expect(notice.title, testNotice.title);
    });
  });

  group('cycling shows speed', () {
    test('145.2 s/km shows as 24,8 km/h', () {
      final notice = workoutNoticeOf(
        run(
          type: WorkoutType.cycling,
          pace: const Duration(milliseconds: 145200),
        ),
        pt,
        UnitSystem.metric,
      );

      expect(notice.text, '152 bpm · 3,92 km · 24,8 km/h');
    });

    test('imperial cycling shows mph', () {
      final notice = workoutNoticeOf(
        run(
          type: WorkoutType.cycling,
          pace: const Duration(milliseconds: 145200),
        ),
        en,
        UnitSystem.imperial,
      );

      expect(notice.text, '152 bpm · 2.44 mi · 15.4 mph');
    });

    test('running keeps pace', () {
      final notice = workoutNoticeOf(run(), en, UnitSystem.imperial);

      expect(notice.text, endsWith('9:26 /mi'));
    });
  });

  group('paused shows the frozen time', () {
    test('a run paused at 23:41 and 3,92 km', () {
      final notice = workoutNoticeOf(
        run(status: WorkoutStatus.paused),
        pt,
        UnitSystem.metric,
      );

      expect(notice.title, 'Corrida · Pausado');
      expect(notice.text, 'Pausado em 23:41 · 3,92 km');
      expect(notice.running, isFalse);
    });

    test('an indoor pause past an hour', () {
      final notice = workoutNoticeOf(
        run(
          type: WorkoutType.strength,
          status: WorkoutStatus.paused,
          gps: false,
          seconds: 3725,
        ),
        pt,
        UnitSystem.metric,
      );

      expect(notice.text, 'Pausado em 1:02:05');
    });
  });

  group('lost and empty states', () {
    test('ring lost names it in the title and blanks the heart rate', () {
      final notice = workoutNoticeOf(
        run(),
        pt,
        UnitSystem.metric,
        ringLost: true,
      );

      expect(notice.title, 'Corrida · anel fora de alcance');
      expect(notice.text, '-- bpm · 3,92 km · 5:52 /km');
    });

    test('GPS lost replaces distance and pace', () {
      final notice = workoutNoticeOf(
        run(),
        pt,
        UnitSystem.metric,
        gpsLost: true,
      );

      expect(notice.text, '152 bpm · Sinal de GPS perdido');
    });

    test('nothing to show yet says it is recording', () {
      final notice = workoutNoticeOf(
        run(type: WorkoutType.yoga, gps: false, bpm: null, zone: null),
        pt,
        UnitSystem.metric,
      );

      expect(notice.text, 'Gravando o tempo');
    });
  });
}
