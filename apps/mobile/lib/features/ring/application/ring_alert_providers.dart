import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/ring/domain/ring_alerts.dart';

final ringAlertPreferencesProvider = Provider<RingAlertPreferences>(
  (ref) => InMemoryRingAlertPreferences(),
);

final ringNotifierProvider = Provider<RingNotifier>(
  (ref) => InMemoryRingNotifier(),
);

final ringAlertSettingsProvider =
    AsyncNotifierProvider<RingAlertSettingsController, Set<RingAlert>>(
      RingAlertSettingsController.new,
    );

class RingAlertSettingsController extends AsyncNotifier<Set<RingAlert>> {
  @override
  Future<Set<RingAlert>> build() =>
      ref.watch(ringAlertPreferencesProvider).enabledAlerts();

  Future<void> setEnabled(RingAlert alert, {required bool enabled}) async {
    final current = await future;
    state = AsyncData(
      enabled ? {...current, alert} : current.difference({alert}),
    );
    await ref
        .read(ringAlertPreferencesProvider)
        .setEnabled(alert, enabled: enabled);
  }
}
