import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';

void main() {
  final now = DateTime.utc(2026, 11, 14, 12);

  WeighInDraft draft({
    DateTime? at,
    double kilograms = 78.2,
    double? bodyFatPercent,
    double? waistCentimeters,
  }) => WeighInDraft(
    at: at ?? now,
    offsetMinutes: -180,
    kilograms: kilograms,
    bodyFatPercent: bodyFatPercent,
    waistCentimeters: waistCentimeters,
  );

  test('a valid draft returns no issues', () {
    final issues = draft(
      bodyFatPercent: 18,
      waistCentimeters: 82,
    ).validate(now: now);

    expect(issues, isEmpty);
  });

  test('a draft with only kilograms is valid', () {
    expect(draft().validate(now: now), isEmpty);
  });

  test('kilograms accepts 20 and 300 and rejects just outside', () {
    expect(draft(kilograms: 20).validate(now: now), isEmpty);
    expect(draft(kilograms: 300).validate(now: now), isEmpty);
    expect(draft(kilograms: 19.99).validate(now: now), {
      WeighInIssue.kilograms,
    });
    expect(draft(kilograms: 300.01).validate(now: now), {
      WeighInIssue.kilograms,
    });
  });

  test('body fat accepts 3 and 70 and rejects just outside', () {
    expect(draft(bodyFatPercent: 3).validate(now: now), isEmpty);
    expect(draft(bodyFatPercent: 70).validate(now: now), isEmpty);
    expect(draft(bodyFatPercent: 2.99).validate(now: now), {
      WeighInIssue.bodyFat,
    });
    expect(draft(bodyFatPercent: 70.01).validate(now: now), {
      WeighInIssue.bodyFat,
    });
  });

  test('waist accepts 40 and 200 and rejects just outside', () {
    expect(draft(waistCentimeters: 40).validate(now: now), isEmpty);
    expect(draft(waistCentimeters: 200).validate(now: now), isEmpty);
    expect(draft(waistCentimeters: 39.99).validate(now: now), {
      WeighInIssue.waist,
    });
    expect(draft(waistCentimeters: 200.01).validate(now: now), {
      WeighInIssue.waist,
    });
  });

  test('a draft 61 seconds ahead is future and 59 seconds ahead is valid', () {
    final ahead61 = draft(at: now.add(const Duration(seconds: 61)));
    final ahead59 = draft(at: now.add(const Duration(seconds: 59)));

    expect(ahead61.validate(now: now), {WeighInIssue.future});
    expect(ahead59.validate(now: now), isEmpty);
  });

  test('a draft in the past is valid', () {
    final past = draft(at: now.subtract(const Duration(days: 400)));

    expect(past.validate(now: now), isEmpty);
  });

  test('a draft with several problems returns all of them', () {
    final issues = draft(
      at: now.add(const Duration(hours: 1)),
      kilograms: 5,
      bodyFatPercent: 99,
      waistCentimeters: 1,
    ).validate(now: now);

    expect(issues, WeighInIssue.values.toSet());
  });

  test('the draft source defaults to manual', () {
    expect(draft().source, WeighInSource.manual);
  });

  test('a weigh-in has value equality', () {
    WeighIn make() => WeighIn(
      id: 1,
      at: now,
      offsetMinutes: -180,
      kilograms: 78.2,
      source: WeighInSource.manual,
    );

    expect(make(), make());
    expect(make().hashCode, make().hashCode);
  });

  test('a value that is not a number is rejected, never stored', () {
    final now = DateTime.utc(2026, 11, 14, 12);
    final draft = WeighInDraft(
      at: now,
      offsetMinutes: 0,
      kilograms: double.nan,
      bodyFatPercent: double.nan,
      waistCentimeters: double.infinity,
    );

    expect(draft.validate(now: now), {
      WeighInIssue.kilograms,
      WeighInIssue.bodyFat,
      WeighInIssue.waist,
    });
  });
}
