import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesModuleStore implements ModuleStore {
  new([SharedPreferencesAsync? preferences]) : _preferences = preferences;

  static const key = 'modules_enabled';

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
}
