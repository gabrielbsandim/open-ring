import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_registry.dart';

void main() {
  test('the registry holds exactly one spec per module', () {
    final ids = moduleRegistry.map((spec) => spec.id).toList();

    expect(ids.toSet(), ModuleId.values.toSet());
    expect(ids, hasLength(ModuleId.values.length));
  });

  test('no module requires itself', () {
    for (final spec in moduleRegistry) {
      expect(spec.requires, isNot(contains(spec.id)), reason: '${spec.id}');
    }
  });

  test('the requirement graph has no cycle', () {
    final requires = {for (final s in moduleRegistry) s.id: s.requires};

    bool reaches(ModuleId from, ModuleId target, Set<ModuleId> seen) {
      if (!seen.add(from)) return false;
      final next = requires[from] ?? const <ModuleId>{};
      return next.contains(target) ||
          next.any((id) => reaches(id, target, seen));
    }

    for (final id in ModuleId.values) {
      expect(reaches(id, id, {}), isFalse, reason: '$id');
    }
  });

  test('trajectory requires body and nothing else requires anything', () {
    final requires = {for (final s in moduleRegistry) s.id: s.requires};

    expect(requires[ModuleId.trajectory], {ModuleId.body});
    for (final id in ModuleId.values.where((i) => i != ModuleId.trajectory)) {
      expect(requires[id], isEmpty, reason: '$id');
    }
  });

  test('missingRequirements names the absent requirements', () {
    expect(missingRequirements(ModuleId.trajectory, {}), {ModuleId.body});
    expect(
      missingRequirements(ModuleId.trajectory, {ModuleId.body}),
      isEmpty,
    );
    expect(missingRequirements(ModuleId.body, {}), isEmpty);
  });

  test('enabledDependents names the enabled modules that need it', () {
    expect(
      enabledDependents(ModuleId.body, {ModuleId.body, ModuleId.trajectory}),
      {ModuleId.trajectory},
    );
    expect(enabledDependents(ModuleId.body, {ModuleId.body}), isEmpty);
    expect(enabledDependents(ModuleId.trajectory, {ModuleId.body}), isEmpty);
  });
}
