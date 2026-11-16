import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

// The parts print to the nearest ten: a finer figure would claim more than
// the estimate knows.
const energyPartStep = 10;

enum EnergyPart { base, steps, workouts }

double energyPartValue(EnergyDayEstimate day, EnergyPart part) =>
    switch (part) {
      EnergyPart.base => day.base,
      EnergyPart.steps => day.steps,
      EnergyPart.workouts => day.workouts,
    };

int energyPartShown(double value) =>
    (value / energyPartStep).round() * energyPartStep;

Color energyPartColor(AppColors colors, EnergyPart part) => switch (part) {
  EnergyPart.base => colors.textLabel,
  EnergyPart.steps => colors.activity,
  EnergyPart.workouts => colors.textPrimary,
};

String energyPartLabel(AppLocalizations l10n, EnergyPart part) =>
    switch (part) {
      EnergyPart.base => l10n.energyPartBase,
      EnergyPart.steps => l10n.energyPartSteps,
      EnergyPart.workouts => l10n.energyPartWorkouts,
    };
