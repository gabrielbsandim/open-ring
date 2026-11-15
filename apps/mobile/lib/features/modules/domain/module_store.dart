import 'package:open_ring/features/modules/domain/module_id.dart';

abstract interface class ModuleStore {
  Future<Set<ModuleId>> read();

  Future<void> write(Set<ModuleId> enabled);

  Future<bool> shortcutDismissed();

  Future<void> dismissShortcut({required bool dismissed});
}

final class InMemoryModuleStore implements ModuleStore {
  new([Set<ModuleId> enabled = const {}]) : _enabled = {...enabled};

  Set<ModuleId> _enabled;
  bool dismissed = false;

  @override
  Future<Set<ModuleId>> read() async => {..._enabled};

  @override
  Future<void> write(Set<ModuleId> enabled) async => _enabled = {...enabled};

  @override
  Future<bool> shortcutDismissed() async => dismissed;

  @override
  Future<void> dismissShortcut({required bool dismissed}) async =>
      this.dismissed = dismissed;
}
