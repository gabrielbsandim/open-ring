import 'dart:convert';

import 'package:metrics/metrics.dart';

const goalCodecVersion = 1;

String encodeReviewInputs(ReviewInputs inputs) => jsonEncode({
  'v': goalCodecVersion,
  'kind': inputs.kind.name,
  'week': inputs.week,
  'levers': [
    for (final week in inputs.levers)
      {
        'kind': week.lever.kind.name,
        'target': week.lever.target,
        'achieved': week.achieved,
      },
  ],
  'adherencePrevious': _finite(inputs.adherencePrevious),
  'baseline': {
    'stepsMedian14': inputs.baseline.stepsMedian14,
    'bedMedian': inputs.baseline.bedMedian,
    'wakeMedian': inputs.baseline.wakeMedian,
    'effortMean4Weeks': _finite(inputs.baseline.effortMean4Weeks),
    'strengthDaysUsual': inputs.baseline.strengthDaysUsual,
  },
  'effortRaisesInRow': inputs.effortRaisesInRow,
  'rate': _rate(inputs.rate),
  'targetPercent': _finite(inputs.targetPercent),
  'capPercent': _finite(inputs.capPercent),
  'previousPercentLow': _finite(inputs.previousPercentLow),
  'bmi': _finite(inputs.bmi),
  'pregnantOrBreastfeeding': inputs.pregnantOrBreastfeeding,
  'screeningPositive': inputs.screeningPositive,
  'bodyOn': inputs.bodyOn,
  'readiness': inputs.readiness,
  'recoveryPrevious': inputs.recoveryPrevious,
  'energy': inputs.energy?.name,
  'energyPrevious': inputs.energyPrevious?.name,
  'foodOrWeight': inputs.foodOrWeight,
  'foodOrWeightPrevious': inputs.foodOrWeightPrevious,
  'maintenance': inputs.maintenance,
});

ReviewInputs? decodeReviewInputs(String json) => _decode(
  json,
  (map) => ReviewInputs(
    kind: _enum(GoalKind.values, _at(map, 'kind')),
    week: _int(map, 'week'),
    levers: [
      for (final entry in _list(map, 'levers'))
        LeverWeek(
          lever: _lever(_map(entry)),
          achieved: _int(_map(entry), 'achieved'),
        ),
    ],
    adherencePrevious: _doubleOrNull(map, 'adherencePrevious'),
    baseline: _baseline(_map(_at(map, 'baseline'))),
    effortRaisesInRow: _int(map, 'effortRaisesInRow'),
    rate: _lossRate(_at(map, 'rate')),
    targetPercent: _double(map, 'targetPercent'),
    capPercent: _double(map, 'capPercent'),
    previousPercentLow: _doubleOrNull(map, 'previousPercentLow'),
    bmi: _doubleOrNull(map, 'bmi'),
    pregnantOrBreastfeeding: _as<bool>(_at(map, 'pregnantOrBreastfeeding')),
    screeningPositive: _as<bool>(_at(map, 'screeningPositive')),
    bodyOn: _as<bool>(_at(map, 'bodyOn')),
    readiness: [for (final value in _list(map, 'readiness')) _as<int?>(value)],
    recoveryPrevious: _as<bool>(_at(map, 'recoveryPrevious')),
    energy: _enumOrNull(CheckInEnergy.values, _at(map, 'energy')),
    energyPrevious: _enumOrNull(
      CheckInEnergy.values,
      _at(map, 'energyPrevious'),
    ),
    foodOrWeight: _as<bool?>(_at(map, 'foodOrWeight')),
    foodOrWeightPrevious: _as<bool?>(_at(map, 'foodOrWeightPrevious')),
    // Rows written before maintenance existed have no key.
    maintenance: _as<bool?>(map['maintenance']) ?? false,
  ),
);

String encodeLevers(List<Lever> levers) => jsonEncode({
  'v': goalCodecVersion,
  'levers': [
    for (final lever in levers)
      {'kind': lever.kind.name, 'target': lever.target},
  ],
});

