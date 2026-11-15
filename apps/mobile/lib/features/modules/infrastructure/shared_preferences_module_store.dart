import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesModuleStore implements ModuleStore {
  new([SharedPreferencesAsync? preferences]) : _preferences = preferences;

  static const key = 'modules_enabled';
  static const shortcutKey = 'modules_shortcut_dismissed';

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<Set<ModuleId>> read() async {
    final names = await _store.getStringList(key) ?? const [];
    final modules = ModuleId.values.asNameMap();
    return {for (final name in names) ?modules[name]};
  }

  @override
  Future<void> write(Set<ModuleId> enabled) =>
      _store.setStringList(key, [for (final id in enabled) id.name]);

  @override
  Future<bool> shortcutDismissed() async =>
      await _store.getBool(shortcutKey) ?? false;

  @override
  Future<void> dismissShortcut({required bool dismissed}) =>
      _store.setBool(shortcutKey, dismissed);
}
