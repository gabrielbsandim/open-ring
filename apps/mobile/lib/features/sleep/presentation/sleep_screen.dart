import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/placeholder_view.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class SleepScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PlaceholderView(
      title: l10n.tabSleep,
      message: l10n.sleepEmpty,
      icon: Icons.bedtime_rounded,
      accent: AppColors.of(context).sleep,
    );
  }
}
