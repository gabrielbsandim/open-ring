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

    test('the modules are the seven, Goals and Food among them once', () {
      expect(OfferedModule.values, hasLength(7));
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

    test('comes last, after Food, and only once', () {
      expect(OfferedModule.values.last, OfferedModule.ai);
      expect(OfferedModule.values.where((module) => module.id == ModuleId.ai), [
        OfferedModule.ai,
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

    test('every other module leads to Today', () {
      for (final module in OfferedModule.values) {
        if (module == OfferedModule.goals || module == OfferedModule.ai) {
          continue;
        }
        expect(module.viewPath, AppTab.today.path, reason: module.name);
      }
    });
  });
}
