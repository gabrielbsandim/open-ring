import 'dart:async';

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
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/goals/application/goal_intake_providers.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goals_gate.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';
import 'package:open_ring/features/goals/domain/goal_setup.dart';
import 'package:open_ring/features/goals/presentation/goal_pick_screen.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class GoalSetupKeys {
  static const pregnancyNo = Key('goal_setup_pregnancy_no');
  static const pregnancyYes = Key('goal_setup_pregnancy_yes');
  static const paceGentle = Key('goal_setup_pace_gentle');
  static const paceStandard = Key('goal_setup_pace_standard');
  static const referenceAdd = Key('goal_setup_reference_add');
  static const referenceRemove = Key('goal_setup_reference_remove');
  static const referenceDown = Key('goal_setup_reference_down');
  static const referenceUp = Key('goal_setup_reference_up');
  static const referenceValue = Key('goal_setup_reference_value');
  static const start = Key('goal_setup_start');
  static const failed = Key('goal_setup_failed');
  static const openBody = Key('goal_setup_open_body');
}

/// What the setup works from once the facts allow it.
typedef _Basis = ({double trendKg, double heightCm, bool asks});

class GoalSetupScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<GoalSetupScreen> createState() => _GoalSetupScreenState();
}

class _GoalSetupScreenState extends ConsumerState<GoalSetupScreen> {
  bool? _pregnant;
  GoalPace _pace = GoalPace.standard;
  // Kept in kilograms: the tab keeps this page while the unit or the trend
  // changes elsewhere, and a number in the old unit would mean another weight.
  double? _chosenKg;
  var _saving = false;
  var _failed = false;
  var _alreadyActive = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final empty = AppPage(title: l10n.goalsSetupTitle, children: const []);
    if (!ref.watch(goalsEnabledProvider)) return empty;
    final facts = ref.watch(intakeFactsProvider);
    final active = ref.watch(activeGoalProvider);
    final asks = ref.watch(asksPregnancyProvider);
    if (facts.hasError || active.hasError || asks.hasError) {
      return AppPage(
        title: l10n.goalsSetupTitle,
        children: [BodyText(l10n.metricLoadError)],
      );
    }
    final current = facts.value;
    final asked = asks.value;
    if (current == null || !active.hasValue || asked == null) return empty;
    // Skipped while saving: the write moves the facts before the page leaves,
    // and a reload still holds the facts from before the change that caused it.
    final settled = !facts.isLoading && !active.isLoading;
    final judged = settled && !_saving && !_alreadyActive;
    if (judged && !_setsUp(current, hasGoal: active.value != null)) {
      return const GoalPickScreen(initial: GoalKind.loseFat);
    }
    final trendKg = current.trendKg;
    final heightCm = current.heightCm;
    if (trendKg == null || heightCm == null) return _weighFirst(l10n);
    final basis = (trendKg: trendKg, heightCm: heightCm, asks: asked);
    return AppPage(
      title: l10n.goalsSetupTitle,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _content(l10n, basis),
        ),
      ],
    );
  }

  bool _setsUp(IntakeFacts facts, {required bool hasGoal}) =>
      !hasGoal &&
      switch (pickStep(GoalKind.loseFat, facts)) {
        PickWeight(next: IntakeNext.setup) => true,
        _ => false,
      };

  Widget _weighFirst(AppLocalizations l10n) => AppPage(
    title: l10n.goalsSetupTitle,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MetricCard(child: BodyText(l10n.goalsSetupWeighFirst)),
          const SizedBox(height: 16),
          ActionButton(
            buttonKey: GoalSetupKeys.openBody,
            label: l10n.goalsSetupOpenBody,
            onPressed: () => context.go(AppPaths.body),
          ),
        ],
      ),
    ],
  );

  List<Widget> _content(AppLocalizations l10n, _Basis basis) {
    if (_alreadyActive) return [BodyText(l10n.goalsPickActive)];
    final pregnant = basis.asks ? _pregnant : false;
    final demo = ref.watch(demoModeProvider);
    return [
      if (basis.asks) ...[_pregnancyCard(l10n), const SizedBox(height: 16)],
      ...switch (pregnant) {
        null => [CaptionText(l10n.goalsSetupAnswerFirst)],
        true => [
          ActionButton(
            label: l10n.goalsPickContinue,
            onPressed: demo || _saving ? null : () => unawaited(_start(basis)),
          ),
          ..._demoNote(l10n, demo: demo),
          ..._failure(l10n),
        ],
        false => _plan(l10n, basis),
      },
    ];
  }

  Widget _pregnancyCard(AppLocalizations l10n) => MetricCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(l10n.goalsSetupPregnancyTitle),
        const SizedBox(height: 6),
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: l10n.goalsSetupPregnancyQuestion,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BodyText(l10n.goalsSetupPregnancyQuestion),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _Choice(
                      key: GoalSetupKeys.pregnancyNo,
                      title: l10n.goalsScreeningNo,
                      selected: _pregnant == false,
                      onTap: () => _answer(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Choice(
                      key: GoalSetupKeys.pregnancyYes,
                      title: l10n.goalsScreeningYes,
                      selected: _pregnant ?? false,
                      onTap: () => _answer(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        CaptionText(l10n.goalsSetupPregnancyWhy),
      ],
    ),
  );

  void _answer(bool pregnant) => setState(() {
    _pregnant = pregnant;
    _failed = false;
  });

  List<Widget> _plan(AppLocalizations l10n, _Basis basis) {
    final hidden = ref.watch(numbersHiddenProvider);
    final demo = ref.watch(demoModeProvider);
    final units = UnitFormat.of(context, ref);
    return [
      _paceCard(l10n, units, basis.trendKg, hidden: hidden),
      if (!hidden) ...[
        const SizedBox(height: 16),
        _referenceCard(l10n, units, basis),
      ],
      const SizedBox(height: 16),
      _blockCard(l10n, units, basis.trendKg, hidden: hidden),
      const SizedBox(height: 16),
      MetricCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Heading(l10n.goalsSetupFoodTitle),
            const SizedBox(height: 6),
            BodyText(l10n.goalsSetupFoodBody),
          ],
        ),
      ),
      const SizedBox(height: 16),
      ActionButton(
        buttonKey: GoalSetupKeys.start,
        label: l10n.goalsSetupStart,
        onPressed: demo || _saving ? null : () => unawaited(_start(basis)),
      ),
      ..._demoNote(l10n, demo: demo),
      ..._failure(l10n),
    ];
  }

  List<Widget> _demoNote(AppLocalizations l10n, {required bool demo}) => [
    if (demo) ...[
      const SizedBox(height: 8),
      CaptionText(l10n.goalsSetupDemo, textAlign: TextAlign.center),
    ],
  ];

  List<Widget> _failure(AppLocalizations l10n) => [
    if (_failed) ...[
      const SizedBox(height: 8),
      Semantics(
        liveRegion: true,
        child: CaptionText(
          l10n.goalsStartFailed,
          key: GoalSetupKeys.failed,
          textAlign: TextAlign.center,
        ),
      ),
    ],
  ];

  Widget _paceCard(
    AppLocalizations l10n,
    UnitFormat units,
    double trendKg, {
    required bool hidden,
  }) {
    String detail(GoalPace pace) {
      final percent = goalPacePercent(pace);
      final shown = _percent(units, percent);
      if (hidden) return l10n.goalsSetupPaceDetailHidden(shown);
      return l10n.goalsSetupPaceDetail(
        shown,
        units.bodyWeight(trendKg * percent / 100),
      );
    }

    Widget option(Key key, GoalPace pace, String title) => _Choice(
      key: key,
      title: title,
      lines: [detail(pace)],
      selected: _pace == pace,
      onTap: () => setState(() {
        _pace = pace;
        _failed = false;
      }),
    );

    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading(l10n.goalsSetupPaceTitle),
          const SizedBox(height: 6),
          Semantics(
            container: true,
            explicitChildNodes: true,
            label: l10n.goalsSetupPaceTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                option(
                  GoalSetupKeys.paceStandard,
                  GoalPace.standard,
                  l10n.goalsSetupPaceStandard,
                ),
                option(
                  GoalSetupKeys.paceGentle,
                  GoalPace.gentle,
                  l10n.goalsSetupPaceGentle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(AppLocalizations l10n, UnitFormat units, _Basis basis) {
    final bounds = referenceBounds(
      heightCm: basis.heightCm,
      trendKg: basis.trendKg,
    );
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading(l10n.goalsSetupReferenceTitle),
          const SizedBox(height: 6),
          CaptionText(l10n.goalsSetupReferenceAbout),
          const SizedBox(height: 12),
          ..._reference(l10n, units, bounds),
        ],
      ),
    );
  }

  List<Widget> _reference(
    AppLocalizations l10n,
    UnitFormat units,
    ReferenceBounds? bounds,
  ) {
    if (bounds == null) return [BodyText(l10n.goalsSetupReferenceNoRoom)];
    final system = units.system;
    final shown = shownReference(bounds, system);
    final kg = _chosenKg;
    if (kg == null) {
      return [
        SecondaryButton(
          buttonKey: GoalSetupKeys.referenceAdd,
          label: l10n.goalsSetupReferenceAdd,
          onPressed: () => setState(
            () => _chosenKg = referenceKgFor(shown.high, system, bounds),
          ),
        ),
      ];
    }
    final value = shownValueFor(kg, shown, system);
    final theme = Theme.of(context);
    final step = _weight(units, shown.step);
    void move(double by) => setState(() {
      final next = (value + by).clamp(shown.low, shown.high);
      _chosenKg = referenceKgFor(next, system, bounds);
    });
    return [
      Row(
        children: [
          _StepButton(
            buttonKey: GoalSetupKeys.referenceDown,
            tooltip: l10n.bodySheetDecrease(step),
            icon: Icons.remove_rounded,
            onPressed: value <= shown.low + 1e-9
                ? null
                : () => move(-shown.step),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _weight(units, value),
              key: GoalSetupKeys.referenceValue,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
          ),
          const SizedBox(width: 12),
          _StepButton(
            buttonKey: GoalSetupKeys.referenceUp,
            tooltip: l10n.bodySheetIncrease(step),
            icon: Icons.add_rounded,
            onPressed: value >= shown.high - 1e-9
                ? null
                : () => move(shown.step),
          ),
        ],
      ),
      const SizedBox(height: 8),
      CaptionText(l10n.goalsSetupReferenceFloor(_weight(units, shown.low))),
      const SizedBox(height: 8),
      SecondaryButton(
        buttonKey: GoalSetupKeys.referenceRemove,
        label: l10n.goalsSetupReferenceRemove,
        onPressed: () => setState(() => _chosenKg = null),
      ),
    ];
  }

  Widget _blockCard(
    AppLocalizations l10n,
    UnitFormat units,
    double trendKg, {
    required bool hidden,
  }) {
    final block = goalBlock(
      startKg: trendKg,
      percentPerWeek: goalPacePercent(_pace),
      start: ref.watch(currentDateProvider),
    );
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading(l10n.goalsSetupBlockTitle),
          const SizedBox(height: 6),
          BodyText(l10n.goalsSetupBlockLosing(block.weeks)),
          BodyText(l10n.goalsSetupBlockHolding(goalMaintenanceWeeks)),
          if (!hidden) ...[
            const SizedBox(height: 6),
            BodyText(
              l10n.goalsSetupBlockAmount(units.bodyWeight(block.blockKg)),
            ),
          ],
          const SizedBox(height: 10),
          CaptionText(
            l10n.goalsSetupBlockNote(
              goalBlockWeeks,
              _percent(units, goalBlockMaxLossPercent),
            ),
          ),
          const SizedBox(height: 6),
          CaptionText(l10n.goalsSetupBlockStarts),
        ],
      ),
    );
  }

  Future<void> _start(_Basis basis) async {
    // A second tap can land before the rebuild that disables the button.
    if (_saving) return;
    final pregnant = basis.asks ? _pregnant : null;
    if (basis.asks && pregnant == null) return;
    _saving = true;
    setState(() => _failed = false);
    try {
      final outcome = await ref
          .read(goalSetupControllerProvider)
          .start(
            pace: _pace,
            referenceKg: pregnant == true ? null : _referenceKg(basis),
            pregnantOrBreastfeeding: pregnant,
          );
      if (!mounted) return;
      _settle(outcome);
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _failed = true;
      });
    }
  }

  // Read at the tap: a reference picked before the numbers were hidden is
  // not sent once they are.
  double? _referenceKg(_Basis basis) {
    final kg = _chosenKg;
    if (kg == null || ref.read(numbersHiddenProvider)) return null;
    final bounds = referenceBounds(
      heightCm: basis.heightCm,
      trendKg: basis.trendKg,
    );
    if (bounds == null) return null;
    final system = UnitFormat.of(context, ref).system;
    final shown = shownValueFor(kg, shownReference(bounds, system), system);
    return referenceKgFor(shown, system, bounds);
  }

  void _settle(SetupOutcome outcome) {
    switch (outcome) {
      case SetupOutcome.started:
        context.go(AppTab.today.path);
      case SetupOutcome.pregnancy:
        context.go(AppPaths.goalsRefusedPregnancy);
      case SetupOutcome.alreadyActive:
        setState(() {
          _saving = false;
          _alreadyActive = true;
        });
      case SetupOutcome.notAllowed:
        setState(() {
          _saving = false;
          _failed = true;
        });
    }
  }

  String _weight(UnitFormat units, double shown) {
    final digits = units.system == UnitSystem.metric ? 1 : 0;
    return '${units.format.decimal(shown, digits: digits)} ${units.weightUnit}';
  }

  String _percent(UnitFormat units, double percent) {
    final tenths = percent * 10;
    final digits = switch (percent) {
      _ when percent == percent.roundToDouble() => 0,
      _ when tenths == tenths.roundToDouble() => 1,
      _ => 2,
    };
    return units.format.decimal(percent, digits: digits);
  }
}

class _Heading extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}

class _Choice extends StatelessWidget {
  const new({
    required this.title,
    required this.selected,
    required this.onTap,
    this.lines = const [],
    super.key,
  });

  final String title;
  final List<String> lines;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: [title, ...lines].join('. '),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? colors.textPrimary : colors.textLabel,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      for (final line in lines) ...[
                        const SizedBox(height: 2),
                        CaptionText(line),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const new({
    required this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final Key buttonKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: OutlinedButton(
      key: buttonKey,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.square(48),
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
      ),
      child: Icon(icon, semanticLabel: tooltip),
    ),
  );
}
