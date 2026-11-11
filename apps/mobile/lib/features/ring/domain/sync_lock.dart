abstract interface class SyncLock {
  Future<bool> acquire(
    String owner, {
    required DateTime at,
    required Duration timeout,
  });

  Future<void> release(String owner);
}
