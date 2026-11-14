import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/onboarding/domain/app_permissions.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class PermissionsKeys {
  static const continueAction = Key('permissions_continue');
  static const bluetoothHint = Key('permissions_bluetooth_hint');

  static Key allow(AppPermission permission) =>
      Key('permissions_allow_${permission.name}');

  static Key granted(AppPermission permission) =>
      Key('permissions_granted_${permission.name}');

  static Key notApplicable(AppPermission permission) =>
      Key('permissions_not_applicable_${permission.name}');
}

class PermissionsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () =>
          unawaited(ref.read(permissionsProvider.notifier).recheck()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final statuses = ref.watch(permissionsProvider).value ?? const {};
    final controller = ref.read(permissionsProvider.notifier);
    final bluetooth = statuses[AppPermission.bluetooth]?.isGranted ?? false;
    return OnboardingPage(
      step: 1,
      title: l10n.permissionsTitle,
      intro: l10n.permissionsIntro,
      children: [
        for (final permission in AppPermission.values) ...[
          _PermissionCard(
            permission: permission,
            status: statuses[permission] ?? PermissionStatus.denied,
            onAllow: () => unawaited(controller.request(permission)),
            onSettings: () => unawaited(controller.openSettings()),
          ),
          const SizedBox(height: cardGap),
        ],
        CaptionText(l10n.permissionsFootnote),
        const SizedBox(height: 20),
        if (!bluetooth) ...[
          InfoNote(
            key: PermissionsKeys.bluetoothHint,
            icon: Icons.info_outline_rounded,
            accent: colors.stress,
            text: l10n.permissionsBluetoothNeeded,
            live: true,
          ),
          const SizedBox(height: cardGap),
        ],
        PrimaryAction(
          key: PermissionsKeys.continueAction,
          label: l10n.onboardingContinue,
          onPressed: () => context.push(AppPaths.onboardingProfile),
        ),
      ],
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const new({
    required this.permission,
    required this.status,
    required this.onAllow,
    required this.onSettings,
  });

  final AppPermission permission;
  final PermissionStatus status;
  final VoidCallback onAllow;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final (icon, name, tag, tagColor, why) = switch (permission) {
      AppPermission.bluetooth => (
        Icons.bluetooth_rounded,
        l10n.permissionsBluetoothName,
        l10n.permissionsForRing,
        colors.textPrimary,
        l10n.permissionsBluetoothWhy,
      ),
      AppPermission.notifications => (
        Icons.notifications_none_rounded,
        l10n.permissionsNotificationsName,
        l10n.permissionsOptional,
        colors.textLabel,
        l10n.permissionsNotificationsWhy,
      ),
      AppPermission.backgroundExecution => (
        Icons.sync_rounded,
        l10n.permissionsBackgroundName,
        l10n.permissionsRecommended,
        colors.activity,
        l10n.permissionsBackgroundWhy,
      ),
      AppPermission.location => (
        Icons.location_on_outlined,
        l10n.permissionsLocationName,
        l10n.permissionsOptional,
        colors.textLabel,
        l10n.permissionsLocationWhy,
      ),
    };
    final granted = status.isGranted;
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: granted ? colors.activity : colors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    CaptionText(tag, color: tagColor),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          BodyText(why),
          const SizedBox(height: 12),
          switch (status) {
            PermissionStatus.granted => _StatusLine(
              key: PermissionsKeys.granted(permission),
              icon: Icons.check_rounded,
              color: colors.activity,
              label: l10n.permissionsAllowed,
            ),
            PermissionStatus.notApplicable => _StatusLine(
              key: PermissionsKeys.notApplicable(permission),
              icon: Icons.info_outline_rounded,
              color: colors.textLabel,
              label: l10n.permissionsNotApplicable,
            ),
            PermissionStatus.denied => SecondaryButton(
              key: PermissionsKeys.allow(permission),
              label: l10n.permissionsAllow,
              onPressed: onAllow,
            ),
            PermissionStatus.permanentlyDenied => SecondaryButton(
              key: PermissionsKeys.allow(permission),
              label: l10n.permissionsOpenSettings,
              onPressed: onSettings,
            ),
          },
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const new({
    required this.icon,
    required this.color,
    required this.label,
    super.key,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
