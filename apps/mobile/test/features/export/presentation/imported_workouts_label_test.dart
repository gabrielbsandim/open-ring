import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

const _locales = [
  Locale('en'),
  Locale('pt'),
  Locale('pt', 'PT'),
  Locale('es'),
  Locale('fr'),
  Locale('de'),
  Locale('it'),
  Locale('id'),
  Locale('ru'),
  Locale('ja'),
  Locale('zh'),
];

void main() {
  test('English reads Workouts from other apps', () {
    expect(
      lookupAppLocalizations(const Locale('en')).exportKindImportedWorkouts,
      'Workouts from other apps',
    );
  });

  for (final locale in _locales) {
    test('$locale carries the imported workouts export label', () {
      final l10n = lookupAppLocalizations(locale);

      expect(l10n.exportKindImportedWorkouts.trim(), isNotEmpty);
      expect(l10n.exportKindImportedWorkouts, l10n.sourcesReadWorkouts);
    });
  }
}
