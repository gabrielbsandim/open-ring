import 'package:meta/meta.dart';

enum RingAlert { lowBattery, syncFailed }

@immutable
final class RingNotification {
  const new({
    required this.id,
    required this.channelName,
    required this.title,
    required this.body,
  });

  final int id;
  final String channelName;
  final String title;
  final String body;
}

abstract interface class RingNotifier {
  Future<bool> enabled();

  Future<void> show(RingNotification notification);
}

final class InMemoryRingNotifier implements RingNotifier {
  new({this.allowed = true});

  bool allowed;
  final shown = <RingNotification>[];

  @override
  Future<bool> enabled() async => allowed;

  @override
  Future<void> show(RingNotification notification) async =>
      shown.add(notification);
}

abstract interface class RingAlertPreferences {
  Future<Set<RingAlert>> enabledAlerts();

  Future<void> setEnabled(RingAlert alert, {required bool enabled});

  // The ring already warned about in the current low battery episode, if any.
  Future<String?> warnedDevice();

  Future<void> setWarnedDevice(String? deviceId);
}

final class InMemoryRingAlertPreferences implements RingAlertPreferences {
  new({Set<RingAlert>? enabled, this.warned})
    : alerts = enabled ?? {...RingAlert.values};

  final Set<RingAlert> alerts;
  String? warned;

  @override
  Future<Set<RingAlert>> enabledAlerts() async => {...alerts};

  @override
  Future<void> setEnabled(RingAlert alert, {required bool enabled}) async {
    if (enabled) {
      alerts.add(alert);
      return;
    }
    alerts.remove(alert);
  }

  @override
  Future<String?> warnedDevice() async => warned;

  @override
  Future<void> setWarnedDevice(String? deviceId) async => warned = deviceId;
}
