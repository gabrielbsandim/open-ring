import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/widgets/placeholder_view.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class ActivityScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PlaceholderView(
      title: l10n.tabActivity,
      message: l10n.activityEmpty,
      icon: Icons.directions_walk_rounded,
      accent: AppColors.activity,
    );
  }
}
