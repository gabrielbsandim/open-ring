import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/health_sync/application/health_status_providers.dart';
import 'package:open_ring/features/health_sync/application/health_sync_controller.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class HealthPermissionKeys {
  static const connect = Key('health_connect');
  static const notNow = Key('health_not_now');
  static const continueAction = Key('health_continue');
  static const connected = Key('health_connected');
  static const declined = Key('health_declined');
}

enum HealthConnectPhase { idle, requesting, connected, declined }

class HealthPermissionScreen extends ConsumerStatefulWidget {
  const new({this.initialPhase = HealthConnectPhase.idle, super.key});

  final HealthConnectPhase initialPhase;

  @override
  ConsumerState<HealthPermissionScreen> createState() =>
      _HealthPermissionScreenState();
}

class _HealthPermissionScreenState
    extends ConsumerState<HealthPermissionScreen> {
  late HealthConnectPhase _phase = widget.initialPhase;

  @override
  void initState() {
    super.initState();
    if (_phase != HealthConnectPhase.idle) return;
    unawaited(_showGranted());
  }

  // After a reinstall the platform may still hold every write permission.
  Future<void> _showGranted() async {
    final granted = await _alreadyGranted();
    if (!mounted || !granted) return;
    if (_phase != HealthConnectPhase.idle) return;
    setState(() => _phase = HealthConnectPhase.connected);
  }

  Future<bool> _alreadyGranted() async {
    try {
      final access = await ref.read(healthAccessProvider.future);
      return access.values.every((value) => value == HealthAccess.granted);
    } on Object {
      return false;
    }
  }

  Future<void> _connect() async {
    setState(() => _phase = HealthConnectPhase.requesting);
    final granted = await _request();
    if (!mounted) return;
    setState(
      () => _phase = granted
          ? HealthConnectPhase.connected
          : HealthConnectPhase.declined,
    );
  }

  Future<bool> _request() async {
    try {
      return await ref.read(healthSyncProvider.notifier).requestAccess();
    } on Object {
      return false;
    }
  }

  void _next() => unawaited(context.push(PairFlow.onboarding.path));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final platform = healthPlatformName();
    final asking =
        _phase == HealthConnectPhase.idle ||
        _phase == HealthConnectPhase.requesting;
    return OnboardingPage(
      step: 3,
      title: l10n.healthTitle(platform),
      intro: l10n.healthIntro(platform),
      children: [
        const _WriteList(),
        const SizedBox(height: cardGap),
        InfoNote(
          icon: Icons.shield_outlined,
          lead: l10n.healthWriteDefaultLead,
          text: [
            l10n.healthWriteDefault,
            l10n.healthNoStress(platform),
            l10n.healthRevoke(platform),
          ].join(' '),
        ),
        const SizedBox(height: cardGap),
        MetricCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccentTitle(title: l10n.healthReadTitle, accent: colors.sleep),
              const SizedBox(height: 6),
              BodyText(l10n.healthReadBody),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_phase == HealthConnectPhase.connected) ...[
          InfoNote(
            key: HealthPermissionKeys.connected,
            icon: Icons.check_circle_outline_rounded,
            accent: colors.activity,
            lead: l10n.healthConnectedLead(platform),
            text: l10n.healthConnected,
            live: true,
          ),
          const SizedBox(height: cardGap),
        ],
        if (_phase == HealthConnectPhase.declined) ...[
          InfoNote(
            key: HealthPermissionKeys.declined,
            icon: Icons.info_outline_rounded,
            accent: colors.stress,
            text: l10n.healthDeclined(platform),
            live: true,
          ),
          const SizedBox(height: cardGap),
        ],
        if (asking) ...[
          PrimaryAction(
            key: HealthPermissionKeys.connect,
            label: l10n.healthConnect(platform),
            onPressed: _phase == HealthConnectPhase.idle
                ? () => unawaited(_connect())
                : null,
          ),
          const SizedBox(height: 4),
          QuietAction(
            key: HealthPermissionKeys.notNow,
            label: l10n.healthNotNow,
            onPressed: _next,
          ),
          CaptionText(l10n.healthSkipNote, textAlign: TextAlign.center),
        ],
        if (!asking)
          PrimaryAction(
            key: HealthPermissionKeys.continueAction,
            label: l10n.onboardingContinue,
            onPressed: _next,
          ),
      ],
    );
  }
}

class _WriteList extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final items = [
      (l10n.healthWriteSteps, l10n.healthWriteStepsDetail, colors.activity),
      (
        l10n.healthWriteDistance,
        l10n.healthWriteDistanceDetail,
        colors.activity,
      ),
      (l10n.healthWriteEnergy, l10n.healthWriteEnergyDetail, colors.activity),
      (
        l10n.healthWriteHeartRate,
        l10n.healthWriteHeartRateDetail,
        colors.heart,
      ),
      (l10n.healthWriteSleep, l10n.healthWriteSleepDetail, colors.sleep),
      (
        l10n.healthWriteWorkouts,
        l10n.healthWriteWorkoutsDetail,
        colors.activity,
      ),
      (l10n.healthWriteRoutes, l10n.healthWriteRoutesDetail, colors.activity),
      (l10n.healthWriteSpo2, l10n.healthWriteSpo2Detail, colors.oxygen),
      (l10n.healthWriteHrv, l10n.healthWriteHrvDetail, colors.heart),
    ];
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.healthWritesTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              CaptionText(l10n.healthWritesCount(items.length)),
            ],
          ),
          const SizedBox(height: 8),
          for (final (name, detail, accent) in items)
            MergeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                          CaptionText(detail),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
