import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/domain/ring_alerts.dart';
import 'package:open_ring/features/ring/infrastructure/shared_preferences_ring_alert_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('both alerts are on by default', () async {
    expect(await SharedPreferencesRingAlertPreferences().enabledAlerts(), {
      ...RingAlert.values,
    });
  });

  test('a toggle survives a new instance, as the worker reads it', () async {
    await SharedPreferencesRingAlertPreferences().setEnabled(
      RingAlert.lowBattery,
      enabled: false,
    );

    expect(await SharedPreferencesRingAlertPreferences().enabledAlerts(), {
      RingAlert.syncFailed,
    });

    await SharedPreferencesRingAlertPreferences().setEnabled(
      RingAlert.lowBattery,
      enabled: true,
    );

    expect(await SharedPreferencesRingAlertPreferences().enabledAlerts(), {
      ...RingAlert.values,
    });
  });

  test('the warned ring is stored and cleared', () async {
    final preferences = SharedPreferencesRingAlertPreferences();
    expect(await preferences.warnedDevice(), isNull);

    await preferences.setWarnedDevice('ring-1');
    expect(
      await SharedPreferencesRingAlertPreferences().warnedDevice(),
      'ring-1',
    );

    await preferences.setWarnedDevice(null);
    expect(await preferences.warnedDevice(), isNull);
  });
}
