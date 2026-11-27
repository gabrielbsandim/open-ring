import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class WidgetsHowScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppPage(
      title: l10n.widgetHowTitle,
      children: [
        MetricCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(context, l10n.widgetHowShowHeading),
              const SizedBox(height: 8),
              BodyText(l10n.widgetHowShowBody),
            ],
          ),
        ),
        const SizedBox(height: cardGap),
        MetricCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(context, l10n.widgetHowWhenHeading),
              const SizedBox(height: 8),
              _BulletRow(
                icon: Icons.sync_rounded,
                text: l10n.widgetHowWhenSync,
              ),
              const SizedBox(height: 8),
              _BulletRow(
                icon: Icons.schedule_rounded,
                text: l10n.widgetHowWhenRefresh,
              ),
              const SizedBox(height: 8),
              _BulletRow(
                icon: Icons.info_outline_rounded,
                text: l10n.widgetHowWhenMidnight,
              ),
            ],
          ),
        ),
        const SizedBox(height: cardGap),
        MetricCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(context, l10n.widgetHowModulesHeading),
              const SizedBox(height: 8),
              BodyText(l10n.widgetHowModulesBody),
              const SizedBox(height: 8),
              BodyText(l10n.widgetHowModulesHidden),
            ],
          ),
        ),
        const SizedBox(height: cardGap),
        MetricCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(context, l10n.widgetHowNeverHeading),
              const SizedBox(height: 8),
              _BulletRow(
                icon: Icons.bluetooth_disabled_rounded,
                text: l10n.widgetHowNeverBluetooth,
              ),
              const SizedBox(height: 8),
              _BulletRow(
                icon: Icons.lock_outline_rounded,
                text: l10n.widgetHowNeverLock,
              ),
              const SizedBox(height: 8),
              _BulletRow(
                icon: Icons.auto_awesome_outlined,
                text: l10n.widgetHowNeverAi,
              ),
              const SizedBox(height: 8),
              _BulletRow(
                icon: Icons.restaurant_outlined,
                text: l10n.widgetHowNeverFood,
              ),
              const SizedBox(height: 8),
              _BulletRow(
                icon: Icons.visibility_off_outlined,
                text: l10n.widgetHowNeverGoals,
              ),
            ],
          ),
        ),
        const SizedBox(height: cardGap),
        MetricCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(context, l10n.widgetHowDataHeading),
              const SizedBox(height: 8),
              BodyText(l10n.widgetHowDataBody),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Semantics(
    header: true,
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}

class _BulletRow extends StatelessWidget {
  const new({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 18, color: colors.textLabel),
        ),
        const SizedBox(width: 10),
        Expanded(child: BodyText(text)),
      ],
    );
  }
}
