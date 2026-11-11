import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';

import '../../../helpers/ring_fakes.dart';
import '../../../helpers/sync_fixtures.dart';

ProviderContainer _container({PairedRing? paired}) {
  final c = ProviderContainer(
    overrides: [
      ...ringOverrides(paired: paired, driver: loadedDriver()),
      syncClockProvider.overrideWithValue(() => syncNow),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('a completed sync bumps the data revision', () async {
    final c = _container(paired: const PairedRing(deviceId: fakeRingId));

    await c.read(ringSyncProvider.notifier).refresh();

    expect(c.read(dataRevisionProvider), 1);
    expect(c.read(ringSyncProvider).lastSuccessAt, syncNow);
  });

  test('a sync without a ring leaves the revision alone', () async {
    final c = _container();

    await c.read(ringSyncProvider.notifier).refresh();

    expect(c.read(dataRevisionProvider), 0);
    expect(c.read(ringSyncProvider).lastError, isNotNull);
  });
}
