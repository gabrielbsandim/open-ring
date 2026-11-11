import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/features/settings/application/about_providers.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

const _licenseName = 'MIT';

class AboutSection extends ConsumerWidget {
  const new({super.key});

  static const versionKey = Key('settings_about_version');
  static const privacyKey = Key('settings_about_privacy');
  static const githubKey = Key('settings_about_github');
  static const licenseKey = Key('settings_about_license');
  static final Uri repositoryUrl = Uri.parse(
    'https://github.com/gabrielbsandim/open-ring',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return TileGroup(
      children: [
        SettingsTile(
          key: versionKey,
          title: l10n.settingsVersion,
          value: ref.watch(appVersionProvider).value,
        ),
        SettingsTile(
          key: privacyKey,
          title: l10n.privacyTitle,
          chevron: true,
          onTap: () => unawaited(context.push(AppPaths.privacy)),
        ),
        SettingsTile(
          key: githubKey,
          title: l10n.settingsGitHub,
          detail: l10n.settingsGitHubDetail,
          trailing: Icon(
            Icons.open_in_new_rounded,
            size: 20,
            color: colors.textLabel,
          ),
          onTap: () => unawaited(
            ref.read(externalLinkOpenerProvider).open(repositoryUrl),
          ),
        ),
        SettingsTile(
          key: licenseKey,
          title: l10n.settingsLicense,
          value: _licenseName,
        ),
        const _MedicalNote(),
      ],
    );
  }
}

class _MedicalNote extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: colors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.of(context).settingsMedicalNote,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.textSecondary, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
