import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/l10n/app_locales.dart';

Locale resolve(List<Locale>? preferred) =>
    AppLocales.resolve(preferred, AppLocales.supported);

void main() {
  group('supported', () {
    test('lists English first', () {
      expect(AppLocales.supported.first, const Locale('en'));
    });

    test('ships the eleven decided locales once each', () {
      expect(AppLocales.supported.toSet(), {
        const Locale('en'),
        const Locale('pt'),
        const Locale('pt', 'PT'),
        const Locale('es'),
        const Locale('fr'),
        const Locale('de'),
        const Locale('it'),
        const Locale('ru'),
        const Locale('zh'),
        const Locale('ja'),
        const Locale('id'),
      });
      expect(AppLocales.supported, hasLength(11));
    });
  });

  group('resolve', () {
    test('Brazilian Portuguese lands on pt', () {
      expect(resolve([const Locale('pt', 'BR')]), const Locale('pt'));
    });

    test('European Portuguese lands on pt_PT', () {
      expect(resolve([const Locale('pt', 'PT')]), const Locale('pt', 'PT'));
    });

    test('any other Portuguese country lands on pt, not pt_PT', () {
      expect(resolve([const Locale('pt', 'AO')]), const Locale('pt'));
    });

    test('Traditional Chinese lands on zh', () {
      expect(
        resolve([
          const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hant',
            countryCode: 'TW',
          ),
        ]),
        const Locale('zh'),
      );
    });

    test('Mexican Spanish lands on es', () {
      expect(resolve([const Locale('es', 'MX')]), const Locale('es'));
    });

    test('a bare supported language matches itself', () {
      expect(resolve([const Locale('ru')]), const Locale('ru'));
    });

    test('an unsupported language falls back to English', () {
      expect(resolve([const Locale('ar')]), const Locale('en'));
    });

    test('the first supported preference wins over the fallback', () {
      expect(
        resolve([const Locale('ar'), const Locale('fr')]),
        const Locale('fr'),
      );
    });

    test('no preference falls back to English', () {
      expect(resolve(const []), const Locale('en'));
      expect(resolve(null), const Locale('en'));
    });

    test('an empty country subtag is treated as absent', () {
      expect(resolve([const Locale('pt', '')]), const Locale('pt'));
    });
  });
}
