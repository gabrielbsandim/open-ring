abstract interface class HideNumbersStore {
  Future<bool> read();

  Future<void> write({required bool hidden});
}

final class InMemoryHideNumbersStore implements HideNumbersStore {
  new({this.hidden = false});

  bool hidden;

  @override
  Future<bool> read() async => hidden;

  @override
  Future<void> write({required bool hidden}) async => this.hidden = hidden;
}
