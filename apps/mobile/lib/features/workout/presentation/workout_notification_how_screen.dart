import 'package:flutter/material.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class WorkoutNotificationHowScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sections = [
      (
        l10n.workoutHowShows,
        [
          l10n.workoutHowFields,
          l10n.workoutHowZone,
          l10n.workoutHowPaused,
          l10n.workoutHowLock,
        ],
      ),
      (
        l10n.workoutHowSources,
        [l10n.workoutHowTime, l10n.workoutHowHeartRate, l10n.workoutHowGps],
      ),
      (l10n.workoutHowUpdates, [l10n.workoutHowCadence]),
      (l10n.workoutHowButtons, [l10n.workoutHowEnd]),
      (l10n.workoutHowAfter, [l10n.workoutHowResult, l10n.workoutHowClosed]),
      (l10n.workoutHowNever, [l10n.workoutHowScores, l10n.workoutHowSound]),
    ];
    return AppPage(
      title: l10n.workoutHowTitle,
      children: [
        BodyText(l10n.workoutHowLead),
        for (final (heading, lines) in sections) ...[
          SectionHeader(heading),
          for (final line in lines) ...[
            BodyText(line),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}
