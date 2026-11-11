import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/settings/infrastructure/drift_user_profile_store.dart';

import '../../../helpers/database.dart';

void main() {
  final at = DateTime.utc(2026, 11, 10, 9);

  test('an empty database has no profile', () async {
    expect(await DriftUserProfileStore(memoryDatabase()).read(), isNull);
  });

  test('a saved profile reads back and a second save replaces it', () async {
    final store = DriftUserProfileStore(memoryDatabase());
    const first = UserProfile(
      birthYear: 1992,
      sex: Sex.female,
      heightCentimeters: 168,
      weightKilograms: 61.5,
      dailyStepGoal: 9000,
    );
    await store.save(first, at: at);
    expect(await store.read(), first);

    const second = UserProfile(birthYear: 1992, maxHeartRate: 191);
    await store.save(second, at: at.add(const Duration(minutes: 1)));

    expect(await store.read(), second);
  });
}
