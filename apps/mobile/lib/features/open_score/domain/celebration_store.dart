/// Remembers the last day whose celebration card the user closed.
abstract interface class CelebrationStore {
  Future<String?> read();

  Future<void> write(String isoDate);
}

final class InMemoryCelebrationStore implements CelebrationStore {
  new([this.closed]);

  String? closed;

  @override
  Future<String?> read() async => closed;

  @override
  Future<void> write(String isoDate) async => closed = isoDate;
}
