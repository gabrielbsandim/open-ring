import 'package:flutter/widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class AppLocales {
  static const fallback = Locale('en');

  static final List<Locale> supported = [
    fallback,
    ...AppLocalizations.supportedLocales.where((locale) => locale != fallback),
  ];

  static Locale resolve(List<Locale>? preferred, Iterable<Locale> available) {
    for (final wanted in preferred ?? const <Locale>[]) {
      final match =
          _byCountry(wanted, available) ??
          _byScript(wanted, available) ??
          _byLanguage(wanted, available);
      if (match != null) return match;
    }
    return fallback;
  }

  static Locale? _byCountry(Locale wanted, Iterable<Locale> available) {
    final country = _subtag(wanted.countryCode);
    if (country == null) return null;
    return _sameLanguage(
      wanted,
      available,
    ).where((locale) => locale.countryCode == country).firstOrNull;
  }

  static Locale? _byScript(Locale wanted, Iterable<Locale> available) {
    final script = _subtag(wanted.scriptCode);
    if (script == null) return null;
    return _sameLanguage(
      wanted,
      available,
    ).where((locale) => locale.scriptCode == script).firstOrNull;
  }

  // The bare language wins so pt_AO lands on pt, not on the pt_PT override.
  static Locale? _byLanguage(Locale wanted, Iterable<Locale> available) {
    final candidates = _sameLanguage(wanted, available);
    return candidates.where(_isBare).firstOrNull ?? candidates.firstOrNull;
  }

  static Iterable<Locale> _sameLanguage(
    Locale wanted,
    Iterable<Locale> available,
  ) => available.where((locale) => locale.languageCode == wanted.languageCode);

  static bool _isBare(Locale locale) =>
      _subtag(locale.countryCode) == null && _subtag(locale.scriptCode) == null;

  static String? _subtag(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }
}
