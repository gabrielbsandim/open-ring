import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/theme_mode_store.dart';

final themeModeStoreProvider = Provider<ThemeModeStore>(
  (ref) => throw UnimplementedError('Override themeModeStoreProvider.'),
);

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() =>
      ref.watch(themeModeStoreProvider).read() ?? ThemeMode.system;

  Future<void> select(ThemeMode mode) async {
    state = mode;
    await ref.read(themeModeStoreProvider).write(mode);
  }
}
