import 'dart:ui';

import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/ring/application/sync_paired_ring.dart';
import 'package:open_ring/features/ring/domain/ring_alerts.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';
import 'package:ring_driver/ring_driver.dart';

const lowBatteryPercent = 20;
const batteryRearmPercent = 30;
const syncFailureAlertAttempts = 3;

const _lowBatteryNotificationId = 1001;
const _syncFailedNotificationId = 1002;

// The worker has no widget tree, so the language comes from the platform
// locales here.
AppLocalizations ringAlertStrings([List<Locale>? locales]) =>
    lookupAppLocalizations(
      AppLocales.resolve(
        locales ?? PlatformDispatcher.instance.locales,
        AppLocales.supported,
      ),
    );

final class SyncAlerts {
  const new({
    required this.store,
    required this.preferences,
    required this.notifier,
    required this.strings,
  });

  final SyncStore store;
  final RingAlertPreferences preferences;
  final RingNotifier notifier;
  final AppLocalizations strings;

  Future<void> afterSync(SyncOutcome outcome) async {
    final ring = await store.pairedRing();
    if (ring == null) return;
    switch (outcome) {
      case SyncCompleted(:final report):
        await _battery(ring.deviceId, report.battery);
      case SyncFailed():
        await _failure(ring.deviceId);
      case NothingPaired() || AlreadySyncing():
        return;
    }
  }

  // One alert per episode: it starts at the threshold and only a reading back
  // at the re-arm level ends it, so a level hovering around 20% stays quiet.
  Future<void> _battery(String deviceId, BatteryStatus? battery) async {
    if (battery == null) return;
    final warned = await preferences.warnedDevice();
    if (battery.percent >= batteryRearmPercent) {
      await preferences.setWarnedDevice(null);
      return;
    }
    if (warned == deviceId ||
        battery.charging ||
        battery.percent > lowBatteryPercent) {
      return;
    }
    if (!await _allowed(RingAlert.lowBattery)) return;
    final format = MetricFormat(strings, strings.localeName);
    await notifier.show(
      RingNotification(
        id: _lowBatteryNotificationId,
        channelName: strings.ringAlertChannel,
        title: strings.ringAlertLowBatteryTitle,
        body: strings.ringAlertLowBatteryBody(
          format.percent(battery.percent.toDouble()),
        ),
      ),
    );
    await preferences.setWarnedDevice(deviceId);
  }

  // Only the run that makes the streak exactly the limit alerts, so every
  // later failure is silent until a successful sync starts a new streak.
  Future<void> _failure(String deviceId) async {
    final runs = await store.recentRuns(deviceId);
    final streak = runs.takeWhile((run) => run.failed).length;
    if (streak != syncFailureAlertAttempts) return;
    if (!await _allowed(RingAlert.syncFailed)) return;
    await notifier.show(
      RingNotification(
        id: _syncFailedNotificationId,
        channelName: strings.ringAlertChannel,
        title: strings.ringAlertSyncFailedTitle,
        body: strings.ringAlertSyncFailedBody(syncFailureAlertAttempts),
      ),
    );
  }

  Future<bool> _allowed(RingAlert alert) async =>
      (await preferences.enabledAlerts()).contains(alert) &&
      await notifier.enabled();
}
