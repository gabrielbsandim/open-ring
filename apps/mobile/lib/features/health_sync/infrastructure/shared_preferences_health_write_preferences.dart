import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_write_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesHealthWritePreferences
    implements HealthWritePreferences {
  new([SharedPreferencesAsync? preferences]) : _preferences = preferences;

  static const key = 'health_writes_disabled';

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<Set<HealthRecordKind>> disabled() async {
    final names = await _store.getStringList(key) ?? const [];
    final kinds = HealthRecordKind.values.asNameMap();
    return {for (final name in names) ?kinds[name]};
  }

  @override
  Future<void> setEnabled(
    HealthRecordKind kind, {
    required bool enabled,
  }) async {
    final current = await disabled();
    final next = enabled ? current.difference({kind}) : {...current, kind};
    await _store.setStringList(key, [for (final k in next) k.name]);
  }
}
