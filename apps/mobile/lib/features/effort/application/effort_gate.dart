import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';

/// Whether the Effort module is on. Still loading counts as off.
final effortEnabledProvider = Provider<bool>(
  (ref) =>
      ref.watch(enabledModulesProvider).value?.contains(ModuleId.effort) ??
      false,
);
