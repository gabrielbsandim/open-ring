import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final pt = lookupAppLocalizations(const Locale('pt'));

  group('1: the alert strings in English and Portuguese', () {
    test('English', () {
      expect(en.workoutAlertChannel, 'Workout alerts');
      expect(
        en.workoutRingLostAlertTitle,
        'The ring stopped sending heart rate',
      );
      expect(
        en.workoutRingLostAlertText,
        'The workout is still recording. Tap to reconnect.',
      );
      expect(en.settingsRingLostAlert, 'Alert when the ring drops');
      expect(
        en.settingsRingLostAlertDetail,
        'Vibrates once if the heart rate stops for 30 s',
      );
    });

    test('Portuguese', () {
      expect(pt.workoutAlertChannel, 'Avisos do treino');
      expect(pt.workoutRingLostAlertTitle, 'O anel parou de enviar a FC');
      expect(
        pt.workoutRingLostAlertText,
        'O treino continua sendo gravado. Toque para reconectar.',
      );
      expect(pt.settingsRingLostAlert, 'Avisar quando o anel cair');
      expect(
        pt.settingsRingLostAlertDetail,
        'Vibra uma vez se a FC parar por 30 s',
      );
    });
  });

  group('1: the workout notice carries the alert labels', () {
    for (final (name, l10n) in [('en', en), ('pt', pt)]) {
      test(name, () {
        final labels = workoutLocationNotice(l10n).live;

        expect(labels.alertChannel, l10n.workoutAlertChannel);
        expect(labels.ringLostAlertTitle, l10n.workoutRingLostAlertTitle);
        expect(labels.ringLostAlertText, l10n.workoutRingLostAlertText);
        expect(labels.reconnect, l10n.workoutNoticeReconnect);
      });
    }
  });

  group('the alert strings exist in every locale', () {
    final dash = RegExp('[${String.fromCharCodes(const [0x2013, 0x2014])}]');

    for (final locale in AppLocalizations.supportedLocales) {
      test('$locale', () {
        final l10n = lookupAppLocalizations(locale);
        final strings = [
          l10n.workoutAlertChannel,
          l10n.workoutRingLostAlertTitle,
          l10n.workoutRingLostAlertText,
          l10n.settingsRingLostAlert,
          l10n.settingsRingLostAlertDetail,
        ];

        for (final string in strings) {
          expect(string.trim(), isNotEmpty);
          expect(string, isNot(contains(dash)));
        }
        if (locale.languageCode == 'en') return;
        expect(l10n.settingsRingLostAlert, isNot(en.settingsRingLostAlert));
        expect(
          l10n.workoutRingLostAlertTitle,
          isNot(en.workoutRingLostAlertTitle),
        );
      });
    }
  });
}
