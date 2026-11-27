import 'package:meta/meta.dart';

enum WeighInSource { manual, demo }

enum WeighInIssue { kilograms, bodyFat, waist, future }

typedef WeighInRange = ({double min, double max});

const WeighInRange weighInKilogramsRange = (min: 20, max: 300);
const WeighInRange weighInBodyFatRange = (min: 3, max: 70);
const WeighInRange weighInWaistRange = (min: 40, max: 200);
const _clockTolerance = Duration(minutes: 1);

bool _outside(double? value, WeighInRange range) =>
    value != null && !(value >= range.min && value <= range.max);

// Hundredths of a kilogram keep a value typed in pounds intact at one decimal.
double roundKilograms(double kilograms) => (kilograms * 100).round() / 100;

@immutable
final class WeighIn {
  const new({
    required this.id,
    required this.at,
    required this.offsetMinutes,
    required this.kilograms,
    required this.source,
    this.bodyFatPercent,
    this.waistCentimeters,
  });

  final int id;
  final DateTime at;
  final int offsetMinutes;
  final double kilograms;
  final double? bodyFatPercent;
  final double? waistCentimeters;
  final WeighInSource source;

  @override
  bool operator ==(Object other) =>
      other is WeighIn &&
      other.id == id &&
      other.at == at &&
      other.offsetMinutes == offsetMinutes &&
      other.kilograms == kilograms &&
      other.bodyFatPercent == bodyFatPercent &&
      other.waistCentimeters == waistCentimeters &&
      other.source == source;

  @override
  int get hashCode => Object.hash(
    id,
    at,
    offsetMinutes,
    kilograms,
    bodyFatPercent,
    waistCentimeters,
    source,
  );
}

final class WeighInDraft {
  const new({
    required this.at,
    required this.offsetMinutes,
    required this.kilograms,
    this.bodyFatPercent,
    this.waistCentimeters,
    this.source = WeighInSource.manual,
  });

  final DateTime at;
  final int offsetMinutes;
  final double kilograms;
  final double? bodyFatPercent;
  final double? waistCentimeters;
  final WeighInSource source;

  Set<WeighInIssue> validate({required DateTime now}) => {
    if (_outside(kilograms, weighInKilogramsRange)) WeighInIssue.kilograms,
    if (_outside(bodyFatPercent, weighInBodyFatRange)) WeighInIssue.bodyFat,
    if (_outside(waistCentimeters, weighInWaistRange)) WeighInIssue.waist,
    if (at.isAfter(now.add(_clockTolerance))) WeighInIssue.future,
  };
}
