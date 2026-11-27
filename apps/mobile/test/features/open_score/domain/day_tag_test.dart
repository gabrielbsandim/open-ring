import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';

const _today = LocalDate(2026, 11, 15);

void main() {
  test('the editable window is 7 days', () {
    expect(dayTagEditableDays, 7);
  });

  for (var age = 0; age <= 6; age++) {
    test('a date $age days old can be edited', () {
      expect(canEditDayTag(_today.addDays(-age), today: _today), isTrue);
    });
  }

  for (final age in [7, 8, 30]) {
    test('a date $age days old cannot be edited', () {
      expect(canEditDayTag(_today.addDays(-age), today: _today), isFalse);
    });
  }

  test('tomorrow and a date far ahead cannot be edited', () {
    expect(canEditDayTag(_today.addDays(1), today: _today), isFalse);
    expect(canEditDayTag(_today.addDays(40), today: _today), isFalse);
  });

  test('the window follows the month and year boundaries', () {
    const newYear = LocalDate(2027, 1, 3);

    expect(
      canEditDayTag(const LocalDate(2026, 12, 28), today: newYear),
      isTrue,
    );
    expect(
      canEditDayTag(const LocalDate(2026, 12, 27), today: newYear),
      isFalse,
    );
  });

  test('tryParse reads each tag name', () {
    expect(DayTag.tryParse('sick'), DayTag.sick);
    expect(DayTag.tryParse('travel'), DayTag.travel);
    expect(DayTag.tryParse('rest'), DayTag.rest);
  });

  test('tryParse is null for anything unknown', () {
    expect(DayTag.tryParse(null), isNull);
    expect(DayTag.tryParse(''), isNull);
    expect(DayTag.tryParse('Sick'), isNull);
    expect(DayTag.tryParse('holiday'), isNull);
  });
}
