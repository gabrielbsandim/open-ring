import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

final class DriftUserProfileStore implements UserProfileStore {
  const new(this._db);

  final AppDatabase _db;

  @override
  Future<UserProfile?> read() async {
    final row = await _db.select(_db.userProfile).getSingleOrNull();
    if (row == null) return null;
    return UserProfile(
      birthYear: row.birthYear,
      sex: Sex.values.asNameMap()[row.sex],
      heightCentimeters: row.heightCentimeters,
      weightKilograms: row.weightKilograms,
      maxHeartRate: row.maxHeartRate,
      dailyStepGoal: row.dailyStepGoal,
    );
  }

  @override
  Future<void> save(UserProfile profile, {required DateTime at}) => _db
      .into(_db.userProfile)
      .insertOnConflictUpdate(
        UserProfileCompanion.insert(
          id: const Value(1),
          birthYear: Value(profile.birthYear),
          sex: Value(profile.sex?.name),
          heightCentimeters: Value(profile.heightCentimeters),
          weightKilograms: Value(profile.weightKilograms),
          maxHeartRate: Value(profile.maxHeartRate),
          dailyStepGoal: Value(profile.dailyStepGoal),
          updatedAtUtcMs: at.utcMs,
        ),
      );
}
