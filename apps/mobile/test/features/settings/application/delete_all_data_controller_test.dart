import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/theme/theme_mode_controller.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/domain/sync_interval.dart';
import 'package:open_ring/features/settings/application/delete_all_data_controller.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/widgets/application/widget_providers.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';

import '../../../helpers/fake_sync_scheduler.dart';
import '../../../helpers/in_memory_sync_interval_store.dart';
import '../../../helpers/in_memory_theme_mode_store.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/settings_fakes.dart';

void main() {
  late FakeLocalDataEraser eraser;
  late InMemoryUnitSystemStore units;
  late InMemoryUserProfileStore profiles;
  late InMemoryOnboardingStore onboarding;
  late InMemoryTodayWidgetConfigStore widgetConfig;

  ProviderContainer container([FakeLocalDataEraser? override]) {
    eraser = override ?? FakeLocalDataEraser();
    units = InMemoryUnitSystemStore(UnitSystem.imperial);
    profiles = InMemoryUserProfileStore(fullProfile);
    onboarding = InMemoryOnboardingStore(completed: true);
    widgetConfig = InMemoryTodayWidgetConfigStore(
      TodayWidgetConfig().withTheme(WidgetTheme.light),
    );
    final container = ProviderContainer(
      overrides: [
        localDataEraserProvider.overrideWithValue(eraser),
        themeModeStoreProvider.overrideWithValue(
          InMemoryThemeModeStore(ThemeMode.dark),
        ),
        syncIntervalStoreProvider.overrideWithValue(
          InMemorySyncIntervalStore(SyncInterval.minutes15),
        ),
        syncSchedulerProvider.overrideWithValue(FakeSyncScheduler()),
        unitSystemStoreProvider.overrideWithValue(units),
        userProfileStoreProvider.overrideWithValue(profiles),
        onboardingStoreProvider.overrideWithValue(onboarding),
        todayWidgetConfigStoreProvider.overrideWithValue(widgetConfig),
      ],
    );
    addTearDown(container.dispose);
    container.listen(deleteAllDataProvider, (_, _) {});
    return container;
  }

  test('erases, then resets what the app holds in memory', () async {
    final c = container();
    expect(await c.read(unitSystemProvider.future), UnitSystem.imperial);
    expect(await c.read(userProfileProvider.future), isNotNull);
    final revision = c.read(dataRevisionProvider);
    units.units = null;
    profiles.profile = null;

    expect(await c.read(deleteAllDataProvider.notifier).delete(), isTrue);

    expect(eraser.erased, 1);
    expect(c.read(deleteAllDataProvider), DeletionStatus.idle);
    expect(c.read(themeModeProvider), ThemeMode.system);
    expect(c.read(syncIntervalProvider), SyncInterval.fallback);
    expect(await c.read(unitSystemProvider.future), UnitSystem.metric);
    expect(await c.read(userProfileProvider.future), isNull);
    expect(c.read(dataRevisionProvider), revision + 1);
    expect(c.read(onboardingProvider), isFalse);
    expect(onboarding.completed, isFalse);
    expect(c.read(todayWidgetConfigProvider), TodayWidgetConfig());
    expect(widgetConfig.saved, isNull);
  });

  test('a failed erase reports failure and keeps the settings', () async {
    final c = container(FakeLocalDataEraser(fail: true));

    expect(await c.read(deleteAllDataProvider.notifier).delete(), isFalse);

    expect(c.read(deleteAllDataProvider), DeletionStatus.failed);
    expect(c.read(themeModeProvider), ThemeMode.dark);
    expect(c.read(onboardingProvider), isTrue);
    expect(c.read(todayWidgetConfigProvider).theme, WidgetTheme.light);
  });

  test('a second tap while deleting does nothing', () async {
    final hold = Completer<void>();
    final c = container(FakeLocalDataEraser(hold: hold));
    final notifier = c.read(deleteAllDataProvider.notifier);

    final first = notifier.delete();
    expect(c.read(deleteAllDataProvider), DeletionStatus.deleting);
    expect(await notifier.delete(), isFalse);
    hold.complete();

    expect(await first, isTrue);
    expect(eraser.erased, 1);
  });
}
