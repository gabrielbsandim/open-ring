import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';

final class SpyModuleStore implements ModuleStore {
  new([Set<ModuleId> enabled = const {}])
    : _inner = InMemoryModuleStore(enabled);

  final InMemoryModuleStore _inner;
  final List<Set<ModuleId>> writes = [];
  int? failOnWrite;

  @override
  Future<Set<ModuleId>> read() => _inner.read();

  @override
  Future<void> write(Set<ModuleId> enabled) async {
    final number = writes.length + 1;
    if (number == failOnWrite) throw StateError('disk');
    writes.add({...enabled});
    await _inner.write(enabled);
  }

  @override
  Future<bool> shortcutDismissed() => _inner.shortcutDismissed();

  @override
  Future<void> dismissShortcut({required bool dismissed}) =>
      _inner.dismissShortcut(dismissed: dismissed);
}
