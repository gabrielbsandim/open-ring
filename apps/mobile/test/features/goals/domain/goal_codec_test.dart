import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/domain/goal_codec.dart';

import '../goal_fixtures.dart';

const _inputKeys = {
  'v',
  'kind',
  'week',
  'levers',
  'adherencePrevious',
  'baseline',
  'effortRaisesInRow',
  'rate',
  'targetPercent',
  'capPercent',
  'previousPercentLow',
  'bmi',
  'pregnantOrBreastfeeding',
  'screeningPositive',
  'bodyOn',
  'readiness',
  'recoveryPrevious',
  'energy',
  'energyPrevious',
  'foodOrWeight',
  'foodOrWeightPrevious',
};

Map<String, Object?> _f1Map() =>
    jsonDecode(encodeReviewInputs(f1)) as Map<String, Object?>;

ReviewInputs? _decodeMap(Map<String, Object?> map) =>
    decodeReviewInputs(jsonEncode(map));

void main() {
  test('the codec version is 1', () {
    expect(goalCodecVersion, 1);
  });

  group('criterion 1: inputs round trip', () {
    final fixtures = {'F1': f1, 'F0': f0};

    for (final MapEntry(key: name, value: source) in fixtures.entries) {
      test('$name encodes to the same string after a decode', () {
        final encoded = encodeReviewInputs(source);

        final decoded = decodeReviewInputs(encoded);

        expect(decoded, isNotNull);
        expect(encodeReviewInputs(decoded!), encoded);
      });

      test('$name decodes to every field of the source', () {
        final decoded = decodeReviewInputs(encodeReviewInputs(source));

        expect(decoded, isNotNull);
        expectSameInputs(decoded!, source);
      });
    }
  });

  group('criterion 2: the decoded F1 is reviewed as the source', () {
    test('the rule is build and the action is nextStep', () {
      final decoded = decodeReviewInputs(encodeReviewInputs(f1))!;

      final review = reviewWeek(decoded);

      expect(review.rule, ReviewRule.build);
      expect(review.action, ReviewAction.nextStep);
    });

    test('the change raises steps from 9000 to 10000', () {
      final decoded = decodeReviewInputs(encodeReviewInputs(f1))!;

      final change = reviewWeek(decoded).change;

      expect(change, isNotNull);
      expect(change!.kind, LeverKind.steps);
      expect(change.from, 9000);
      expect(change.to, 10000);
    });
  });

  group('criterion 3: the F0 JSON', () {
    test('holds the 20 field keys and the version, nothing else', () {
      final map = jsonDecode(encodeReviewInputs(f0)) as Map<String, Object?>;

      expect(map.keys.toSet(), _inputKeys);
      expect(map['v'], 1);
    });

    test('writes a null for each unset field instead of omitting it', () {
      final map = jsonDecode(encodeReviewInputs(f0)) as Map<String, Object?>;

      for (final key in [
        'adherencePrevious',
        'rate',
        'previousPercentLow',
        'bmi',
        'energy',
        'energyPrevious',
        'foodOrWeight',
        'foodOrWeightPrevious',
      ]) {
        expect(map.containsKey(key), isTrue, reason: key);
        expect(map[key], isNull, reason: key);
      }
      expect(map['readiness'], List<Object?>.filled(7, null));
    });

    test('writes enums by name and keeps the Dart field names', () {
      final map = _f1Map();

      expect(map['kind'], 'loseFat');
      expect(map['energy'], 'good');
      expect(map['energyPrevious'], 'normal');
      expect((map['levers']! as List).first, {
        'kind': 'strengthDays',
        'target': 2,
        'achieved': 2,
      });
      expect((map['baseline']! as Map).keys.toSet(), {
        'stepsMedian14',
        'bedMedian',
        'wakeMedian',
        'effortMean4Weeks',
        'strengthDaysUsual',
      });
      expect((map['rate']! as Map).keys.toSet(), {
        'kg',
        'kgLow',
        'kgHigh',
        'percent',
        'percentLow',
        'percentHigh',
      });
    });
  });

  group('criterion 4: decodeReviewInputs returns null', () {
    test('for JSON that does not parse', () {
      expect(decodeReviewInputs('{'), isNull);
    });

    test('for a version other than 1', () {
      expect(decodeReviewInputs(jsonEncode(_f1Map()..['v'] = 2)), isNull);
    });

    test('for F1 without bodyOn', () {
      expect(_decodeMap(_f1Map()..remove('bodyOn')), isNull);
    });

    test('for an unknown kind', () {
      expect(_decodeMap(_f1Map()..['kind'] = 'x'), isNull);
    });

    test('for an unknown energy name', () {
      expect(_decodeMap(_f1Map()..['energy'] = 'x'), isNull);
    });

    test('for a wrong type', () {
      expect(_decodeMap(_f1Map()..['week'] = 'three'), isNull);
    });

    test('for a key missing from a nested object', () {
      final map = _f1Map();
      (map['baseline']! as Map).remove('bedMedian');

      expect(_decodeMap(map), isNull);
    });

    test('for a lever of an unknown kind', () {
      final map = _f1Map();
      ((map['levers']! as List).first as Map)['kind'] = 'x';

      expect(_decodeMap(map), isNull);
    });

    test('for JSON that is not an object', () {
      expect(decodeReviewInputs('[]'), isNull);
    });

    test('for an empty string', () {
      expect(decodeReviewInputs(''), isNull);
    });
  });

  group('doubles in the JSON', () {
    test('an integer written for a double decodes as that double', () {
      final decoded = _decodeMap(_f1Map()..['bmi'] = 25);

      expect(decoded, isNotNull);
      expect(decoded!.bmi, 25.0);
    });

    test('an integer in a rate field decodes as a double', () {
      final map = _f1Map();
      (map['rate']! as Map)['kg'] = 1;

      final decoded = _decodeMap(map);

      expect(decoded, isNotNull);
      expect(decoded!.rate!.kg, 1.0);
    });
  });

  group('criterion 5: a non-finite double is refused', () {
    ReviewInputs withBmi(double? bmi) => ReviewInputs(
      kind: f1.kind,
      week: f1.week,
      levers: f1.levers,
      adherencePrevious: f1.adherencePrevious,
      baseline: f1.baseline,
      effortRaisesInRow: f1.effortRaisesInRow,
      rate: f1.rate,
      targetPercent: f1.targetPercent,
      capPercent: f1.capPercent,
      previousPercentLow: f1.previousPercentLow,
      bmi: bmi,
      pregnantOrBreastfeeding: f1.pregnantOrBreastfeeding,
      screeningPositive: f1.screeningPositive,
      bodyOn: f1.bodyOn,
      readiness: f1.readiness,
      recoveryPrevious: f1.recoveryPrevious,
      energy: f1.energy,
      energyPrevious: f1.energyPrevious,
      foodOrWeight: f1.foodOrWeight,
      foodOrWeightPrevious: f1.foodOrWeightPrevious,
    );

    test('bmi of infinity throws ArgumentError', () {
      expect(
        () => encodeReviewInputs(withBmi(double.infinity)),
        throwsArgumentError,
      );
    });

    test('bmi of NaN throws ArgumentError', () {
      expect(
        () => encodeReviewInputs(withBmi(double.nan)),
        throwsArgumentError,
      );
    });

    test('an infinite rate percent throws ArgumentError', () {
      final inputs = ReviewInputs(
        kind: f1.kind,
        week: f1.week,
        levers: f1.levers,
        adherencePrevious: f1.adherencePrevious,
        baseline: f1.baseline,
        effortRaisesInRow: f1.effortRaisesInRow,
        rate: const LossRate(
          kg: 0.2,
          kgLow: 0.1,
          kgHigh: 0.3,
          percent: double.infinity,
          percentLow: double.infinity,
          percentHigh: double.infinity,
        ),
        targetPercent: f1.targetPercent,
        capPercent: f1.capPercent,
        previousPercentLow: f1.previousPercentLow,
        bmi: f1.bmi,
        pregnantOrBreastfeeding: f1.pregnantOrBreastfeeding,
        screeningPositive: f1.screeningPositive,
        bodyOn: f1.bodyOn,
        readiness: f1.readiness,
        recoveryPrevious: f1.recoveryPrevious,
        energy: f1.energy,
        energyPrevious: f1.energyPrevious,
        foodOrWeight: f1.foodOrWeight,
        foodOrWeightPrevious: f1.foodOrWeightPrevious,
      );

      expect(() => encodeReviewInputs(inputs), throwsArgumentError);
    });

    test('a finite bmi is written as that number', () {
      final map = jsonDecode(
        encodeReviewInputs(withBmi(24.55)),
      ) as Map<String, Object?>;

      expect(map['bmi'], 24.55);
    });
  });

  group('criterion 6: levers and change round trip', () {
    test('a lever list keeps kinds, targets and order', () {
      const levers = [strengthLever, sleepLever, stepsLever];

      final decoded = decodeLevers(encodeLevers(levers));

      expect(decoded, isNotNull);
      expectSameLevers(decoded!, levers);
    });

    test('an empty lever list round trips to an empty list', () {
      final decoded = decodeLevers(encodeLevers(const <Lever>[]));

      expect(decoded, isEmpty);
    });

    test('the lever JSON has the version and kind and target only', () {
      final map = jsonDecode(
        encodeLevers(const [strengthLever]),
      ) as Map<String, Object?>;

      expect(map, {
        'v': 1,
        'levers': [
          {'kind': 'strengthDays', 'target': 2},
        ],
      });
    });

    test('a lever list with an unknown kind decodes to null', () {
      const json = '{"v":1,"levers":[{"kind":"x","target":2}]}';

      expect(decodeLevers(json), isNull);
    });

    test('a lever list with version 2 decodes to null', () {
      expect(decodeLevers('{"v":2,"levers":[]}'), isNull);
    });

    test('a lever list that does not parse decodes to null', () {
      expect(decodeLevers('{'), isNull);
    });

    test('a raise keeps from and to', () {
      const change = LeverChange(kind: LeverKind.steps, from: 9000, to: 10000);

      final decoded = decodeLeverChange(encodeLeverChange(change));

      expectSameChange(decoded, change);
    });

    test('an added lever keeps a null from', () {
      const change = LeverChange(kind: LeverKind.steps, from: null, to: 9000);

      final decoded = decodeLeverChange(encodeLeverChange(change));

      expect(decoded, isNotNull);
      expectSameChange(decoded, change);
    });

    test('a removed lever keeps a null to', () {
      const change = LeverChange(kind: LeverKind.steps, from: 9000, to: null);

      final decoded = decodeLeverChange(encodeLeverChange(change));

      expect(decoded, isNotNull);
      expectSameChange(decoded, change);
    });

    test('the change JSON writes the null explicitly', () {
      const change = LeverChange(kind: LeverKind.steps, from: null, to: 9000);

      final map = jsonDecode(encodeLeverChange(change)) as Map<String, Object?>;

      expect(map, {'v': 1, 'kind': 'steps', 'from': null, 'to': 9000});
    });

    test('a change with a missing key decodes to null', () {
      expect(decodeLeverChange('{"v":1,"kind":"steps","from":1}'), isNull);
    });

    test('a change with an unknown kind decodes to null', () {
      const json = '{"v":1,"kind":"x","from":1,"to":2}';

      expect(decodeLeverChange(json), isNull);
    });

    test('a change with version 2 decodes to null', () {
      const json = '{"v":2,"kind":"steps","from":1,"to":2}';

      expect(decodeLeverChange(json), isNull);
    });

    test('a change that does not parse decodes to null', () {
      expect(decodeLeverChange('nope'), isNull);
    });
  });

  group('criterion 7: applyLeverChange', () {
    const levers = [strengthLever, stepsLever];

    test('an add appends the lever at the end', () {
      const change = LeverChange(
        kind: LeverKind.sleepWindow,
        from: null,
        to: 690,
      );

      final result = applyLeverChange(levers, change);

      expectSameLevers(result, [strengthLever, stepsLever, sleepLever]);
    });

    test('a raise replaces the target in place', () {
      const change = LeverChange(kind: LeverKind.steps, from: 9000, to: 10000);

      final result = applyLeverChange(levers, change);

      expectSameLevers(result, const [
        strengthLever,
        Lever(kind: LeverKind.steps, target: 10000),
      ]);
    });

    test('a raise on the first lever keeps its position', () {
      const change = LeverChange(kind: LeverKind.strengthDays, from: 2, to: 3);

      final result = applyLeverChange(levers, change);

      expectSameLevers(result, const [
        Lever(kind: LeverKind.strengthDays, target: 3),
        stepsLever,
      ]);
    });

    test('a remove drops that kind', () {
      const change = LeverChange(kind: LeverKind.steps, from: 9000, to: null);

      final result = applyLeverChange(levers, change);

      expectSameLevers(result, const [strengthLever]);
    });

    test('an add to an empty list gives that one lever', () {
      const change = LeverChange(kind: LeverKind.steps, from: null, to: 9000);

      final result = applyLeverChange(const <Lever>[], change);

      expectSameLevers(result, const [stepsLever]);
    });

    test('the input list is not modified', () {
      const change = LeverChange(kind: LeverKind.steps, from: 9000, to: null);
      final input = [strengthLever, stepsLever];

      applyLeverChange(input, change);

      expectSameLevers(input, const [strengthLever, stepsLever]);
    });
  });
}
