import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/workout/application/location_access_provider.dart';
import 'package:open_ring/features/workout/domain/location_access.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/workout_labels.dart';
import 'package:open_ring/features/workout/presentation/workout_routes.dart';
import 'package:open_ring/features/workout/presentation/workout_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class LocationPermissionKeys {
  static const allow = Key('location_allow');
  static const start = Key('location_start');
  static const retry = Key('location_retry');
  static const settings = Key('location_settings');
  static const withoutGps = Key('location_without_gps');
  static const outcome = Key('location_outcome');
  static const checkFailed = Key('location_check_failed');
}

class LocationPermissionScreen extends ConsumerStatefulWidget {
  const new({required this.type, this.initialStatus, super.key});

  final WorkoutType type;
  final LocationAccessStatus? initialStatus;

  @override
  ConsumerState<LocationPermissionScreen> createState() =>
      _LocationPermissionScreenState();
}

class _LocationPermissionScreenState
    extends ConsumerState<LocationPermissionScreen> {
  late LocationAccessStatus? _status = widget.initialStatus;
  late final AppLifecycleListener _lifecycle;
  bool _busy = false;
  bool _checkFailed = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_recheck()));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    final platform = workoutHealthPlatform();
    final status = _status;
    return AppPage(
      title: l10n.workoutLocationTitle,
      subtitle: l10n.workoutLocationLead,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Icon(
              Icons.location_on_outlined,
              size: 32,
              color: colors.activity,
            ),
          ),
        ),
        const SizedBox(height: 12),
        BodyText(l10n.workoutLocationIntro),
        const SizedBox(height: 16),
        MetricCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Point(
                icon: Icons.route_rounded,
                accent: colors.activity,
                title: l10n.workoutLocationRouteTitle,
                body: l10n.workoutLocationRouteBody,
              ),
              Divider(height: 1, color: colors.surfaceBorder),
              _Point(
                icon: Icons.schedule_rounded,
                accent: colors.textSecondary,
                title: l10n.workoutLocationOnlyTitle,
                body: l10n.workoutLocationOnlyBody,
              ),
              Divider(height: 1, color: colors.surfaceBorder),
              _Point(
                icon: Icons.smartphone_rounded,
                accent: colors.textSecondary,
                title: l10n.workoutLocationLocalTitle,
                body: l10n.workoutLocationLocalBody(platform),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ..._decision(status, l10n, colors),
        if (status?.isGranted != true) ...[
          const SizedBox(height: 6),
          TextButton(
            key: LocationPermissionKeys.withoutGps,
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: _busy ? null : () => unawaited(_begin(gps: false)),
            child: Text(
              l10n.workoutWithoutGps,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _decision(
    LocationAccessStatus? status,
    AppLocalizations l10n,
    AppColors colors,
  ) {
    if (_checkFailed) {
      return [
        NoticeCard(
          key: LocationPermissionKeys.checkFailed,
          icon: Icons.error_outline_rounded,
          accent: colors.heart,
          title: l10n.workoutLocationCheckFailedTitle,
          body: l10n.workoutLocationCheckFailedBody,
        ),
        const SizedBox(height: 24),
        ActionButton(
          key: LocationPermissionKeys.retry,
          label: l10n.workoutLocationRetry,
          onPressed: _busy ? null : () => unawaited(_request()),
        ),
      ];
    }
    if (status == null) {
      return [
        CaptionText(l10n.workoutLocationAskHint),
        const SizedBox(height: 24),
        ActionButton(
          key: LocationPermissionKeys.allow,
          label: l10n.workoutLocationAllow,
          onPressed: _busy ? null : () => unawaited(_request()),
        ),
      ];
    }
    return [
      _Outcome(key: LocationPermissionKeys.outcome, status: status),
      const SizedBox(height: 24),
      ..._actions(status, l10n, colors),
    ];
  }

  List<Widget> _actions(
    LocationAccessStatus status,
    AppLocalizations l10n,
    AppColors colors,
  ) => switch (status) {
    LocationAccessStatus.granted => [
      AccentButton(
        key: LocationPermissionKeys.start,
        label: l10n.workoutLocationStart,
        icon: Icons.play_arrow_rounded,
        color: colors.activity,
        onPressed: _busy ? null : () => unawaited(_begin()),
      ),
    ],
    LocationAccessStatus.denied => [
      ActionButton(
        key: LocationPermissionKeys.retry,
        label: l10n.workoutLocationRetry,
        onPressed: _busy ? null : () => unawaited(_request()),
      ),
    ],
    LocationAccessStatus.deniedForever ||
    LocationAccessStatus.serviceDisabled => [
      ActionButton(
        key: LocationPermissionKeys.settings,
        label: l10n.workoutLocationOpenSettings,
        onPressed: () => unawaited(_openSettings(status)),
      ),
    ],
  };

  Future<void> _request() async {
    setState(() => _busy = true);
    final status = await _ask(ref.read(locationAccessProvider).request);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = status;
      _checkFailed = status == null;
    });
  }

  Future<void> _recheck() async {
    if (_status == null || _busy) return;
    final status = await _ask(ref.read(locationAccessProvider).status);
    if (!mounted || status == null) return;
    setState(() => _status = status);
  }

  static Future<LocationAccessStatus?> _ask(
    Future<LocationAccessStatus> Function() query,
  ) async {
    try {
      return await query();
    } on Object {
      return null;
    }
  }

  Future<void> _openSettings(LocationAccessStatus status) {
    final access = ref.read(locationAccessProvider);
    if (status == LocationAccessStatus.serviceDisabled) {
      return access.openLocationSettings();
    }
    return access.openAppSettings();
  }

  Future<void> _begin({bool gps = true}) async {
    setState(() => _busy = true);
    await beginWorkout(
      ref,
      GoRouter.of(context),
      widget.type,
      notice: workoutLocationNotice(MetricFormat.of(context).l10n),
      gps: gps,
    );
    if (!mounted) return;
    setState(() => _busy = false);
  }
}

class _Point extends StatelessWidget {
  const new({
    required this.icon,
    required this.accent,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.surfaceInner,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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

class _Outcome extends StatelessWidget {
  const new({required this.status, super.key});

  final LocationAccessStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    return switch (status) {
      LocationAccessStatus.granted => NoticeCard(
        icon: Icons.check_circle_outline_rounded,
        accent: colors.activity,
        border: colors.activity,
        title: l10n.workoutLocationGrantedTitle,
        body: l10n.workoutLocationGrantedBody,
      ),
      LocationAccessStatus.denied => NoticeCard(
        icon: Icons.location_disabled_rounded,
        accent: colors.stress,
        title: l10n.workoutLocationDeniedTitle,
        body: l10n.workoutLocationDeniedBody,
      ),
      LocationAccessStatus.deniedForever => NoticeCard(
        icon: Icons.block_rounded,
        accent: colors.heart,
        title: l10n.workoutLocationBlockedTitle,
        body: l10n.workoutLocationBlockedBody,
      ),
      LocationAccessStatus.serviceDisabled => NoticeCard(
        icon: Icons.location_off_outlined,
        accent: colors.stress,
        title: l10n.workoutLocationOffTitle,
        body: l10n.workoutLocationOffBody,
      ),
    };
  }
}
