abstract interface class DemoModeStore {
  bool get enabled;

  Future<void> enable();

  Future<void> disable();
}

final class InMemoryDemoModeStore implements DemoModeStore {
  new({this.enabled = false});

  @override
  bool enabled;

  @override
  Future<void> enable() async => enabled = true;

  @override
  Future<void> disable() async => enabled = false;
}
