import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/open_score/infrastructure/shared_preferences_week_goal_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('the key is open_score_week_goal', () {
    expect(SharedPreferencesWeekGoalStore.key, 'open_score_week_goal');
  });

  test('nothing is stored before the user picks a goal', () async {
    expect(await SharedPreferencesWeekGoalStore().read(), isNull);
  });

  test('a written goal survives a new store instance', () async {
    await SharedPreferencesWeekGoalStore().write(6);

    expect(await SharedPreferencesWeekGoalStore().read(), 6);
  });
}
