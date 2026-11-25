import 'dart:convert';

import 'package:metrics/metrics.dart' show LocalDate;
import 'package:open_ring/features/food/domain/food_energy_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesFoodEnergyStore implements FoodEnergyStore {
  new([SharedPreferencesAsync? preferences]) : _preferences = preferences;

  static const key = 'food_energy_opt_in';

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<FoodEnergyOptIn?> read() async => _decode(await _store.getString(key));

  @override
  Future<void> write(FoodEnergyOptIn optIn) => _store.setString(
    key,
    jsonEncode({'on': optIn.on.iso, 'soft_seen': optIn.softSeen}),
  );

  @override
  Future<void> clear() => _store.remove(key);

  static FoodEnergyOptIn? _decode(String? raw) {
    if (raw == null) return null;
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?>) return null;
    final on = LocalDate.tryParse(switch (json['on']) {
      final String iso => iso,
      _ => null,
    });
    final seen = json['soft_seen'];
    if (on == null || seen is! int || seen < 0) return null;
    return (on: on, softSeen: seen);
  }
}
