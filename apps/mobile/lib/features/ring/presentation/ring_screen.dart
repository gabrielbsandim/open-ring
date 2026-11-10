import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/widgets/placeholder_view.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class RingScreen extends StatelessWidget {
  const new({super.key});

  static const settingsKey = Key('ring_settings');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PlaceholderView(
      title: l10n.tabRing,
      message: l10n.ringEmpty,
      icon: Icons.radio_button_unchecked_rounded,
      accent: AppColors.oxygen,
      actions: [
        IconButton(
          key: settingsKey,
          tooltip: l10n.settingsTitle,
          icon: const Icon(Icons.settings_rounded),
          onPressed: () => context.go(AppPaths.settings),
        ),
      ],
    );
  }
}
