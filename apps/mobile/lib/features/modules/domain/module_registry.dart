import 'package:open_ring/features/modules/domain/module_id.dart';

final class ModuleSpec {
  const new({required this.id, this.requires = const {}});

  final ModuleId id;
  final Set<ModuleId> requires;
}

const List<ModuleSpec> moduleRegistry = [
  ModuleSpec(id: ModuleId.body),
  ModuleSpec(id: ModuleId.openScore),
  ModuleSpec(id: ModuleId.energy),
  ModuleSpec(id: ModuleId.effort),
  ModuleSpec(id: ModuleId.goals),
  ModuleSpec(id: ModuleId.food),
  ModuleSpec(id: ModuleId.ai),
  ModuleSpec(id: ModuleId.trajectory, requires: {ModuleId.body}),
];

Set<ModuleId> missingRequirements(ModuleId id, Set<ModuleId> enabled) => {
  for (final spec in moduleRegistry)
    if (spec.id == id) ...spec.requires.difference(enabled),
};

Set<ModuleId> enabledDependents(ModuleId id, Set<ModuleId> enabled) => {
  for (final spec in moduleRegistry)
    if (spec.requires.contains(id) && enabled.contains(spec.id)) spec.id,
};
