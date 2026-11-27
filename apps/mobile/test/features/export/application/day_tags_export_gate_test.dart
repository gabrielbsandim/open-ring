import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/export/application/export_controller.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';

import '../../../helpers/settings_fakes.dart';

void main() {
  for (final (modules, offered) in [
    (<ModuleId>{}, false),
    ({ModuleId.body}, false),
    ({ModuleId.openScore}, true),
    ({ModuleId.body, ModuleId.openScore}, true),
  ]) {
    test('with modules $modules day tags are exported: $offered', () async {
      final exporter = FakeDataExporter();
      final container = ProviderContainer(
        overrides: [
          ...settingsOverrides(exporter: exporter),
          moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(enabledModulesProvider.future);

      await container.read(exportProvider.notifier).run();

      final kinds = exporter.requests.single.kinds;
      expect(kinds.contains(ExportKind.dayTags), offered);
      expect(
        container.read(exportKindsProvider).contains(ExportKind.dayTags),
        offered,
      );
    });
  }

  test(
    'turning Open Score off drops the kind and leaves the other kinds',
    () async {
      final container = ProviderContainer(
        overrides: [
          ...settingsOverrides(),
          moduleStoreProvider.overrideWithValue(
            InMemoryModuleStore({ModuleId.openScore}),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(enabledModulesProvider.future);
      expect(container.read(exportKindsProvider), contains(ExportKind.dayTags));

      await container
          .read(enabledModulesProvider.notifier)
          .disable(ModuleId.openScore);

      final kinds = container.read(exportKindsProvider);
      expect(kinds, isNot(contains(ExportKind.dayTags)));
      expect(kinds, contains(ExportKind.sleep));
    },
  );
}
