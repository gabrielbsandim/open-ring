import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

const _minusSign = '−';

final class MetricFormat {
  const new(this.l10n, this.locale);

  factory of(BuildContext context) => MetricFormat(
    AppLocalizations.of(context),
    Localizations.localeOf(context).toString(),
  );

  final AppLocalizations l10n;
  final String locale;

  String duration(Duration value) {
    final minutes = (value.inSeconds / 60).round();
    if (minutes < 60) return l10n.metricDurationMinutes(minutes);
    if (minutes % 60 == 0) return l10n.metricDurationHours(minutes ~/ 60);
    return l10n.metricDurationHoursMinutes(minutes ~/ 60, minutes % 60);
  }

  String clock(DateTime instant, Duration utcOffset) =>
      DateFormat.Hm(locale).format(_wall(instant, utcOffset));

  String dayAndClock(DateTime instant, Duration utcOffset) =>
      DateFormat.MMMd(locale).add_Hm().format(_wall(instant, utcOffset));

  String clockOrDay(DateTime instant, DateTime now) {
    final offset = now.timeZoneOffset;
    final sameDay =
        LocalDate.fromInstant(instant, offset) ==
        LocalDate.fromInstant(now, offset);
    if (sameDay) return clock(instant, offset);
    return dayAndClock(instant, offset);
  }

  String date(LocalDate value) =>
      DateFormat.MMMEd(locale).format(_midnight(value));

  String weekday(LocalDate value) =>
      DateFormat.E(locale).format(_midnight(value));

  String nightOf(LocalDate wake) {
    final start = _midnight(wake.addDays(-1));
    final end = _midnight(wake);
    final monthDay = DateFormat.MMMd(locale);
    final dayOnly =
        start.month == end.month && (monthDay.pattern ?? '').startsWith('d');
    return l10n.sleepNightOf(
      dayOnly ? DateFormat.d(locale).format(start) : monthDay.format(start),
      monthDay.format(end),
    );
  }

  String decimal(double value, {int digits = 0}) {
    final format = NumberFormat.decimalPattern(locale)
      ..minimumFractionDigits = digits
      ..maximumFractionDigits = digits;
    return format.format(value);
  }

  String points(double value) {
    final format = NumberFormat.decimalPattern(locale)
      ..maximumFractionDigits = 1;
    return format.format(value);
  }

  String integer(num value) =>
      NumberFormat.decimalPattern(locale).format(value.round());

  String signed(double value, {int digits = 0}) {
    final text = decimal(value.abs(), digits: digits);
    if (text == decimal(0, digits: digits)) return text;
    return value.isNegative ? '$_minusSign$text' : '+$text';
  }

  String bpm(double value) => l10n.metricBpm(integer(value));

  String ms(double value) => l10n.metricMs(integer(value));

  String percent(double value) => l10n.metricPercent(integer(value));

  DateTime _wall(DateTime instant, Duration utcOffset) =>
      instant.toUtc().add(utcOffset);

  DateTime _midnight(LocalDate value) =>
      DateTime.utc(value.year, value.month, value.day);
}
