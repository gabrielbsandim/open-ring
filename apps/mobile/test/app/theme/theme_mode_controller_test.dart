import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/theme/theme_mode_controller.dart';

import '../../helpers/in_memory_theme_mode_store.dart';

ProviderContainer containerWith(InMemoryThemeModeStore store) =>
    ProviderContainer.test(
      overrides: [themeModeStoreProvider.overrideWithValue(store)],
    );

void main() {
  test('defaults to the system mode when nothing is saved', () {
    final container = containerWith(InMemoryThemeModeStore());

    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('restores the saved mode', () {
    final container = containerWith(InMemoryThemeModeStore(ThemeMode.dark));

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('select updates the state and persists it', () async {
    final store = InMemoryThemeModeStore();
    final container = containerWith(store);

    await container.read(themeModeProvider.notifier).select(ThemeMode.light);

    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(store.saved, ThemeMode.light);
    expect(store.writes, 1);
  });

  test('a new session restores what the last one selected', () async {
    final store = InMemoryThemeModeStore();
    await containerWith(store)
        .read(themeModeProvider.notifier)
        .select(ThemeMode.dark);

    expect(containerWith(store).read(themeModeProvider), ThemeMode.dark);
  });
}
