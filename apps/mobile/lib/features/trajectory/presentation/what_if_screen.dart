import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/trajectory/application/levers_providers.dart';
import 'package:open_ring/features/trajectory/application/steps_what_if_providers.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_states.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class WhatIfKeys {
  static const step1000 = Key('what_if_step_1000');
  static const step2000 = Key('what_if_step_2000');
  static const step3000 = Key('what_if_step_3000');
  static const weight = Key('what_if_weight');
  static const cohort = Key('what_if_cohort');
  static const noScenario = Key('what_if_no_scenario');
  static const noSteps = Key('what_if_no_steps');
}

const Map<int, Key> _steps = {
  1000: WhatIfKeys.step1000,
  2000: WhatIfKeys.step2000,
  3000: WhatIfKeys.step3000,
};

class WhatIfScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<WhatIfScreen> createState() => _WhatIfScreenState();
}

class _WhatIfScreenState extends ConsumerState<WhatIfScreen> {
  int _extra = 2000;
  WhatIfView? _shown;

  @override
  Widget build(BuildContext context) {
    final units = UnitFormat.of(context, ref);
    final l10n = units.l10n;
    return AppPage(
      title: l10n.trajectoryWhatIfTitle,
      children: [
        CaptionText(l10n.trajectoryWhatIfLead),
        const SizedBox(height: 16),
        ..._content(units, ref.watch(whatIfProvider(_extra))),
      ],
    );
  }

  List<Widget> _content(UnitFormat units, AsyncValue<WhatIfView> view) {
    final l10n = units.l10n;
    final error = TrajectoryErrorCard(
      onRetry: () {
        ref
          ..invalidate(weighInsProvider)
          ..invalidate(weightSummaryProvider)
          ..invalidate(trajectoryViewProvider)
          ..invalidate(leversProvider)
          ..invalidate(whatIfProvider);
      },
    );
    if (view.hasError) return [error];
    // A new step size loads a new family entry; keep the last one so the page
    // does not collapse and jump while it reads.
    final shown = view.value ?? _shown;
    if (shown == null) return const [];
    _shown = shown;
    return switch (shown) {
      WhatIfOff() => [BodyText(l10n.trajectoryPlaceholder)],
      WhatIfRefused(:final reason) => [TrajectoryRefusedCard(reason: reason)],
      WhatIfError() => [error],
      WhatIfNoSteps(:final validDays) => [
        MetricCard(
          key: WhatIfKeys.noSteps,
          child: BodyText(
            l10n.trajectoryWhatIfNoSteps(units.format.integer(validDays)),
          ),
        ),
      ],
      final WhatIfReady ready => [
        _stepsCard(units, ready),
        const SizedBox(height: 12),
        _weightCard(units, ready.weight),
        const SizedBox(height: 12),
        _cohortCard(units, ready),
        const SizedBox(height: 16),
        CaptionText(l10n.trajectoryWhatIfFoot),
      ],
    };
  }

  Widget _stepsCard(UnitFormat units, WhatIfReady ready) {
    final l10n = units.l10n;
    final format = units.format;
    return _Card(
      title: l10n.trajectoryWhatIfStepsTitle,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final MapEntry(key: steps, value: key) in _steps.entries)
              ChoiceChip(
                key: key,
                label: Text(l10n.trajectoryWhatIfStep(format.integer(steps))),
                selected: steps == _extra,
                onSelected: (_) => setState(() => _extra = steps),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          l10n.trajectoryWhatIfFromTo(
            format.integer(ready.typical),
            format.integer(ready.toSteps),
          ),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        CaptionText(
          l10n.trajectoryWhatIfTypical(format.integer(ready.typical)),
        ),
      ],
    );
  }

  Widget _weightCard(UnitFormat units, StepsWhatIf? weight) {
    final l10n = units.l10n;
    final eatBack = CaptionText(l10n.trajectoryWhatIfEatBack);
    if (weight == null) {
      return _Card(
        title: l10n.trajectoryWhatIfWeightTitle,
        children: [
          BodyText(key: WhatIfKeys.noScenario, l10n.trajectoryWhatIfNoScenario),
          const SizedBox(height: 10),
          eatBack,
        ],
      );
    }
    String amount(double kilograms) =>
        units.format.decimal(units.bodyWeightIn(kilograms), digits: 2);
    final distance = units.distanceText(weight.kilometers * metersPerKilometre);
    final hidden = ref.watch(numbersHiddenProvider);
    return _Card(
      title: l10n.trajectoryWhatIfWeightTitle,
      children: [
        _Row(
          key: WhatIfKeys.weight,
          caption: l10n.trajectoryWhatIfIn12,
          value: hidden
              ? l10n.trajectoryWhatIfLessWords
              : l10n.trajectoryWhatIfLess(
                  amount(weight.kgLess12),
                  units.weightUnit,
                ),
          why: hidden
              ? l10n.trajectoryWhatIfHiddenWhy(distance)
              : l10n.trajectoryWhatIfWeightWhy(
                  distance,
                  amount(weight.kgLess4),
                  units.weightUnit,
                ),
        ),
        const SizedBox(height: 10),
        eatBack,
      ],
    );
  }

  Widget _cohortCard(UnitFormat units, WhatIfReady ready) {
    final l10n = units.l10n;
    final format = units.format;
    final top = paluchAnchors.last.steps;
    final groups = l10n.trajectoryWhatIfGroups(
      format.integer(math.min(ready.toSteps, top)),
      format.integer(ready.typical),
    );
    final clamped = l10n.trajectoryWhatIfClamped(format.integer(top));
    // At or above the top group there is no study group to compare against.
    final why = switch (ready) {
      WhatIfReady(:final typical) when typical >= top => clamped,
      WhatIfReady(clamped: true) => '$groups $clamped',
      _ => groups,
    };
    return _Card(
      title: l10n.trajectoryWhatIfStudiesTitle,
      children: [
        _Row(
          key: WhatIfKeys.cohort,
          caption: l10n.trajectoryWhatIfMortality,
          value: _words(l10n, ready.words),
          why: why,
        ),
        const SizedBox(height: 10),
        BodyText(l10n.trajectoryWhatIfCohortNote),
      ],
    );
  }

  String _words(AppLocalizations l10n, CohortWords words) => switch (words) {
    CohortWords.aboutTheSame => l10n.trajectoryWhatIfWordsSame,
    CohortWords.slightlyLower => l10n.trajectoryWhatIfWordsSlightly,
    CohortWords.fifthToQuarterLower => l10n.trajectoryWhatIfWordsFifth,
    CohortWords.muchLower => l10n.trajectoryWhatIfWordsMuch,
  };
}

class _Card extends StatelessWidget {
  const new({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const new({
    required this.caption,
    required this.value,
    required this.why,
    super.key,
  });

  final String caption;
  final String value;
  final String why;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CaptionText(caption),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          BodyText(why),
        ],
      ),
    );
  }
}
