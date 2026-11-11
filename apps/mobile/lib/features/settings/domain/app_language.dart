import 'package:flutter/widgets.dart';

enum AppLanguage {
  system(null),
  english(Locale('en')),
  portugueseBrazil(Locale('pt')),
  portuguesePortugal(Locale('pt', 'PT')),
  spanish(Locale('es')),
  french(Locale('fr')),
  german(Locale('de')),
  italian(Locale('it')),
  russian(Locale('ru')),
  chineseSimplified(Locale('zh')),
  japanese(Locale('ja')),
  indonesian(Locale('id'));

  new(this.locale);

  final Locale? locale;

  static const AppLanguage fallback = AppLanguage.english;

  static AppLanguage of(Locale locale) => values.firstWhere(
    (language) => language.locale == locale,
    orElse: () => fallback,
  );
}

abstract interface class AppLanguageStore {
  AppLanguage? read();

  Future<void> write(AppLanguage language);
}

final class InMemoryAppLanguageStore implements AppLanguageStore {
  new([this.language]);

  AppLanguage? language;

  @override
  AppLanguage? read() => language;

  @override
  Future<void> write(AppLanguage language) async => this.language = language;
}
