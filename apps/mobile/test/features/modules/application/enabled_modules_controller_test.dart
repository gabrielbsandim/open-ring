import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';

final class _SlowStore implements ModuleStore {
  Set<ModuleId> stored = {};

  @override
  Future<Set<ModuleId>> read() async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return {...stored};
  }

  @override
  Future<void> write(Set<ModuleId> enabled) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    stored = {...enabled};
  }
}

void main() {
  late InMemoryModuleStore store;
  late ProviderContainer container;

  setUp(() {
    store = InMemoryModuleStore();
    container = ProviderContainer.test(
      overrides: [moduleStoreProvider.overrideWithValue(store)],
    );
  });

  test('a fresh container reads the empty set', () async {
    expect(await container.read(enabledModulesProvider.future), isEmpty);
  });

  test('enabling trajectory without body writes nothing', () async {
    await container.read(enabledModulesProvider.future);

    final blocking = await container
        .read(enabledModulesProvider.notifier)
        .enable(ModuleId.trajectory);

    expect(blocking, {ModuleId.body});
    expect(container.read(enabledModulesProvider).value, isEmpty);
    expect(await store.read(), isEmpty);
  });

  test('enabling body then trajectory both succeed and persist', () async {
    final notifier = container.read(enabledModulesProvider.notifier);
    await container.read(enabledModulesProvider.future);

    expect(await notifier.enable(ModuleId.body), isEmpty);
    expect(await notifier.enable(ModuleId.trajectory), isEmpty);

    const both = {ModuleId.body, ModuleId.trajectory};
    expect(container.read(enabledModulesProvider).value, both);
    expect(await store.read(), both);
  });

  test('disabling body while trajectory is on is blocked', () async {
    final notifier = container.read(enabledModulesProvider.notifier);
    await container.read(enabledModulesProvider.future);
    await notifier.enable(ModuleId.body);
    await notifier.enable(ModuleId.trajectory);

    expect(await notifier.disable(ModuleId.body), {ModuleId.trajectory});

    const both = {ModuleId.body, ModuleId.trajectory};
    expect(container.read(enabledModulesProvider).value, both);
    expect(await store.read(), both);
  });

  test('disabling trajectory first lets body be disabled', () async {
    final notifier = container.read(enabledModulesProvider.notifier);
    await container.read(enabledModulesProvider.future);
    await notifier.enable(ModuleId.body);
    await notifier.enable(ModuleId.trajectory);

    expect(await notifier.disable(ModuleId.trajectory), isEmpty);
    expect(await notifier.disable(ModuleId.body), isEmpty);

    expect(container.read(enabledModulesProvider).value, isEmpty);
    expect(await store.read(), isEmpty);
  });

  test('two enables issued without awaiting both end stored', () async {
    final slow = _SlowStore();
    final c = ProviderContainer.test(
      overrides: [moduleStoreProvider.overrideWithValue(slow)],
    );
    await c.read(enabledModulesProvider.future);
    final notifier = c.read(enabledModulesProvider.notifier);

    final first = notifier.enable(ModuleId.body);
    final second = notifier.enable(ModuleId.food);

    expect(await first, isEmpty);
    expect(await second, isEmpty);
    const both = {ModuleId.body, ModuleId.food};
    expect(slow.stored, both);
    expect(c.read(enabledModulesProvider).value, both);
  });

  test('the set read from the store at start is the initial state', () async {
    final c = ProviderContainer.test(
      overrides: [
        moduleStoreProvider.overrideWithValue(
          InMemoryModuleStore({ModuleId.body, ModuleId.trajectory}),
        ),
      ],
    );

    expect(await c.read(enabledModulesProvider.future), {
      ModuleId.body,
      ModuleId.trajectory,
    });
  });
}
