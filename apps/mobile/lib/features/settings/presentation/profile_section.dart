import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/settings/presentation/profile_editor.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class ProfileSectionKeys {
  static const loadError = Key('settings_profile_load_error');

  static Key field(ProfileField field) => Key('settings_profile_${field.name}');
}

IntRange _inward(ValueRange range, double Function(double) convert) => (
  min: convert(range.min.toDouble()).ceil(),
  max: convert(range.max.toDouble()).floor(),
);

IntRange _ints(ValueRange range) =>
    (min: range.min.toInt(), max: range.max.toInt());

class ProfileSection extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stored = ref.watch(userProfileProvider);
    final profile = stored.value;
    final locked = profile == null && stored.hasError;
    final units = ref.watch(unitSystemProvider).value ?? UnitSystem.metric;
    final year = ref.watch(clockProvider)().year;
    final text = ProfileText(MetricFormat.of(context), units);
    final l10n = text.format.l10n;
    final age = profile?.ageIn(year);
    final maxHeartRate = profile?.maxHeartRate;
    final estimate = age == null ? null : maxHeartRateForAge(age);
    final group = TileGroup(
      children: [
        _tile(
          ref,
          context,
          ProfileField.age,
          locked: locked,
          title: l10n.profileAge,
          detail: l10n.settingsAgeDetail,
          value: text.age(age),
        ),
        _tile(
          ref,
          context,
          ProfileField.sex,
          locked: locked,
          title: l10n.profileSex,
          detail: l10n.profileSexNote,
          value: text.sex(profile?.sex),
        ),
        _tile(
          ref,
          context,
          ProfileField.height,
          locked: locked,
          title: l10n.profileHeight,
          detail: l10n.settingsHeightDetail,
          value: text.height(profile?.heightCentimeters),
        ),
        _tile(
          ref,
          context,
          ProfileField.weight,
          locked: locked,
          title: l10n.profileWeight,
          detail: l10n.settingsWeightDetail,
          value: text.weight(profile?.weightKilograms),
        ),
        _tile(
          ref,
          context,
          ProfileField.maxHeartRate,
          locked: locked,
          title: l10n.profileMaxHr,
          detail: switch ((maxHeartRate, estimate)) {
            (int(), _) => l10n.settingsMaxHrCustom,
            (null, int()) => l10n.settingsMaxHrEstimated,
            (null, null) => l10n.profileMaxHrNeedsAge,
          },
          value: text.bpm(maxHeartRate ?? estimate),
        ),
        _tile(
          ref,
          context,
          ProfileField.stepGoal,
          locked: locked,
          title: l10n.settingsStepGoal,
          detail: l10n.settingsStepGoalDetail,
          value: text.steps(profile?.dailyStepGoal ?? defaultStepGoal),
        ),
      ],
    );
    if (!locked) return group;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoNote(
          key: ProfileSectionKeys.loadError,
          icon: Icons.error_outline_rounded,
          accent: AppColors.of(context).heart,
          text: l10n.profileLoadError,
          live: true,
        ),
        const SizedBox(height: cardGap),
        group,
      ],
    );
  }

  // A profile that could not be read stays read only, so one edit cannot
  // overwrite every stored field with blanks.
  Widget _tile(
    WidgetRef ref,
    BuildContext context,
    ProfileField field, {
    required bool locked,
    required String title,
    required String detail,
    required String value,
  }) => SettingsTile(
    key: ProfileSectionKeys.field(field),
    title: title,
    detail: detail,
    value: value,
    onTap: locked ? null : () => unawaited(_edit(ref, context, field, title)),
  );

  Future<void> _edit(
    WidgetRef ref,
    BuildContext context,
    ProfileField field,
    String title,
  ) async {
    final profile = ref.read(userProfileProvider).value;
    final units = ref.read(unitSystemProvider).value ?? UnitSystem.metric;
    final edited = await switch (field) {
      ProfileField.sex => _editSex(context, profile),
      ProfileField.age => _editAge(ref, context, profile, title),
      ProfileField.height => _editHeight(context, profile, title, units),
      ProfileField.weight => _editWeight(context, profile, title, units),
      ProfileField.maxHeartRate => _editMaxHeartRate(context, profile, title),
      ProfileField.stepGoal => _editStepGoal(context, profile, title),
    };
    if (edited == null) return;
    try {
      await ref.read(userProfileProvider.notifier).save(edited);
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).profileSaveFailed)),
      );
    }
  }

  Future<UserProfile?> _editSex(
    BuildContext context,
    UserProfile? profile,
  ) async {
    final picked = await showSexEditor(context, profile?.sex);
    if (picked == null) return null;
    return editProfile(profile, sex: picked.sex);
  }

  Future<UserProfile?> _editAge(
    WidgetRef ref,
    BuildContext context,
    UserProfile? profile,
    String title,
  ) async {
    final year = ref.read(clockProvider)().year;
    final edit = await showNumberEditor(
      context,
      title: title,
      unit: AppLocalizations.of(context).profileUnitYears,
      initial: profile?.ageIn(year)?.toDouble(),
      range: _ints(UserProfile.ageRange),
    );
    if (edit == null) return null;
    final age = edit.value?.round();
    return editProfile(
      profile,
      birthYear: age == null ? null : UserProfile.birthYearFor(age, year: year),
    );
  }

  Future<UserProfile?> _editHeight(
    BuildContext context,
    UserProfile? profile,
    String title,
    UnitSystem units,
  ) async {
    final l10n = AppLocalizations.of(context);
    final imperial = units == UnitSystem.imperial;
    final current = profile?.heightCentimeters;
    final edit = await showNumberEditor(
      context,
      title: title,
      unit: imperial ? l10n.settingsInchesUnit : l10n.profileUnitCm,
      initial: imperial && current != null
          ? ImperialUnits.inches(current).roundToDouble()
          : current,
      range: imperial
          ? _inward(UserProfile.heightRange, ImperialUnits.inches)
          : _ints(UserProfile.heightRange),
    );
    if (edit == null) return null;
    final value = edit.value;
    final centimeters = imperial && value != null
        ? ImperialUnits.centimeters(value)
        : value;
    return editProfile(
      profile,
      heightCentimeters: centimeters == null ? null : _tenths(centimeters),
    );
  }

  Future<UserProfile?> _editWeight(
    BuildContext context,
    UserProfile? profile,
    String title,
    UnitSystem units,
  ) async {
    final l10n = AppLocalizations.of(context);
    final imperial = units == UnitSystem.imperial;
    final current = profile?.weightKilograms;
    final edit = await showNumberEditor(
      context,
      title: title,
      unit: imperial ? l10n.settingsPoundsUnit : l10n.profileUnitKg,
      initial: imperial && current != null
          ? ImperialUnits.pounds(current).roundToDouble()
          : current,
      range: imperial
          ? _inward(UserProfile.weightRange, ImperialUnits.pounds)
          : _ints(UserProfile.weightRange),
      decimal: !imperial,
    );
    if (edit == null) return null;
    final value = edit.value;
    final kilograms = imperial && value != null
        ? ImperialUnits.kilograms(value)
        : value;
    return editProfile(
      profile,
      weightKilograms: kilograms == null ? null : _tenths(kilograms),
    );
  }

  Future<UserProfile?> _editMaxHeartRate(
    BuildContext context,
    UserProfile? profile,
    String title,
  ) async {
    final edit = await showNumberEditor(
      context,
      title: title,
      unit: AppLocalizations.of(context).profileUnitBpm,
      initial: profile?.maxHeartRate?.toDouble(),
      range: _ints(UserProfile.maxHeartRateRange),
    );
    if (edit == null) return null;
    return editProfile(profile, maxHeartRate: edit.value?.round());
  }

  Future<UserProfile?> _editStepGoal(
    BuildContext context,
    UserProfile? profile,
    String title,
  ) async {
    final edit = await showNumberEditor(
      context,
      title: title,
      unit: AppLocalizations.of(context).profileUnitSteps,
      initial: (profile?.dailyStepGoal ?? defaultStepGoal).toDouble(),
      range: _ints(UserProfile.stepGoalRange),
    );
    if (edit == null) return null;
    return editProfile(profile, dailyStepGoal: edit.value?.round());
  }

  static double _tenths(double value) => (value * 10).roundToDouble() / 10;
}

final class ProfileText {
  const new(this.format, this.units);

  final MetricFormat format;
  final UnitSystem units;

  AppLocalizations get _l10n => format.l10n;

  UnitFormat get _units => UnitFormat(format, units);

  String age(int? years) => switch (years) {
    null => _l10n.settingsNotSet,
    final value => '${format.integer(value)} ${_l10n.profileUnitYears}',
  };

  String sex(Sex? sex) => switch (sex) {
    Sex.female => _l10n.profileSexFemale,
    Sex.male => _l10n.profileSexMale,
    null => _l10n.settingsNotSet,
  };

  String height(double? centimeters) => switch (centimeters) {
    null => _l10n.settingsNotSet,
    final value => _units.height(value),
  };

  String weight(double? kilograms) => switch (kilograms) {
    null => _l10n.settingsNotSet,
    final value => _units.weight(value),
  };

  String bpm(int? value) => switch (value) {
    null => _l10n.settingsNotSet,
    final bpm => format.bpm(bpm.toDouble()),
  };

  String steps(int value) =>
      '${format.integer(value)} ${_l10n.profileUnitSteps}';
}
