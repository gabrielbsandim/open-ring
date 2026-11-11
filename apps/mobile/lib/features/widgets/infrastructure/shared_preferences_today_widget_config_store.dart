import 'dart:convert';

import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesTodayWidgetConfigStore
    implements TodayWidgetConfigStore {
  const new(this._preferences);

  static const key = 'today_widget_config';

  final SharedPreferencesWithCache _preferences;

  static Future<SharedPreferencesTodayWidgetConfigStore> open() async {
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(allowList: {key}),
    );
    return SharedPreferencesTodayWidgetConfigStore(preferences);
  }

  @override
  TodayWidgetConfig? read() {
    final raw = _preferences.getString(key);
    if (raw == null) return null;
    final decoded = _decode(raw);
    if (decoded is! Map<String, Object?>) return null;
    return TodayWidgetConfig.fromJson(decoded);
  }

  Object? _decode(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(TodayWidgetConfig config) =>
      _preferences.setString(key, jsonEncode(config.toJson()));

  @override
  Future<void> reset() => _preferences.remove(key);
}
