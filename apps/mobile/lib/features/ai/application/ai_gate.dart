import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';

/// Whether the AI module is on. Still loading counts as off.
final aiEnabledProvider = Provider<bool>(
  (ref) =>
      ref.watch(enabledModulesProvider).value?.contains(ModuleId.ai) ?? false,
);

/// Whether imported Health Connect records may reach an AI summary. Off until
/// the Play rule on sending them to a chosen service is checked.
final aiImportedOfferedProvider = Provider<bool>((_) => false);
