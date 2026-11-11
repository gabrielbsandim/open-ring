import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/features/ring/application/ring_alert_providers.dart';
import 'package:open_ring/features/ring/application/sync_alerts.dart';
import 'package:open_ring/features/ring/domain/ring_alerts.dart';
import 'package:open_ring/features/settings/application/notification_providers.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class NotificationsSection extends ConsumerStatefulWidget {
  const new({super.key});

  static const statusKey = Key('settings_notifications_status');
  static const openSettingsKey = Key('settings_notifications_open');

  static Key alertKey(RingAlert alert) => Key('settings_alert_${alert.name}');

  @override
  ConsumerState<NotificationsSection> createState() =>
      _NotificationsSectionState();
}

class _NotificationsSectionState extends ConsumerState<NotificationsSection> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(notificationsEnabledProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final enabled = ref.watch(notificationsEnabledProvider).value;
    final alerts = ref.watch(ringAlertSettingsProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(l10n.settingsNotifications),
        TileGroup(
          children: [
            if (enabled == false)
              SettingsTile(
                key: NotificationsSection.statusKey,
                leading: Icon(
                  Icons.notifications_off_rounded,
                  color: colors.textLabel,
                ),
                title: l10n.settingsNotificationsPermission,
                value: l10n.settingsNotificationsOff,
                valueColor: colors.stress,
              ),
            for (final alert in RingAlert.values)
              SettingsTile(
                title: alert.title(l10n),
                detail: alert.detail(l10n),
                trailing: Switch(
                  key: NotificationsSection.alertKey(alert),
                  value: enabled != false && (alerts?.contains(alert) ?? false),
                  onChanged: enabled == false || alerts == null
                      ? null
                      : (value) => _setAlert(alert, enabled: value),
                ),
              ),
            if (enabled == false)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: OutlinedButton(
                  key: NotificationsSection.openSettingsKey,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _openSettings,
                  child: Text(
                    l10n.settingsNotificationsOpenSettings,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  void _openSettings() =>
      unawaited(ref.read(notificationAccessProvider).openSettings());

  void _setAlert(RingAlert alert, {required bool enabled}) => unawaited(
    ref
        .read(ringAlertSettingsProvider.notifier)
        .setEnabled(alert, enabled: enabled),
  );
}

extension on RingAlert {
  String title(AppLocalizations l10n) => switch (this) {
    RingAlert.lowBattery => l10n.settingsAlertLowBattery,
    RingAlert.syncFailed => l10n.settingsAlertSyncFailed,
  };

  String detail(AppLocalizations l10n) => switch (this) {
    RingAlert.lowBattery => l10n.settingsAlertLowBatteryDetail(
      lowBatteryPercent,
    ),
    RingAlert.syncFailed => l10n.settingsAlertSyncFailedDetail(
      syncFailureAlertAttempts,
    ),
  };
}