List<Lever>? decodeLevers(String json) => _decode(
  json,
  (map) => [for (final entry in _list(map, 'levers')) _lever(_map(entry))],
);

String encodeLeverChange(LeverChange change) => jsonEncode({
  'v': goalCodecVersion,
  'kind': change.kind.name,
  'from': change.from,
  'to': change.to,
});

LeverChange? decodeLeverChange(String json) => _decode(
  json,
  (map) => LeverChange(
    kind: _enum(LeverKind.values, _at(map, 'kind')),
    from: _as<int?>(_at(map, 'from')),
    to: _as<int?>(_at(map, 'to')),
  ),
);

// A raise of a lever the list does not hold adds it, so an accepted change
// always ends with its target in force.
List<Lever> applyLeverChange(List<Lever> levers, LeverChange change) {
  final to = change.to;
  if (to == null) {
    return [
      for (final lever in levers)
        if (lever.kind != change.kind) lever,
    ];
  }
  final next = Lever(kind: change.kind, target: to);
  if (!levers.any((lever) => lever.kind == change.kind)) {
    return [...levers, next];
  }
  return [
    for (final lever in levers)
      if (lever.kind == change.kind) next else lever,
  ];
}

double? _finite(double? value) {
  if (value == null || value.isFinite) return value;
  throw ArgumentError.value(value, 'value', 'A stored number must be finite');
}

Map<String, Object?>? _rate(LossRate? rate) {
  if (rate == null) return null;
  return {
    'kg': _finite(rate.kg),
    'kgLow': _finite(rate.kgLow),
    'kgHigh': _finite(rate.kgHigh),
    'percent': _finite(rate.percent),
    'percentLow': _finite(rate.percentLow),
    'percentHigh': _finite(rate.percentHigh),
  };
}

T? _decode<T>(String json, T Function(Map<String, Object?> map) read) {
  try {
    final map = _map(jsonDecode(json));
    if (map['v'] != goalCodecVersion) return null;
    return read(map);
  } on FormatException {
    return null;
  }
}

Lever _lever(Map<String, Object?> map) => Lever(
  kind: _enum(LeverKind.values, _at(map, 'kind')),
  target: _int(map, 'target'),
);

LeverBaseline _baseline(Map<String, Object?> map) => LeverBaseline(
  stepsMedian14: _as<int?>(_at(map, 'stepsMedian14')),
  bedMedian: _as<int?>(_at(map, 'bedMedian')),
  wakeMedian: _as<int?>(_at(map, 'wakeMedian')),
  effortMean4Weeks: _doubleOrNull(map, 'effortMean4Weeks'),
  strengthDaysUsual: _int(map, 'strengthDaysUsual'),
);

LossRate? _lossRate(Object? value) {
  if (value == null) return null;
  final map = _map(value);
  return LossRate(
    kg: _double(map, 'kg'),
    kgLow: _double(map, 'kgLow'),
    kgHigh: _double(map, 'kgHigh'),
    percent: _double(map, 'percent'),
    percentLow: _double(map, 'percentLow'),
    percentHigh: _double(map, 'percentHigh'),
  );
}

Object? _at(Map<String, Object?> map, String key) {
  if (map.containsKey(key)) return map[key];
  throw FormatException('Missing key $key');
}

T _as<T>(Object? value) {
  if (value is T) return value;
  throw FormatException('Unexpected value $value');
}

Map<String, Object?> _map(Object? value) => _as<Map<String, Object?>>(value);

List<Object?> _list(Map<String, Object?> map, String key) =>
    _as<List<Object?>>(_at(map, key));

int _int(Map<String, Object?> map, String key) => _as<int>(_at(map, key));

double _double(Map<String, Object?> map, String key) =>
    _as<num>(_at(map, key)).toDouble();

double? _doubleOrNull(Map<String, Object?> map, String key) =>
    _as<num?>(_at(map, key))?.toDouble();

T _enum<T extends Enum>(List<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('Unknown name $name');
}

T? _enumOrNull<T extends Enum>(List<T> values, Object? name) =>
    name == null ? null : _enum(values, name);
