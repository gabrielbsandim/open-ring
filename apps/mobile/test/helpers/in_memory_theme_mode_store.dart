import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/theme_mode_store.dart';

class InMemoryThemeModeStore implements ThemeModeStore {
  new([this.saved]);

  ThemeMode? saved;
  int writes = 0;

  @override
  ThemeMode? read() => saved;

  @override
  Future<void> write(ThemeMode mode) async {
    saved = mode;
    writes++;
  }
}
