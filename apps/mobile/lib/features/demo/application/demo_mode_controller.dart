import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/demo/domain/demo_data_generator.dart';
import 'package:open_ring/features/demo/domain/demo_data_store.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';

final demoModeStoreProvider = Provider<DemoModeStore>(
  (ref) => InMemoryDemoModeStore(),
);

final demoDataStoreProvider = Provider<DemoDataStore>(
  (ref) => throw UnimplementedError('Override demoDataStoreProvider.'),
);

final demoModeProvider = NotifierProvider<DemoModeController, bool>(
  DemoModeController.new,
);

class DemoModeController extends Notifier<bool> {
  Future<void>? _seeding;

  @override
  bool build() => ref.watch(demoModeStoreProvider).enabled;

  // The flag is saved before any data exists, so no sync path ever sees the
  // demo ring as a real one.
  Future<bool> enter() async {
    final store = ref.read(demoModeStoreProvider);
    await store.enable();
    state = true;
    try {
      await ref.read(syncSchedulerProvider).cancel();
      await refresh();
      await ref.read(onboardingProvider.notifier).complete();
      return true;
    } on Object {
      await store.disable();
      if (ref.mounted) state = false;
      return false;
    }
  }

  Future<void> refresh() {
    if (!state) return Future.value();
    return _seeding ??= _seed().whenComplete(() => _seeding = null);
  }

  Future<bool> leave() async {
    if (!state) return true;
    try {
      await ref.read(demoDataStoreProvider).wipe();
    } on Object {
      return false;
    }
    await ref.read(demoModeStoreProvider).disable();
    state = false;
    await ref.read(onboardingProvider.notifier).reset();
    ref
      ..invalidate(ringSyncProvider)
      ..read(dataRevisionProvider.notifier).bump();
    return true;
  }

  Future<void> _seed() async {
    final data = DemoDataGenerator(now: ref.read(clockProvider)()).generate();
    await ref.read(demoDataStoreProvider).replace(data);
    if (!ref.mounted) return;
    ref.read(dataRevisionProvider.notifier).bump();
  }
}
