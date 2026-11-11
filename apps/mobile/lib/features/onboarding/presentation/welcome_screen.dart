import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/open_ring_logo.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class WelcomeScreen extends StatelessWidget {
  const new({super.key});

  static const startKey = Key('welcome_start');
  static const demoKey = Key('welcome_demo');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final platform = healthPlatformName();
    return OnboardingPage(
      label: l10n.appTitle,
      hero: const Center(child: OpenRingLogo(size: 120)),
      title: l10n.welcomeTitle,
      intro: l10n.welcomeIntro(platform),
      children: [
        MetricCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              _Point(
                icon: Icons.smartphone_rounded,
                title: l10n.welcomeLocalTitle,
                body: l10n.welcomeLocalBody,
              ),
              const Divider(height: 1),
              _Point(
                icon: Icons.sync_rounded,
                title: l10n.welcomeSyncTitle,
                body: l10n.welcomeSyncBody(platform),
              ),
              const Divider(height: 1),
              _Point(
                icon: Icons.bar_chart_rounded,
                title: l10n.welcomeHonestTitle,
                body: l10n.welcomeHonestBody,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        PrimaryAction(
          key: startKey,
          label: l10n.welcomeStart,
          onPressed: () => context.push(AppPaths.onboardingPermissions),
        ),
        const SizedBox(height: 4),
        const _ExploreDemo(),
        const SizedBox(height: 6),
        CaptionText(l10n.welcomeFootnote, textAlign: TextAlign.center),
      ],
    );
  }
}

class _ExploreDemo extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_ExploreDemo> createState() => _ExploreDemoState();
}

class _ExploreDemoState extends ConsumerState<_ExploreDemo> {
  bool _loading = false;

  Future<void> _explore() async {
    setState(() => _loading = true);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final entered = await ref.read(demoModeProvider.notifier).enter();
    if (!mounted) return;
    setState(() => _loading = false);
    if (!entered) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.welcomeDemoFailed)));
      return;
    }
    router.go(AppTab.today.path);
  }

  @override
  Widget build(BuildContext context) {
    return QuietAction(
      key: WelcomeScreen.demoKey,
      label: AppLocalizations.of(context).welcomeExploreDemo,
      onPressed: _loading ? null : () => unawaited(_explore()),
    );
  }
}

class _Point extends StatelessWidget {
  const new({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.surfaceInner,
                border: Border.all(color: colors.strongBorder),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: colors.textSecondary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  CaptionText(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
