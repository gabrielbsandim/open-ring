import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesHideNumbersStore implements HideNumbersStore {
  new([SharedPreferencesAsync? preferences]) : _preferences = preferences;

  static const key = 'body_hide_numbers';

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<bool> read() async => await _store.getBool(key) ?? false;

  @override
  Future<void> write({required bool hidden}) => _store.setBool(key, hidden);
}
