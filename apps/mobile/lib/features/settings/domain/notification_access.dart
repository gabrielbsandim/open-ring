abstract interface class NotificationAccess {
  Future<bool> enabled();

  Future<void> openSettings();
}

final class InMemoryNotificationAccess implements NotificationAccess {
  new({this.allowed = true});

  bool allowed;
  int settingsOpened = 0;

  @override
  Future<bool> enabled() async => allowed;

  @override
  Future<void> openSettings() async => settingsOpened++;
}
