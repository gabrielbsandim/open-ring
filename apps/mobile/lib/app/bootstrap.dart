import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/theme/shared_preferences_theme_mode_store.dart';
import 'package:open_ring/app/theme/theme_mode_controller.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeModeStore = await SharedPreferencesThemeModeStore.open();
  runApp(
    ProviderScope(
      overrides: [themeModeStoreProvider.overrideWithValue(themeModeStore)],
      child: const OpenRingApp(),
    ),
  );
}
