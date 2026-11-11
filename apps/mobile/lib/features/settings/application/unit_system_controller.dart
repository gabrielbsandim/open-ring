import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';

final unitSystemStoreProvider = Provider<UnitSystemStore>(
  (ref) => InMemoryUnitSystemStore(),
);

final unitSystemProvider =
    AsyncNotifierProvider<UnitSystemController, UnitSystem>(
      UnitSystemController.new,
    );

class UnitSystemController extends AsyncNotifier<UnitSystem> {
  @override
  Future<UnitSystem> build() async =>
      await ref.watch(unitSystemStoreProvider).read() ?? UnitSystem.metric;

  Future<void> select(UnitSystem units) async {
    state = AsyncData(units);
    await ref.read(unitSystemStoreProvider).write(units);
  }
}

final currentUnitSystemProvider = Provider<UnitSystem>(
  (ref) => ref.watch(unitSystemProvider).value ?? UnitSystem.metric,
);
