import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/goals/application/goal_intake_providers.dart';
import 'package:open_ring/features/goals/application/goals_gate.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';
import 'package:open_ring/features/goals/presentation/goal_pick_screen.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class GoalScreeningKeys {
  static Key no(int index) => Key('goal_screening_no_$index');
  static Key yes(int index) => Key('goal_screening_yes_$index');
  static const continueButton = Key('goal_screening_continue');
  static const back = Key('goal_screening_back');
  static const answered = Key('goal_screening_answered');
  static const failed = Key('goal_screening_failed');
}

class GoalScreeningScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<GoalScreeningScreen> createState() =>
      _GoalScreeningScreenState();
}

class _GoalScreeningScreenState extends ConsumerState<GoalScreeningScreen> {
  final _answers = List<bool?>.filled(goalScreeningQuestions, null);
  var _submitting = false;
  var _failed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final empty = AppPage(title: l10n.goalsScreeningTitle, children: const []);
    if (!ref.watch(goalsEnabledProvider)) return empty;
    final instead = _submitting ? null : _instead(l10n, empty);
    if (instead != null) return instead;
    final done = _answers.nonNulls.length;
    final complete = done == goalScreeningQuestions;
    return AppPage(
      title: l10n.goalsScreeningTitle,
      subtitle: l10n.goalsScreeningLead,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BodyText(l10n.goalsScreeningNotDiagnosis),
            const SizedBox(height: 16),
            MetricCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, question) in _questions(l10n).indexed) ...[
                    if (index > 0) const SizedBox(height: 18),
                    _Question(
                      index: index,
                      label: l10n.goalsScreeningQuestionLabel(index + 1),
                      text: question,
                      answer: _answers[index],
                      no: l10n.goalsScreeningNo,
                      yes: l10n.goalsScreeningYes,
                      onAnswer: (yes) => setState(() {
                        _answers[index] = yes;
                        _failed = false;
                      }),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _Stays(
              title: l10n.goalsScreeningStaysTitle,
              text: l10n.goalsScreeningStays,
            ),
            const SizedBox(height: 16),
            ActionButton(
              buttonKey: GoalScreeningKeys.continueButton,
              label: l10n.goalsPickContinue,
              onPressed: complete && !_submitting
                  ? () => unawaited(_submit())
                  : null,
            ),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: CaptionText(
                l10n.goalsScreeningAnswered(done),
                key: GoalScreeningKeys.answered,
                textAlign: TextAlign.center,
              ),
            ),
            if (_failed) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: CaptionText(
                  l10n.goalsScreeningFailed,
                  key: GoalScreeningKeys.failed,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 16),
            CaptionText(l10n.goalsScreeningSkip),
            const SizedBox(height: 10),
            SecondaryButton(
              buttonKey: GoalScreeningKeys.back,
              label: l10n.goalsRefusalSeeNoWeight,
              onPressed: () =>
                  context.go(AppPaths.goalsPickWith(GoalKind.getFitter)),
            ),
          ],
        ),
      ],
    );
  }

  // Skipped during a submit: the write flips the facts before the screen
  // leaves, and the check would swap in the picker under the person.
  Widget? _instead(AppLocalizations l10n, Widget empty) {
    final facts = ref.watch(intakeFactsProvider);
    if (facts.hasError) {
      return AppPage(
        title: l10n.goalsScreeningTitle,
        children: [BodyText(l10n.metricLoadError)],
      );
    }
    final current = facts.value;
    if (current == null) return empty;
    if (_asks(current)) return null;
    return const GoalPickScreen(initial: GoalKind.loseFat);
  }

  bool _asks(IntakeFacts facts) => switch (pickStep(GoalKind.loseFat, facts)) {
    PickWeight(next: IntakeNext.screening) => true,
    _ => false,
  };

  List<String> _questions(AppLocalizations l10n) => [
    l10n.goalsScreeningQ1,
    l10n.goalsScreeningQ2,
    if (ref.watch(numbersHiddenProvider))
      l10n.goalsScreeningQ3Hidden
    else
      l10n.goalsScreeningQ3(
        UnitFormat.of(context, ref).weight(goalScreeningLossKg),
      ),
    l10n.goalsScreeningQ4,
    l10n.goalsScreeningQ5,
  ];

  Future<void> _submit() async {
    // A second tap can land before the rebuild that disables the button.
    if (_submitting) return;
    final answers = _answers.nonNulls.toList();
    if (answers.length != goalScreeningQuestions) return;
    _submitting = true;
    setState(() => _failed = false);
    try {
      final soft = await ref.read(screeningControllerProvider).submit(answers);
      if (!mounted) return;
      context.go(
        soft
            ? AppPaths.goalsRefusedFor(IntakeBlock.softMode)
            : AppTab.today.path,
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _failed = true;
      });
    }
  }
}

class _Question extends StatelessWidget {
  const new({
    required this.index,
    required this.label,
    required this.text,
    required this.answer,
    required this.no,
    required this.yes,
    required this.onAnswer,
  });

  final int index;
  final String label;
  final String text;
  final bool? answer;
  final String no;
  final String yes;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: label,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BodyText(text),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _Answer(
                key: GoalScreeningKeys.no(index),
                label: no,
                selected: answer == false,
                onTap: () => onAnswer(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Answer(
                key: GoalScreeningKeys.yes(index),
                label: yes,
                selected: answer ?? false,
                onTap: () => onAnswer(true),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _Answer extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
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
      label: label,
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
                Flexible(
                  child: Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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

class _Stays extends StatelessWidget {
  const new({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(
            Icons.phone_android_outlined,
            size: 20,
            color: colors.textLabel,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [CaptionText(title), CaptionText(text)],
          ),
        ),
      ],
    );
  }
}
