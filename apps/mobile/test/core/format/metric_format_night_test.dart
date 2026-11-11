import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

MetricFormat _format(String locale) =>
    MetricFormat(lookupAppLocalizations(Locale(locale)), locale);

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  test('a day-first locale shows the start day alone within a month', () {
    expect(
      _format('pt').nightOf(const LocalDate(2026, 11, 10)),
      'Noite de 9 para 10 de nov.',
    );
  });

  test('the start keeps its month when the night crosses months', () {
    expect(
      _format('pt').nightOf(const LocalDate(2026, 12, 1)),
      'Noite de 30 de nov. para 1 de dez.',
    );
  });

  test('a month-first locale keeps both dates whole', () {
    expect(
      _format('en').nightOf(const LocalDate(2026, 11, 10)),
      'Night of Nov 9 to Nov 10',
    );
  });
}
