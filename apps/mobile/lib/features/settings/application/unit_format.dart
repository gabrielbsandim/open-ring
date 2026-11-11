import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

const metersPerKilometre = 1000.0;

final class UnitFormat {
  const new(this.format, this.system);

  factory of(BuildContext context, WidgetRef ref) => UnitFormat(
    MetricFormat.of(context),
    ref.watch(currentUnitSystemProvider),
  );

  final MetricFormat format;
  final UnitSystem system;

  AppLocalizations get l10n => format.l10n;

  bool get imperial => system == UnitSystem.imperial;

  T select<T>(T metric, T imperial) => switch (system) {
    UnitSystem.metric => metric,
    UnitSystem.imperial => imperial,
  };

  double get distanceUnitMeters =>
      select(metersPerKilometre, ImperialUnits.metersPerMile);

  double distanceIn(double meters) => meters / distanceUnitMeters;

  String distance(double? meters) {
    if (meters == null) return l10n.workoutNoValue;
    return format.decimal(distanceIn(meters), digits: 2);
  }

  String get distanceUnit => select(l10n.workoutUnitKm, l10n.workoutUnitMi);

  String distanceText(double meters) =>
      select(l10n.activityKm, l10n.activityMi)(distance(meters));

  String pace(Duration? perKilometre) {
    if (perKilometre == null) return l10n.workoutNoValue;
    final seconds = (_perUnit(perKilometre).inMilliseconds / 1000).round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  String get paceUnit => select(l10n.workoutUnitPace, l10n.workoutUnitPaceMi);

  String speed(Duration? perKilometre) {
    if (perKilometre == null || perKilometre <= Duration.zero) {
      return l10n.workoutNoValue;
    }
    final hours =
        _perUnit(perKilometre).inMicroseconds / Duration.microsecondsPerHour;
    return format.decimal(1 / hours, digits: 1);
  }

  String get speedUnit =>
      select(l10n.workoutUnitSpeed, l10n.workoutUnitSpeedMph);

  String length(double meters) =>
      format.integer(select(meters, ImperialUnits.feet(meters)));

  String get lengthUnit => select(l10n.workoutUnitMeters, l10n.workoutUnitFeet);

  String height(double centimeters) {
    if (!imperial) {
      return '${format.integer(centimeters)} ${l10n.profileUnitCm}';
    }
    final inches = ImperialUnits.inches(centimeters).round();
    return l10n.settingsFeetInches(
      inches ~/ ImperialUnits.inchesPerFoot,
      inches % ImperialUnits.inchesPerFoot,
    );
  }

  String weight(double kilograms) {
    if (imperial) {
      return l10n.settingsPounds(
        format.integer(ImperialUnits.pounds(kilograms)),
      );
    }
    final digits = kilograms == kilograms.roundToDouble() ? 0 : 1;
    return '${format.decimal(kilograms, digits: digits)} ${l10n.profileUnitKg}';
  }

  Duration _perUnit(Duration perKilometre) =>
      perKilometre * (distanceUnitMeters / metersPerKilometre);
}
