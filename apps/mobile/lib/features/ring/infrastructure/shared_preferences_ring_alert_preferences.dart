import 'package:open_ring/features/ring/domain/ring_alerts.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesRingAlertPreferences
    implements RingAlertPreferences {
  new([SharedPreferencesAsync? preferences]) : _preferences = preferences;

  static const offKey = 'ring_alerts_off';
  static const warnedKey = 'ring_alert_low_battery_device';

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<Set<RingAlert>> enabledAlerts() async {
    final off = (await _store.getStringList(offKey))?.toSet() ?? const {};
    return RingAlert.values.where((a) => !off.contains(a.name)).toSet();
  }

  @override
  Future<void> setEnabled(RingAlert alert, {required bool enabled}) async {
    final on = await enabledAlerts();
    final next = enabled ? {...on, alert} : on.difference({alert});
    await _store.setStringList(offKey, [
      for (final a in RingAlert.values)
        if (!next.contains(a)) a.name,
    ]);
  }

  @override
  Future<String?> warnedDevice() => _store.getString(warnedKey);

  @override
  Future<void> setWarnedDevice(String? deviceId) async {
    if (deviceId == null) {
      await _store.remove(warnedKey);
      return;
    }
    await _store.setString(warnedKey, deviceId);
  }
}
