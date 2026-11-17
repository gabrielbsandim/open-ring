import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/presentation/offered_module.dart';

void main() {
  group('1. the Goals module', () {
    test('has its module id, icon and route', () {
      expect(OfferedModule.goals.id, ModuleId.goals);
      expect(OfferedModule.goals.icon, Icons.flag_outlined);
      expect(OfferedModule.goals.path, AppPaths.settingsModuleGoals);
    });

    test('the route is under Settings, Modules', () {
      expect(AppPaths.settingsModuleGoals, '/ring/settings/modules/goals');
    });

    test('the modules are the five, Goals among them once', () {
      expect(OfferedModule.values, hasLength(5));
      expect(
        OfferedModule.values.where((module) => module.id == ModuleId.goals),
        [OfferedModule.goals],
      );
    });
  });

  group('4. where View leads', () {
    test('Goals leads to the goal screen', () {
      expect(OfferedModule.goals.viewPath, AppPaths.goals);
    });

    test('every other module leads to Today', () {
      for (final module in OfferedModule.values) {
        if (module == OfferedModule.goals) continue;
        expect(module.viewPath, AppTab.today.path, reason: module.name);
      }
    });
  });
}
