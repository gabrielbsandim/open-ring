import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/onboarding/infrastructure/shared_preferences_onboarding_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('a first launch has not finished onboarding', () async {
    final store = await SharedPreferencesOnboardingStore.open();

    expect(store.completed, isFalse);
  });

  test('a completed onboarding survives reopening', () async {
    final first = await SharedPreferencesOnboardingStore.open();
    await first.complete();

    final second = await SharedPreferencesOnboardingStore.open();

    expect(second.completed, isTrue);
  });

  test('a reset onboarding stays reset after reopening', () async {
    final first = await SharedPreferencesOnboardingStore.open();
    await first.complete();
    await first.reset();

    expect(first.completed, isFalse);
    final second = await SharedPreferencesOnboardingStore.open();
    expect(second.completed, isFalse);
  });
}
