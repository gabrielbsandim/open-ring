import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

UnitFormat unitsIn(UnitSystem system, {String locale = 'en'}) => UnitFormat(
  MetricFormat(lookupAppLocalizations(Locale(locale)), locale),
  system,
);

void main() {
  final metric = unitsIn(UnitSystem.metric);
  final imperial = unitsIn(UnitSystem.imperial);

  test('distance is kilometres in metric and miles in imperial', () {
    expect(metric.distance(5210.4), '5.21');
    expect(metric.distanceUnit, 'km');
    expect(metric.distanceText(5210.4), '5.21 km');
    expect(imperial.distance(5210.4), '3.24');
    expect(imperial.distanceUnit, 'mi');
    expect(imperial.distanceText(5210.4), '3.24 mi');
    expect(imperial.distance(null), '--');
  });

  test('the split length follows the distance unit', () {
    expect(metric.distanceUnitMeters, 1000);
    expect(imperial.distanceUnitMeters, ImperialUnits.metersPerMile);
    expect(imperial.distanceIn(ImperialUnits.metersPerMile * 2), 2);
  });

  test('pace is per km or per mile', () {
    const fiveMinutes = Duration(minutes: 5);

    expect(metric.pace(fiveMinutes), '5:00');
    expect(metric.paceUnit, 'min/km');
    expect(imperial.pace(fiveMinutes), '8:03');
    expect(imperial.paceUnit, 'min/mi');
    expect(imperial.pace(null), '--');
  });

  test('speed is km/h or mph', () {
    const twoMinutes = Duration(minutes: 2);

    expect(metric.speed(twoMinutes), '30.0');
    expect(metric.speedUnit, 'km/h');
    expect(imperial.speed(twoMinutes), '18.6');
    expect(imperial.speedUnit, 'mph');
    expect(imperial.speed(Duration.zero), '--');
  });

  test('short lengths like climb are metres or feet', () {
    expect(metric.length(30), '30');
    expect(metric.lengthUnit, 'm');
    expect(imperial.length(30), '98');
    expect(imperial.lengthUnit, 'ft');
  });

  test('height and weight follow the unit system', () {
    expect(metric.height(180), '180 cm');
    expect(imperial.height(180), '5 ft 11 in');
    expect(metric.weight(70), '70 kg');
    expect(metric.weight(70.5), '70.5 kg');
    expect(imperial.weight(70), '154 lb');
  });

  test('numbers use the locale separators', () {
    final german = unitsIn(UnitSystem.imperial, locale: 'de');

    expect(german.distanceText(5210.4), '3,24 mi');
    expect(german.speed(const Duration(minutes: 2)), '18,6');
  });

  test('select picks the value for the unit system', () {
    expect(metric.select('a', 'b'), 'a');
    expect(imperial.select('a', 'b'), 'b');
  });
}
