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
  );

  new(this.id, this.icon, this.path);

  final ModuleId id;
  final IconData icon;
  final String path;

  String title(AppLocalizations l10n) => switch (this) {
    OfferedModule.body => l10n.moduleBodyName,
    OfferedModule.openScore => l10n.moduleOpenScoreName,
    OfferedModule.energy => l10n.energyTitle,
  };

  String detail(AppLocalizations l10n) => switch (this) {
    OfferedModule.body => l10n.moduleBodyDetail,
    OfferedModule.openScore => l10n.moduleOpenScoreDetail,
    OfferedModule.energy => l10n.moduleEnergyDetail,
  };

  String turnedOn(AppLocalizations l10n) => switch (this) {
    OfferedModule.body => l10n.moduleBodyTurnedOn,
    OfferedModule.openScore => l10n.moduleOpenScoreTurnedOn,
    OfferedModule.energy => l10n.moduleEnergyTurnedOn(l10n.tabToday),
  };
}
