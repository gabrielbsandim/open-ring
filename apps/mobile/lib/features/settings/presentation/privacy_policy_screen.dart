import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/settings/application/about_providers.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class PrivacyPolicyScreen extends ConsumerWidget {
  const new({super.key});

  static const closeKey = Key('privacy_policy_close');
  static const fullPolicyKey = Key('privacy_policy_full');
  static final Uri fullPolicyUrl = Uri.parse(
    'https://github.com/gabrielbsandim/open-ring/blob/main/docs/privacy-policy.md',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final canPop = Navigator.canPop(context);
    return AppPage(
      title: l10n.privacyTitle,
      subtitle: l10n.privacyEffective,
      actions: [
        if (!canPop)
          IconButton(
            key: closeKey,
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            icon: const Icon(Icons.close_rounded),
            onPressed: () => context.go(AppTab.today.path),
          ),
      ],
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.privacyShortHeading,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        for (final line in [
          l10n.privacyShortNoAccount,
          l10n.privacyShortStored,
          l10n.privacyShortInternet,
          l10n.privacyShortLeaves,
        ]) ...[BodyText(line), const SizedBox(height: 8)],
        SectionHeader(l10n.privacyStoresHeading),
        TileGroup(
          children: [
            for (final (data, why) in [
              (l10n.privacyStoresRing, l10n.privacyStoresRingWhy),
              (l10n.privacyStoresRingData, l10n.privacyStoresRingDataWhy),
              (l10n.privacyStoresWorkouts, l10n.privacyStoresWorkoutsWhy),
              (l10n.privacyStoresRoutes, l10n.privacyStoresRoutesWhy),
              (l10n.privacyStoresProfile, l10n.privacyStoresProfileWhy),
              (l10n.privacyStoresOtherApps, l10n.privacyStoresOtherAppsWhy),
              (l10n.privacyStoresSettings, l10n.privacyStoresSettingsWhy),
              (l10n.privacyStoresSummary, l10n.privacyStoresSummaryWhy),
            ])
              SettingsTile(title: data, detail: why),
          ],
        ),
        SectionHeader(l10n.privacyHealthHeading),
        TileGroup(
          children: [
            SettingsTile(
              title: l10n.privacyHealthWrites,
              detail: l10n.privacyHealthWritesWhy,
            ),
            SettingsTile(
              title: l10n.privacyHealthReads,
              detail: l10n.privacyHealthReadsWhy,
            ),
          ],
        ),
        const SizedBox(height: 8),
        BodyText(l10n.privacyHealthShare),
        SectionHeader(l10n.privacyDeleteHeading),
        for (final line in [
          l10n.privacyDeleteKept,
          l10n.privacyDeleteWorkout,
          l10n.privacyDeleteAll,
          l10n.privacyDeleteHealthConnect,
          l10n.privacyRevoke,
        ]) ...[BodyText(line), const SizedBox(height: 8)],
        const SizedBox(height: cardGap),
        TileGroup(
          children: [
            SettingsTile(
              key: fullPolicyKey,
              title: l10n.privacyFullPolicy,
              detail: l10n.privacyFullPolicyDetail,
              trailing: Icon(
                Icons.open_in_new_rounded,
                size: 20,
                color: colors.textLabel,
              ),
              onTap: () => unawaited(
                ref.read(externalLinkOpenerProvider).open(fullPolicyUrl),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
