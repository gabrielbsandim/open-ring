import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/goals/application/goal_intake_providers.dart';
import 'package:open_ring/features/goals/application/goals_gate.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';
import 'package:open_ring/features/goals/presentation/goal_pick_screen.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class GoalRefusalKeys {
  static const primary = Key('goal_refusal_primary');
  static const secondary = Key('goal_refusal_secondary');
}

/// What one refusal says and where its two buttons lead.
typedef _Refusal = ({
  String title,
  List<String> body,
  String? rule,
  ({String title, List<String> items})? facts,
  String primary,
  String primaryPath,
  String secondary,
  String secondaryPath,
});

// The slack absorbs binary noise only: 103.5 lb converted to kilograms and
// back lands a hair under 103.5, which must not read 103.4.
double _floorTenth(double value) => (value * 10 + 1e-9).floorToDouble() / 10;

double _ceilTenth(double value) => (value * 10 - 1e-9).ceilToDouble() / 10;

class GoalRefusalScreen extends ConsumerWidget {
  const new({required this.block, super.key});

  final IntakeBlock? block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final empty = AppPage(title: l10n.goalsPickGroup, children: const []);
    if (!ref.watch(goalsEnabledProvider) || !_refusable.contains(block)) {
      return empty;
    }
    final facts = ref.watch(intakeFactsProvider);
    if (facts.hasError) {
      return AppPage(
        title: l10n.goalsPickGroup,
        children: [BodyText(l10n.metricLoadError)],
      );
    }
    final current = facts.value;
    if (current == null) return empty;
    if (!_holds(current)) {
      return const GoalPickScreen(initial: GoalKind.loseFat);
    }
    final refusal = _refusal(context, ref, l10n);
    if (refusal == null) return empty;
    return AppPage(
      title: refusal.title,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MetricCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, paragraph) in refusal.body.indexed) ...[
                    if (index > 0) const SizedBox(height: 10),
                    BodyText(paragraph),
                  ],
                  if (refusal.rule case final rule?) ...[
                    const SizedBox(height: 14),
                    _Rule(text: rule),
                  ],
                ],
              ),
            ),
            if (refusal.facts case final facts?) ...[
              const SizedBox(height: 16),
              ModuleFactsCard(
                title: facts.title,
                icon: Icons.checklist_rounded,
                facts: facts.items,
              ),
            ],
            const SizedBox(height: 16),
            ActionButton(
              buttonKey: GoalRefusalKeys.primary,
              label: refusal.primary,
              onPressed: () => context.go(refusal.primaryPath),
            ),
            const SizedBox(height: 10),
            SecondaryButton(
              buttonKey: GoalRefusalKeys.secondary,
              label: refusal.secondary,
              onPressed: () => context.go(refusal.secondaryPath),
            ),
            const SizedBox(height: 16),
            CaptionText(l10n.goalsRefusalFoot),
          ],
        ),
      ],
    );
  }

  // The tab keeps this page while the profile changes elsewhere, so the
  // address alone may name a block that no longer holds.
  bool _holds(IntakeFacts facts) =>
      _shown(weightGoalBlock(facts)) == _shown(block);

  static const Set<IntakeBlock?> _refusable = {
    IntakeBlock.softMode,
    IntakeBlock.under18,
    IntakeBlock.ageMissing,
    IntakeBlock.heightMissing,
    IntakeBlock.bmiUnderFloor,
  };

  static IntakeBlock? _shown(IntakeBlock? block) =>
      block == IntakeBlock.heightMissing ? IntakeBlock.ageMissing : block;

  _Refusal? _refusal(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) => switch (block) {
    IntakeBlock.softMode => _soft(l10n),
    IntakeBlock.under18 => _under18(ref, l10n),
    IntakeBlock.ageMissing || IntakeBlock.heightMissing => _profile(l10n),
    IntakeBlock.bmiUnderFloor => _bmi(context, ref, l10n),
    _ => null,
  };

  _Refusal _soft(AppLocalizations l10n) => (
    title: l10n.goalsSoftTitle,
    body: [l10n.goalsSoftBody1, l10n.goalsSoftBody2],
    rule: l10n.goalsSoftRule,
    facts: (
      title: l10n.goalsSoftFactsTitle,
      items: [l10n.goalsSoftFact1, l10n.goalsSoftFact2, l10n.goalsSoftFact3],
    ),
    primary: l10n.goalsRefusalSeeNoWeight,
    primaryPath: AppPaths.goalsPickWith(GoalKind.getFitter),
    secondary: l10n.goalsPickContinueNone,
    secondaryPath: AppTab.today.path,
  );

  _Refusal? _under18(WidgetRef ref, AppLocalizations l10n) {
    final profile = ref.watch(userProfileProvider).value;
    final birthYear = profile?.birthYear;
    final age = profile?.ageIn(ref.watch(currentDateProvider).year);
    if (birthYear == null || age == null) return null;
    return (
      title: l10n.goalsUnder18Title,
      body: [l10n.goalsUnder18Body1('$age'), l10n.goalsUnder18Body2],
      rule: l10n.goalsUnder18Rule('${weightGoalsOpenYear(birthYear)}'),
      facts: null,
      primary: l10n.goalsRefusalSeeNoWeight,
      primaryPath: AppPaths.goalsPickWith(GoalKind.getFitter),
      secondary: l10n.goalsPickContinueNone,
      secondaryPath: AppTab.today.path,
    );
  }

  _Refusal _profile(AppLocalizations l10n) => (
    title: l10n.goalsProfileTitle,
    body: [l10n.goalsProfileBody],
    rule: null,
    facts: null,
    primary: l10n.goalsProfileOpen,
    primaryPath: AppPaths.settings,
    secondary: l10n.goalsRefusalSeeNoWeight,
    secondaryPath: AppPaths.goalsPickWith(GoalKind.getFitter),
  );

  _Refusal? _bmi(BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    final hidden = ref.watch(hideNumbersProvider);
    final heightCm = ref.watch(userProfileProvider).value?.heightCentimeters;
    final trendKg = ref.watch(weightSummaryProvider).value?.trend;
    if (!hidden.hasValue || heightCm == null || trendKg == null) return null;
    final shown = (hidden.value ?? true)
        ? (body: l10n.goalsBmiBody1Hidden, rule: l10n.goalsBmiRuleHidden)
        : _bmiFigures(UnitFormat.of(context, ref), l10n, heightCm, trendKg);
    return (
      title: l10n.goalsBmiTitle,
      body: [shown.body, l10n.goalsBmiBody2],
      rule: shown.rule,
      facts: null,
      primary: l10n.goalsRefusalSeeOthers,
      primaryPath: AppPaths.goalsPickWith(GoalKind.getFitter),
      secondary: l10n.goalsPickContinueNone,
      secondaryPath: AppTab.today.path,
    );
  }

  ({String body, String rule}) _bmiFigures(
    UnitFormat units,
    AppLocalizations l10n,
    double heightCm,
    double trendKg,
  ) {
    final meters = heightCm / 100;
    String weight(double tenth) =>
        '${units.format.decimal(tenth, digits: 1)} ${units.weightUnit}';
    final trend = _floorTenth(units.bodyWeightIn(trendKg));
    final floor = _ceilTenth(units.bodyWeightIn(bmiFloor * meters * meters));
    final index = shownBmi(bmi(trendKg, heightCm));
    return (
      body: l10n.goalsBmiBody1(weight(trend), units.height(heightCm)),
      rule: l10n.goalsBmiRule(
        units.format.decimal(index, digits: 1),
        weight(floor),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(
            Icons.receipt_long_outlined,
            size: 20,
            color: colors.textLabel,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [CaptionText(l10n.goalsRefusalRule), CaptionText(text)],
          ),
        ),
      ],
    );
  }
}
