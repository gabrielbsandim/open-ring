import 'package:flutter/material.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

enum OfferedModule {
  body(
    ModuleId.body,
    Icons.monitor_weight_outlined,
    AppPaths.settingsModuleBody,
  ),
  openScore(
    ModuleId.openScore,
    Icons.speed_rounded,
    AppPaths.settingsModuleOpenScore,
  ),
  energy(
    ModuleId.energy,
    Icons.local_fire_department_outlined,
    AppPaths.settingsModuleEnergy,
  ),
  effort(ModuleId.effort, Icons.bolt_rounded, AppPaths.settingsModuleEffort),
  goals(ModuleId.goals, Icons.flag_outlined, AppPaths.settingsModuleGoals),
  food(ModuleId.food, Icons.restaurant_outlined, AppPaths.settingsModuleFood),
  ai(ModuleId.ai, Icons.chat_bubble_outline_rounded, AppPaths.settingsModuleAi),
  trajectory(
    ModuleId.trajectory,
    Icons.route_outlined,
    AppPaths.settingsModuleTrajectory,
  );

  new(this.id, this.icon, this.path);

  final ModuleId id;
  final IconData icon;
  final String path;

  String title(AppLocalizations l10n) => switch (this) {
    OfferedModule.body => l10n.moduleBodyName,
    OfferedModule.openScore => l10n.moduleOpenScoreName,
    OfferedModule.energy => l10n.energyTitle,
    OfferedModule.effort => l10n.effortTitle,
    OfferedModule.goals => l10n.moduleGoalsName,
    OfferedModule.food => l10n.foodTitle,
    OfferedModule.ai => l10n.moduleAiName,
    OfferedModule.trajectory => l10n.moduleTrajectoryName,
  };

  String detail(AppLocalizations l10n) => switch (this) {
    OfferedModule.body => l10n.moduleBodyDetail,
    OfferedModule.openScore => l10n.moduleOpenScoreDetail,
    OfferedModule.energy => l10n.moduleEnergyDetail,
    OfferedModule.effort => l10n.moduleEffortDetail,
    OfferedModule.goals => l10n.moduleGoalsDetail,
    OfferedModule.food => l10n.moduleFoodDetail,
    OfferedModule.ai => l10n.moduleAiDetail,
    OfferedModule.trajectory => l10n.moduleTrajectoryDetail,
  };

  String turnedOn(AppLocalizations l10n) => switch (this) {
    OfferedModule.body => l10n.moduleBodyTurnedOn,
    OfferedModule.openScore => l10n.moduleOpenScoreTurnedOn,
    OfferedModule.energy => l10n.moduleEnergyTurnedOn(l10n.tabToday),
    OfferedModule.effort => l10n.moduleEffortTurnedOn(l10n.tabToday),
    OfferedModule.goals => l10n.moduleGoalsTurnedOn,
    OfferedModule.food => l10n.moduleFoodTurnedOn(l10n.tabToday),
    OfferedModule.ai => l10n.moduleAiTurnedOn,
    OfferedModule.trajectory => l10n.moduleTrajectoryTurnedOn(
      l10n.moduleBodyName,
    ),
  };

  /// Energy and Trajectory use equations built with adults only.
  bool get adultOnly => this == energy || this == trajectory;

  /// Where View goes after switching on: Goals, AI and Trajectory show
  /// nothing on Today, so each opens its own screen.
  String get viewPath => switch (this) {
    OfferedModule.goals => AppPaths.goals,
    OfferedModule.ai => AppPaths.settingsAiConnection,
    OfferedModule.trajectory => AppPaths.trajectory,
    _ => AppTab.today.path,
  };
}
