import 'package:flutter/material.dart';

abstract interface class ThemeModeStore {
  ThemeMode? read();

  Future<void> write(ThemeMode mode);
}
