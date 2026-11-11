enum AppPermission { bluetooth, notifications, backgroundExecution, location }

enum PermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  notApplicable;

  bool get isGranted => this == granted;
}

// request() returns at once without a system prompt when the permission is
// already granted, so callers can request on every attempt.
abstract interface class AppPermissions {
  Future<PermissionStatus> status(AppPermission permission);

  Future<PermissionStatus> request(AppPermission permission);

  Future<void> openSettings();
}
