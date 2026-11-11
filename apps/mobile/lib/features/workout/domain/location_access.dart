enum LocationAccessStatus {
  granted,
  denied,
  deniedForever,
  serviceDisabled;

  bool get isGranted => this == granted;
}

abstract interface class LocationAccess {
  Future<LocationAccessStatus> status();

  Future<LocationAccessStatus> request();

  Future<void> openAppSettings();

  Future<void> openLocationSettings();
}
