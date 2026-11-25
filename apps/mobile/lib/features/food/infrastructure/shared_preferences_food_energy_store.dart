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
    jsonEncode({
      'on': optIn.on.iso,
      'soft': switch (optIn.soft) {
        null => null,
        (:final id, :final on) => {'id': id, 'on': on.iso},
      },
    }),
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
    if (json is! Map<String, Object?> || !json.containsKey('soft')) return null;
    final on = _date(json['on']);
    if (on == null) return null;
    final soft = json['soft'];
    if (soft == null) return (on: on, soft: null);
    if (soft is! Map<String, Object?>) return null;
    final id = soft['id'];
    final softOn = _date(soft['on']);
    if (softOn == null || id is! int?) return null;
    return (on: on, soft: (id: id, on: softOn));
  }

  static LocalDate? _date(Object? iso) =>
      iso is String ? LocalDate.tryParse(iso) : null;
}
