import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

const _suffixes = [
  'Tile',
  'TileDetail',
  'Title',
  'Lead',
  'Shows',
  'Sources',
  'Updates',
  'Buttons',
  'After',
  'Never',
  'Fields',
  'Zone',
  'Paused',
  'Lock',
  'Time',
  'HeartRate',
  'Gps',
  'Cadence',
  'End',
  'Result',
  'Closed',
  'Scores',
  'Sound',
];

final _dashes = RegExp(
  '[${String.fromCharCode(0x2013)}${String.fromCharCode(0x2014)}]',
);

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('the How it works screen has 23 keys', () {
    expect(_suffixes, hasLength(23));
  });

  for (final locale in AppLocales.supported) {
    group('$locale', () {
      final name = locale.toString();
      final l = lookupAppLocalizations(locale);

      test('6: holds the 23 keys, each with a text and no dash', () {
        final arb = _arb(name);
        final keys = [for (final suffix in _suffixes) 'workoutHow$suffix'];
        final missing = [
          for (final key in keys)
            if (arb[key] is! String || (arb[key] as String).trim().isEmpty) key,
        ];
        final dashed = [
          for (final key in keys)
            if ('${arb[key]}'.contains(_dashes)) key,
        ];
        expect(missing, isEmpty);
        expect(dashed, isEmpty);
      });

      test('4: End names End, Save and Continue', () {
        expect(l.workoutHowEnd, contains(l.workoutEnd));
        expect(l.workoutHowEnd, contains(l.workoutNoticeSave));
        expect(l.workoutHowEnd, contains(l.workoutNoticeKeep));
      });

      test('4: Paused names Resume and End', () {
        expect(l.workoutHowPaused, contains(l.workoutResume));
        expect(l.workoutHowPaused, contains(l.workoutEnd));
      });

      test('4: Lock names the lock screen switch', () {
        expect(l.workoutHowLock, contains(l.settingsLockHeartRate));
      });

      test('4: Sound names the ring lost switch', () {
        expect(l.workoutHowSound, contains(l.settingsRingLostAlert));
      });

      test('4: Gps names the GPS lost line', () {
        expect(l.workoutHowGps, contains(l.workoutNoticeGpsLost));
      });

      test('4: HeartRate names Reconnect', () {
        expect(l.workoutHowHeartRate, contains(l.workoutNoticeReconnect));
      });

      test('4: Zone names Profile', () {
        expect(l.workoutHowZone, contains(l.settingsProfile));
      });
    });
  }
}
