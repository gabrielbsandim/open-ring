import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

String weightDirection(AppLocalizations l10n, WeightRate rate) =>
    switch (rate) {
      WeightRateBuilding() => l10n.bodyDirectionNone,
      WeightRateReady(stable: true) => l10n.bodyDirectionStable,
      WeightRateReady(:final perWeek) when perWeek < 0 =>
        l10n.bodyDirectionDown,
      WeightRateReady() => l10n.bodyDirectionUp,
    };

class HiddenNumbersLabel extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.visibility_off_outlined,
          size: 18,
          color: AppColors.of(context).textLabel,
        ),
        const SizedBox(width: 6),
        Flexible(child: CaptionText(text)),
      ],
    );
  }
}
