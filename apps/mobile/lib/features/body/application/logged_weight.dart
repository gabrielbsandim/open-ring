import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';

final loggedWeightProvider = FutureProvider<double?>((ref) async {
  final modules = await ref.watch(enabledModulesProvider.future);
  if (!modules.contains(ModuleId.body)) return null;
  final entries = await ref.watch(weighInsProvider.future);
  return entries.firstOrNull?.kilograms;
});
