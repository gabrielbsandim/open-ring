import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  test('criterion 2: the English strings are the ones the spec fixes', () {
    expect(en.moduleOpenScoreDataTitle, 'Open Score data');
    expect(en.moduleOpenScoreDataEmpty, 'No day tags stored on this phone.');
    expect(en.moduleOpenScoreDataCount(3), 'Day tags stored on this phone: 3.');
    expect(en.moduleOpenScoreDataGoal(6), 'Weekly goal: 6 of 7 days.');
    expect(
      en.moduleOpenScoreKept(3),
      'Open Score is off. Day tags kept on this phone: 3. They count again '
      'when you turn it on.',
    );
    expect(en.moduleOpenScoreDelete, 'Delete Open Score data');
    expect(en.moduleOpenScoreDeleteTitle, 'Delete the Open Score data?');
    expect(
      en.moduleOpenScoreDeleteBody(3, weekGoalDefault),
      'Day tags to delete: 3. The weekly goal goes back to 4 of 7. This '
      'cannot be undone. A tag older than 6 days cannot be set again, and '
      'the Level, the bests and the averages count those days again.',
    );
    expect(en.moduleOpenScoreDeleted, 'Open Score data deleted.');
    expect(
      en.moduleOpenScoreDeleteFailed,
      'The Open Score data could not be deleted. Try again.',
    );
    expect(
      en.moduleOpenScoreUsesStore,
      'It stores only your day tags, your weekly goal and the day you last '
      'closed a celebration card: the score is always recalculated from the '
      "ring's data.",
    );
  });

  group('criterion 8: every locale carries the new keys', () {
    for (final locale in AppLocales.supported) {
      test('moduleOpenScore data strings in $locale', () {
        final l = lookupAppLocalizations(locale);
        final texts = [
          l.moduleOpenScoreDataTitle,
          l.moduleOpenScoreDataEmpty,
          l.moduleOpenScoreDataCount(3),
          l.moduleOpenScoreDataGoal(6),
          l.moduleOpenScoreKept(3),
          l.moduleOpenScoreDelete,
          l.moduleOpenScoreDeleteTitle,
          l.moduleOpenScoreDeleteBody(3, weekGoalDefault),
          l.moduleOpenScoreDeleted,
          l.moduleOpenScoreDeleteFailed,
          l.moduleOpenScoreUsesStore,
        ];

        for (final text in texts) {
          expect(text.trim(), isNotEmpty);
        }
        expect(l.moduleOpenScoreDataCount(3), contains('3'));
        expect(l.moduleOpenScoreDataGoal(6), contains('6'));
        expect(l.moduleOpenScoreKept(3), contains('3'));
        expect(l.moduleOpenScoreDeleteBody(3, weekGoalDefault), contains('3'));
        expect(
          l.moduleOpenScoreDeleteBody(3, weekGoalDefault),
          contains('$weekGoalDefault'),
        );
        if (locale.languageCode == 'en') return;
        expect(l.moduleOpenScoreDataTitle, isNot(en.moduleOpenScoreDataTitle));
        expect(l.moduleOpenScoreDelete, isNot(en.moduleOpenScoreDelete));
        expect(
          l.moduleOpenScoreDeleteBody(3, weekGoalDefault),
          isNot(en.moduleOpenScoreDeleteBody(3, weekGoalDefault)),
        );
        expect(l.moduleOpenScoreKept(3), isNot(en.moduleOpenScoreKept(3)));
        expect(l.moduleOpenScoreUsesStore, isNot(en.moduleOpenScoreUsesStore));
      });
    }
  });

  group('criterion 8: plurals', () {
    test('ru has distinct plural forms of the delete body', () {
      final l = lookupAppLocalizations(const Locale('ru'));
      final forms = {
        for (final n in [1, 2, 5])
          l.moduleOpenScoreDeleteBody(n, weekGoalDefault).replaceAll('$n', '#'),
      };

      expect(forms, hasLength(3));
    });

    test('ru carries the count in every plural message', () {
      final l = lookupAppLocalizations(const Locale('ru'));

      for (final n in [0, 1, 2, 5, 21]) {
        expect(l.moduleOpenScoreDeleteBody(n, weekGoalDefault), contains('$n'));
        expect(l.moduleOpenScoreKept(n), contains('$n'));
        expect(l.moduleOpenScoreDataCount(n), contains('$n'));
      }
    });

    test('ja carries the count in every plural message', () {
      final l = lookupAppLocalizations(const Locale('ja'));

      for (final n in [0, 1, 2, 5, 21]) {
        expect(l.moduleOpenScoreDeleteBody(n, weekGoalDefault), contains('$n'));
        expect(l.moduleOpenScoreKept(n), contains('$n'));
        expect(l.moduleOpenScoreDataCount(n), contains('$n'));
      }
    });

    test('every locale carries the count at 0, 1, 2, 5 and 21', () {
      for (final locale in AppLocales.supported) {
        final l = lookupAppLocalizations(locale);
        for (final n in [0, 1, 2, 5, 21]) {
          expect(
            l.moduleOpenScoreDataCount(n),
            contains('$n'),
            reason: '$locale $n',
          );
          expect(
            l.moduleOpenScoreKept(n),
            contains('$n'),
            reason: '$locale $n',
          );
        }
      }
    });
  });
}
