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

    test('the modules are the eight, Goals and Food among them once', () {
      expect(OfferedModule.values, hasLength(8));
      expect(
        OfferedModule.values.where((module) => module.id == ModuleId.goals),
        [OfferedModule.goals],
      );
      expect(
        OfferedModule.values.where((module) => module.id == ModuleId.food),
        [OfferedModule.food],
      );
    });
  });

  group('Food module', () {
    test('has its module id, icon and route', () {
      expect(OfferedModule.food.id, ModuleId.food);
      expect(OfferedModule.food.icon, Icons.restaurant_outlined);
      expect(OfferedModule.food.path, AppPaths.settingsModuleFood);
    });

    test('the route is under Settings, Modules', () {
      expect(AppPaths.settingsModuleFood, '/ring/settings/modules/food');
    });
  });

  group('AI module', () {
    test('has its module id, icon and route', () {
      expect(OfferedModule.ai.id, ModuleId.ai);
      expect(OfferedModule.ai.icon, Icons.chat_bubble_outline_rounded);
      expect(OfferedModule.ai.path, AppPaths.settingsModuleAi);
    });

    test('comes after Food, before Trajectory, and only once', () {
      const values = OfferedModule.values;
      expect(values.indexOf(OfferedModule.ai), values.length - 2);
      expect(OfferedModule.values.where((module) => module.id == ModuleId.ai), [
        OfferedModule.ai,
      ]);
    });
  });

  group('Trajectory module', () {
    test('comes last, needs adults and opens its module screen', () {
      expect(OfferedModule.values.last, OfferedModule.trajectory);
      expect(OfferedModule.trajectory.id, ModuleId.trajectory);
      expect(OfferedModule.trajectory.path, AppPaths.settingsModuleTrajectory);
      expect(OfferedModule.values.where((module) => module.adultOnly), [
        OfferedModule.energy,
        OfferedModule.trajectory,
      ]);
    });
  });

  group('4. where View leads', () {
    test('Goals leads to the goal screen', () {
      expect(OfferedModule.goals.viewPath, AppPaths.goals);
    });

    test('AI leads to the connection screen', () {
      expect(OfferedModule.ai.viewPath, AppPaths.settingsAiConnection);
    });

    test('Trajectory leads to its screen', () {
      expect(OfferedModule.trajectory.viewPath, AppPaths.trajectory);
    });

    test('every other module leads to Today', () {
      for (final module in OfferedModule.values) {
        if ({
          OfferedModule.goals,
          OfferedModule.ai,
          OfferedModule.trajectory,
        }.contains(module)) {
          continue;
        }
        expect(module.viewPath, AppTab.today.path, reason: module.name);
      }
    });
  });
}
