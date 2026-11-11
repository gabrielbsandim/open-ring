import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesUnitSystemStore implements UnitSystemStore {
  new([SharedPreferencesAsync? preferences]) : _preferences = preferences;

  static const key = 'unit_system';

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<UnitSystem?> read() async =>
      UnitSystem.values.asNameMap()[await _store.getString(key)];

  @override
  Future<void> write(UnitSystem units) => _store.setString(key, units.name);
}
