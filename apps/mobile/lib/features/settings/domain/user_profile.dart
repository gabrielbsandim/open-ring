import 'package:meta/meta.dart';

enum Sex { female, male }

typedef ValueRange = ({num min, num max});

@immutable
final class UserProfile {
  const new({
    this.birthYear,
    this.sex,
    this.heightCentimeters,
    this.weightKilograms,
    this.maxHeartRate,
    this.dailyStepGoal,
  });

  static const ValueRange ageRange = (min: 10, max: 100);
  static const ValueRange heightRange = (min: 100, max: 230);
  static const ValueRange weightRange = (min: 30, max: 250);
  static const ValueRange maxHeartRateRange = (min: 100, max: 230);
  static const ValueRange stepGoalRange = (min: 1000, max: 40000);

  final int? birthYear;
  final Sex? sex;
  final double? heightCentimeters;
  final double? weightKilograms;
  final int? maxHeartRate;
  final int? dailyStepGoal;

  int? ageIn(int year) => switch (birthYear) {
    null => null,
    final born => year - born,
  };

  static int birthYearFor(int age, {required int year}) => year - age;

  static bool fits(num value, ValueRange range) =>
      value >= range.min && value <= range.max;

  @override
  bool operator ==(Object other) =>
      other is UserProfile &&
      other.birthYear == birthYear &&
      other.sex == sex &&
      other.heightCentimeters == heightCentimeters &&
      other.weightKilograms == weightKilograms &&
      other.maxHeartRate == maxHeartRate &&
      other.dailyStepGoal == dailyStepGoal;

  @override
  int get hashCode => Object.hash(
    birthYear,
    sex,
    heightCentimeters,
    weightKilograms,
    maxHeartRate,
    dailyStepGoal,
  );
}

abstract interface class UserProfileStore {
  Future<UserProfile?> read();

  Future<void> save(UserProfile profile, {required DateTime at});
}

final class InMemoryUserProfileStore implements UserProfileStore {
  new([this.profile]);

  UserProfile? profile;

  @override
  Future<UserProfile?> read() async => profile;

  @override
  Future<void> save(UserProfile profile, {required DateTime at}) async =>
      this.profile = profile;
}
