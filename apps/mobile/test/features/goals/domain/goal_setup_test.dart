import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_setup.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

import '../goal_fixtures.dart';

GoalScreening _row(int day, {bool? softMode, bool? pregnant}) => GoalScreening(
  on: goalDay(12, day),
  softMode: softMode,
  pregnantOrBreastfeeding: pregnant,
);

void main() {
  group('4. asksPregnancy', () {
    test('is true when the sex is not given', () {
      expect(asksPregnancy(null, const []), isTrue);
    });

    test('is true for female with no rows and with a newest no', () {
      expect(asksPregnancy(Sex.female, const []), isTrue);
      expect(asksPregnancy(Sex.female, [_row(3, pregnant: false)]), isTrue);
    });

    test('is true for a male whose newest pregnancy answer is yes', () {
      expect(asksPregnancy(Sex.male, [_row(3, pregnant: true)]), isTrue);
    });

    test('is false for a male with no rows', () {
      expect(asksPregnancy(Sex.male, const []), isFalse);
    });

    test('is false for a male whose newest pregnancy answer is no', () {
      final rows = [_row(4, pregnant: false), _row(2, pregnant: true)];

      expect(asksPregnancy(Sex.male, rows), isFalse);
    });

    test('a soft mode only row above a yes does not hide the yes', () {
      final rows = [_row(4, softMode: false), _row(2, pregnant: true)];

      expect(asksPregnancy(Sex.male, rows), isTrue);
    });

    test('a male with only soft mode rows is not asked', () {
      expect(asksPregnancy(Sex.male, [_row(2, softMode: true)]), isFalse);
    });
  });

  group('6. referenceBounds', () {
    test('178 cm and a trend of 78.4 give 59.0 to 78.0', () {
      final bounds = referenceBounds(heightCm: 178, trendKg: 78.4);

      expect(bounds, isNotNull);
      expect(bounds!.minKg, 59.0);
      expect(bounds.maxKg, 78.0);
    });

    test('178 cm and a trend of 59.2 leave no room, so null', () {
      expect(referenceBounds(heightCm: 178, trendKg: 59.2), isNull);
    });
  });

  group('SetupOutcome', () {
    test('has the four outcomes in order', () {
      expect(SetupOutcome.values, [
        SetupOutcome.started,
        SetupOutcome.pregnancy,
        SetupOutcome.alreadyActive,
        SetupOutcome.notAllowed,
      ]);
    });
  });
}
