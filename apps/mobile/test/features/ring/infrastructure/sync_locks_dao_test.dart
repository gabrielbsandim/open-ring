import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/infrastructure/sync_locks_dao.dart';

import '../../../helpers/database.dart';

void main() {
  final at = DateTime(2026, 11, 10, 8);
  const timeout = Duration(minutes: 10);

  test('the first owner acquires a free lock', () async {
    final locks = SyncLocksDao(memoryDatabase());

    expect(await locks.acquire('a', at: at, timeout: timeout), isTrue);
    expect((await locks.current())?.owner, 'a');
  });

  test('a held lock refuses a second owner and keeps the first', () async {
    final locks = SyncLocksDao(memoryDatabase());
    await locks.acquire('a', at: at, timeout: timeout);

    final second = await locks.acquire(
      'b',
      at: at.add(const Duration(minutes: 9)),
      timeout: timeout,
    );

    expect(second, isFalse);
    expect((await locks.current())?.owner, 'a');
  });

  test('a lock past its timeout is taken over', () async {
    final locks = SyncLocksDao(memoryDatabase());
    await locks.acquire('a', at: at, timeout: timeout);

    final second = await locks.acquire(
      'b',
      at: at.add(timeout),
      timeout: timeout,
    );

    expect(second, isTrue);
    expect((await locks.current())?.owner, 'b');
  });

  test('release frees the lock only for its owner', () async {
    final locks = SyncLocksDao(memoryDatabase());
    await locks.acquire('a', at: at, timeout: timeout);

    await locks.release('b');
    expect((await locks.current())?.owner, 'a');

    await locks.release('a');
    expect(await locks.current(), isNull);
    expect(await locks.acquire('b', at: at, timeout: timeout), isTrue);
  });
}
