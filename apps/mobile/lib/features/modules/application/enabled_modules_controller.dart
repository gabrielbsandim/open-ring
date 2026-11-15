import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_registry.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';

final moduleStoreProvider = Provider<ModuleStore>(
  (ref) => InMemoryModuleStore(),
);

final enabledModulesProvider =
    AsyncNotifierProvider<EnabledModulesController, Set<ModuleId>>(
      EnabledModulesController.new,
    );

typedef _Rule = Set<ModuleId> Function(Set<ModuleId> enabled);

class EnabledModulesController extends AsyncNotifier<Set<ModuleId>> {
  Future<void> _queue = Future.value();

  @override
  Future<Set<ModuleId>> build() => ref.watch(moduleStoreProvider).read();

  Future<Set<ModuleId>> enable(ModuleId id) => _change(
    blocking: (enabled) => missingRequirements(id, enabled),
    next: (enabled) => {...enabled, id},
  );

  Future<Set<ModuleId>> disable(ModuleId id) => _change(
    blocking: (enabled) => enabledDependents(id, enabled),
    next: (enabled) => enabled.difference({id}),
  );

  // Changes run one at a time: each reads the set the previous one wrote.
  Future<Set<ModuleId>> _change({
    required _Rule blocking,
    required _Rule next,
  }) {
    final result = _queue.then((_) => _apply(blocking, next));
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Set<ModuleId>> _apply(_Rule blocking, _Rule next) async {
    final enabled = await future;
    final blockers = blocking(enabled);
    if (blockers.isNotEmpty) return blockers;
    final updated = next(enabled);
    await ref.read(moduleStoreProvider).write(updated);
    state = AsyncData(updated);
    return const {};
  }
}

final modulesShortcutProvider =
    AsyncNotifierProvider<ModulesShortcutController, bool>(
      ModulesShortcutController.new,
    );

class ModulesShortcutController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.watch(moduleStoreProvider).shortcutDismissed();

  Future<void> set({required bool dismissed}) async {
    state = AsyncData(dismissed);
    await ref.read(moduleStoreProvider).dismissShortcut(dismissed: dismissed);
  }
}
