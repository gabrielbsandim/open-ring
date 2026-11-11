import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class ProfileKeys {
  static const age = Key('profile_age');
  static const height = Key('profile_height');
  static const weight = Key('profile_weight');
  static const maxHeartRate = Key('profile_max_hr');
  static const resetMaxHeartRate = Key('profile_max_hr_reset');
  static const steps = Key('profile_steps');
  static const continueAction = Key('profile_continue');
  static const skip = Key('profile_skip');
  static const saveFailed = Key('profile_save_failed');

  static Key sex(Sex? sex) => Key('profile_sex_${sex?.name ?? 'none'}');
}

class ProfileScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _maxHeartRate = TextEditingController();
  final _steps = TextEditingController(text: '$defaultStepGoal');
  Sex? _sex;
  bool _maxHeartRateEdited = false;
  bool _saving = false;
  bool _saveFailed = false;

  int get _year => ref.read(clockProvider)().year;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final controller in [_age, _height, _weight, _maxHeartRate, _steps]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await _stored();
    if (!mounted || profile == null) return;
    setState(() {
      _age.text = _text(profile.ageIn(_year));
      _height.text = _text(profile.heightCentimeters?.round());
      _weight.text = _text(profile.weightKilograms);
      _steps.text = _text(profile.dailyStepGoal ?? defaultStepGoal);
      _sex = profile.sex;
      _maxHeartRateEdited = profile.maxHeartRate != null;
      _maxHeartRate.text = _text(profile.maxHeartRate ?? _estimate);
    });
  }

  // An unreadable profile leaves the form empty; saving it writes a new one.
  Future<UserProfile?> _stored() async {
    try {
      return await ref.read(userProfileProvider.future);
    } on Object {
      return null;
    }
  }

  static String _text(num? value) => switch (value) {
    null => '',
    final double v when v == v.roundToDouble() => '${v.round()}',
    final v => '$v',
  };

  static int? _int(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  static double? _decimal(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.'));

  int? get _validAge {
    final age = _int(_age);
    if (age == null || !UserProfile.fits(age, UserProfile.ageRange)) {
      return null;
    }
    return age;
  }

  int? get _estimate => switch (_validAge) {
    null => null,
    final age => maxHeartRateForAge(age),
  };

  String? _error(TextEditingController controller, ValueRange range) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    final value = _decimal(controller);
    if (value != null && UserProfile.fits(value, range)) return null;
    return AppLocalizations.of(context)
        .profileRangeError(range.min.toInt(), range.max.toInt());
  }

  bool get _valid => [
    _error(_age, UserProfile.ageRange),
    _error(_height, UserProfile.heightRange),
    _error(_weight, UserProfile.weightRange),
    _error(_maxHeartRate, UserProfile.maxHeartRateRange),
    _error(_steps, UserProfile.stepGoalRange),
  ].every((error) => error == null);

  void _onAgeChanged(String _) {
    setState(() {
      if (_maxHeartRateEdited) return;
      _maxHeartRate.text = _text(_estimate);
    });
  }

  void _resetMaxHeartRate() => setState(() {
    _maxHeartRateEdited = false;
    _maxHeartRate.text = _text(_estimate);
  });

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    final age = _validAge;
    final profile = UserProfile(
      birthYear: age == null
          ? null
          : UserProfile.birthYearFor(age, year: _year),
      sex: _sex,
      heightCentimeters: _decimal(_height),
      weightKilograms: _decimal(_weight),
      maxHeartRate: _maxHeartRateEdited ? _int(_maxHeartRate) : null,
      dailyStepGoal: _int(_steps),
    );
    final saved = await _persist(profile);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saveFailed = !saved;
    });
    if (!saved) return;
    await context.push(AppPaths.onboardingHealth);
  }

  Future<bool> _persist(UserProfile profile) async {
    try {
      await ref.read(userProfileProvider.notifier).save(profile);
      return true;
    } on Object {
      return false;
    }
  }

  String _maxHeartRateHint(AppLocalizations l10n) {
    if (_maxHeartRateEdited) return l10n.profileMaxHrCustom;
    if (_estimate == null) return l10n.profileMaxHrNeedsAge;
    return l10n.profileMaxHrEstimated;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final estimate = _estimate;
    return OnboardingPage(
      step: 2,
      title: l10n.profileTitle,
      intro: l10n.profileIntro,
      children: [
        _NumberField(
          key: ProfileKeys.age,
          controller: _age,
          label: l10n.profileAge,
          unit: l10n.profileUnitYears,
          error: _error(_age, UserProfile.ageRange),
          onChanged: _onAgeChanged,
        ),
        _NumberField(
          key: ProfileKeys.height,
          controller: _height,
          label: l10n.profileHeight,
          unit: l10n.profileUnitCm,
          error: _error(_height, UserProfile.heightRange),
          onChanged: (_) => setState(() {}),
        ),
        _NumberField(
          key: ProfileKeys.weight,
          controller: _weight,
          label: l10n.profileWeight,
          unit: l10n.profileUnitKg,
          decimal: true,
          error: _error(_weight, UserProfile.weightRange),
          onChanged: (_) => setState(() {}),
        ),
        _SexPicker(
          selected: _sex,
          onSelected: (sex) => setState(() => _sex = sex),
        ),
        const SizedBox(height: 16),
        _NumberField(
          key: ProfileKeys.maxHeartRate,
          controller: _maxHeartRate,
          label: l10n.profileMaxHr,
          unit: l10n.profileUnitBpm,
          helper: _maxHeartRateHint(l10n),
          error: _error(_maxHeartRate, UserProfile.maxHeartRateRange),
          onChanged: (_) => setState(() => _maxHeartRateEdited = true),
        ),
        if (_maxHeartRateEdited)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: ProfileKeys.resetMaxHeartRate,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _resetMaxHeartRate,
              child: Text(
                estimate == null
                    ? l10n.profileMaxHrResetNoAge
                    : l10n.profileMaxHrReset(estimate),
              ),
            ),
          ),
        _NumberField(
          key: ProfileKeys.steps,
          controller: _steps,
          label: l10n.profileStepGoal,
          unit: l10n.profileUnitSteps,
          error: _error(_steps, UserProfile.stepGoalRange),
          onChanged: (_) => setState(() {}),
        ),
        CaptionText(l10n.profileFootnote),
        const SizedBox(height: 20),
        if (_saveFailed) ...[
          InfoNote(
            key: ProfileKeys.saveFailed,
            icon: Icons.error_outline_rounded,
            accent: AppColors.of(context).heart,
            text: l10n.profileSaveFailed,
            live: true,
          ),
          const SizedBox(height: cardGap),
        ],
        PrimaryAction(
          key: ProfileKeys.continueAction,
          label: l10n.onboardingContinue,
          onPressed: _valid && !_saving ? () => unawaited(_save()) : null,
        ),
        const SizedBox(height: 4),
        QuietAction(
          key: ProfileKeys.skip,
          label: l10n.onboardingSkip,
          onPressed: () => context.push(AppPaths.onboardingHealth),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const new({
    required this.controller,
    required this.label,
    required this.unit,
    required this.onChanged,
    this.error,
    this.helper,
    this.decimal = false,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String unit;
  final String? error;
  final String? helper;
  final bool decimal;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: colors.strongBorder),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            decimal ? RegExp('[0-9.,]') : RegExp('[0-9]'),
          ),
        ],
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          helperText: helper,
          helperMaxLines: 4,
          errorText: error,
          errorMaxLines: 4,
          filled: true,
          fillColor: colors.surface,
          border: border,
          enabledBorder: border,
        ),
      ),
    );
  }
}

class _SexPicker extends StatelessWidget {
  const new({required this.selected, required this.onSelected});

  final Sex? selected;
  final ValueChanged<Sex?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <(Sex?, String)>[
      (Sex.female, l10n.profileSexFemale),
      (Sex.male, l10n.profileSexMale),
      (null, l10n.profileSexUnspecified),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.profileSex,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (sex, label) in options)
              ChoiceChip(
                key: ProfileKeys.sex(sex),
                label: Text(label),
                selected: selected == sex,
                onSelected: (_) => onSelected(sex),
              ),
          ],
        ),
        const SizedBox(height: 6),
        CaptionText(l10n.profileSexNote),
      ],
    );
  }
}
