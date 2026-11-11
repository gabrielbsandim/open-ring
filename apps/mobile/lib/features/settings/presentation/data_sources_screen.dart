import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/core/widgets/text_scale.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/health_sync/application/health_status_providers.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/features/settings/presentation/source_labels.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

enum MetricOrigin { ring, phone, computed }

enum SourcedMetric {
  steps(MetricOrigin.ring),
  energy(MetricOrigin.ring),
  heartRate(MetricOrigin.ring),
  hrv(MetricOrigin.ring),
  spo2(MetricOrigin.ring),
  stress(MetricOrigin.ring),
  sleep(MetricOrigin.ring),
  battery(MetricOrigin.ring),
  workouts(MetricOrigin.phone),
  route(MetricOrigin.phone),
  scores(MetricOrigin.computed);

  new(this.origin);

  final MetricOrigin origin;
}

abstract final class DataSourcesKeys {
  static const ring = Key('sources_ring');
  static const readSleep = Key('sources_read_sleep');
  static const readWorkouts = Key('sources_read_workouts');
  static const openHealth = Key('sources_open_health');
  static const priority = Key('sources_priority');
  static const workoutPriority = Key('sources_priority_workout');

  static Key metric(SourcedMetric metric) => Key('sources_${metric.name}');

  static Key read(HealthRecordKind kind) => switch (kind) {
    HealthRecordKind.workout => readWorkouts,
    _ => readSleep,
  };

  static Key priorityOf(HealthRecordKind kind) => switch (kind) {
    HealthRecordKind.workout => workoutPriority,
    _ => priority,
  };

  static Key app(String source) => Key('sources_app_$source');

  static Key rank(String source, {HealthRecordKind kind = _sleep}) =>
      Key('sources_rank_${_scope(kind)}$source');

  static Key moveUp(String source, {HealthRecordKind kind = _sleep}) =>
      Key('sources_up_${_scope(kind)}$source');

  static Key moveDown(String source, {HealthRecordKind kind = _sleep}) =>
      Key('sources_down_${_scope(kind)}$source');

  static Key drag(String source, {HealthRecordKind kind = _sleep}) =>
      Key('sources_drag_${_scope(kind)}$source');

  static const HealthRecordKind _sleep = HealthRecordKind.sleep;

  static String _scope(HealthRecordKind kind) =>
      kind == _sleep ? '' : '${kind.name}_';
}

class DataSourcesScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final platform = healthPlatformName();
    final sleep = ref.watch(healthReadProvider);
    final workouts = ref.watch(workoutReadProvider);
    return AppPage(
      title: l10n.sourcesTitle,
      subtitle: l10n.sourcesIntro(platform),
      children: [
        AsyncBody(
          value: ref.watch(ringStatusProvider),
          builder: (ring) => _RingCard(ring: ring),
        ),
        SectionHeader(l10n.sourcesPerMetric),
        TileGroup(
          children: [
            for (final metric in SourcedMetric.values)
              SettingsTile(
                key: DataSourcesKeys.metric(metric),
                leading: AccentDot(color: metric.accent(colors)),
                title: metric.label(l10n),
                detail: metric.detail(l10n),
                value: metric.origin.label(l10n),
                valueColor: colors.textSecondary,
              ),
          ],
        ),
        SectionHeader(l10n.sourcesOtherTitle(platform)),
        AsyncBody(
          value: sleep,
          builder: (sleepView) => AsyncBody(
            value: workouts,
            builder: (workoutView) => _OtherApps(
              sleep: sleepView,
              workouts: workoutView,
              platform: platform,
            ),
          ),
        ),
        SectionHeader(l10n.sourcesPriorityTitle),
        CaptionText(l10n.sourcesPriorityBody),
        const SizedBox(height: 8),
        AsyncBody(
          value: sleep,
          builder: (view) =>
              _PriorityCard(kind: HealthRecordKind.sleep, view: view),
        ),
        const SizedBox(height: cardGap),
        AsyncBody(
          value: workouts,
          builder: (view) =>
              _PriorityCard(kind: HealthRecordKind.workout, view: view),
        ),
        SectionHeader(l10n.sourcesRulesTitle),
        NumberedTip(number: 1, body: l10n.healthWriteDefault),
        NumberedTip(number: 2, body: l10n.sourcesRulePriority),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 40),
          child: CaptionText(l10n.sourcesRuleExample),
        ),
        const SizedBox(height: 8),
        CaptionText(l10n.sourcesLocalNote(platform)),
        const SizedBox(height: 8),
        CaptionText(l10n.sourcesReadNote(platform)),
      ],
    );
  }
}

class _RingCard extends StatelessWidget {
  const new({required this.ring});

  final RingStatus ring;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final name = ring.name ?? ring.model;
    return MetricCard(
      key: DataSourcesKeys.ring,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.radio_button_checked_rounded, color: colors.oxygen),
              Text(
                name ?? l10n.sourcesRingTitle,
                style: theme.textTheme.titleMedium,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceInner,
                  border: Border.all(color: colors.strongBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: CaptionText(
                  l10n.sourcesRingMain,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          BodyText(
            ring.paired ? l10n.sourcesRingDetail : l10n.sourcesRingUnpaired,
          ),
        ],
      ),
    );
  }
}

extension on MetricOrigin {
  String label(AppLocalizations l10n) => switch (this) {
    MetricOrigin.ring => l10n.sourcesFromRing,
    MetricOrigin.phone => l10n.sourcesFromPhone,
    MetricOrigin.computed => l10n.sourcesComputed,
  };
}

extension on SourcedMetric {
  String label(AppLocalizations l10n) => switch (this) {
    SourcedMetric.steps => l10n.sourcesSteps,
    SourcedMetric.energy => l10n.sourcesEnergy,
    SourcedMetric.heartRate => l10n.sourcesHeartRate,
    SourcedMetric.hrv => l10n.sourcesHrv,
    SourcedMetric.spo2 => l10n.sourcesSpo2,
    SourcedMetric.stress => l10n.sourcesStress,
    SourcedMetric.sleep => l10n.sourcesSleep,
    SourcedMetric.battery => l10n.sourcesBattery,
    SourcedMetric.workouts => l10n.sourcesWorkouts,
    SourcedMetric.route => l10n.sourcesRoute,
    SourcedMetric.scores => l10n.sourcesScores,
  };

  String detail(AppLocalizations l10n) => switch (this) {
    SourcedMetric.steps => l10n.sourcesStepsDetail,
    SourcedMetric.energy => l10n.sourcesEnergyDetail,
    SourcedMetric.heartRate ||
    SourcedMetric.hrv ||
    SourcedMetric.spo2 ||
    SourcedMetric.stress => l10n.sourcesLoggedDetail,
    SourcedMetric.sleep => l10n.sourcesSleepDetail,
    SourcedMetric.battery => l10n.sourcesBatteryDetail,
    SourcedMetric.workouts => l10n.sourcesWorkoutsDetail,
    SourcedMetric.route => l10n.sourcesRouteDetail,
    SourcedMetric.scores => l10n.sourcesScoresDetail,
  };

  Color accent(AppColors colors) => switch (this) {
    SourcedMetric.steps ||
    SourcedMetric.energy ||
    SourcedMetric.workouts ||
    SourcedMetric.route => colors.activity,
    SourcedMetric.heartRate || SourcedMetric.hrv => colors.heart,
    SourcedMetric.spo2 => colors.oxygen,
    SourcedMetric.stress => colors.stress,
    SourcedMetric.sleep => colors.sleep,
    SourcedMetric.battery || SourcedMetric.scores => colors.textLabel,
  };
}

typedef _SeenSource = ({String id, int nights, int workouts, DateTime? last});

class _OtherApps extends ConsumerWidget {
  const new({
    required this.sleep,
    required this.workouts,
    required this.platform,
  });

  final HealthReadView sleep;
  final HealthReadView workouts;
  final String platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final now = ref.watch(clockProvider)();
    final askAgain = _askAgain(sleep) || _askAgain(workouts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TileGroup(
          children: [
            _ReadTile(
              kind: HealthRecordKind.sleep,
              view: sleep,
              platform: platform,
            ),
            _ReadTile(
              kind: HealthRecordKind.workout,
              view: workouts,
              platform: platform,
            ),
            for (final source in _seen())
              SettingsTile(
                key: DataSourcesKeys.app(source.id),
                leading: Icon(Icons.watch_outlined, color: colors.textLabel),
                title: sourceName(source.id, l10n),
                detail: _sourceDetail(source, l10n, format, now),
              ),
          ],
        ),
        if (askAgain) ...[
          const SizedBox(height: 8),
          SecondaryButton(
            key: DataSourcesKeys.openHealth,
            label: l10n.healthStatusOpen(platform),
            onPressed: () =>
                unawaited(ref.read(healthSettingsOpenerProvider).open()),
          ),
        ],
        const SizedBox(height: 8),
        if (sleep.enabled && sleep.sources.isEmpty) ...[
          CaptionText(l10n.sourcesSeenEmpty(platform)),
          const SizedBox(height: 4),
        ],
        if (workouts.enabled && workouts.sources.isEmpty) ...[
          CaptionText(l10n.sourcesSeenWorkoutsEmpty(platform)),
          const SizedBox(height: 4),
        ],
        CaptionText(l10n.sourcesSeenNoteAll(platform)),
      ],
    );
  }

  static bool _askAgain(HealthReadView view) =>
      view.declined || (view.enabled && view.access == HealthAccess.denied);

  List<_SeenSource> _seen() {
    final nights = {
      if (sleep.enabled)
        for (final source in sleep.sources) source.id: source,
    };
    final sessions = {
      if (workouts.enabled)
        for (final source in workouts.sources) source.id: source,
    };
    final ids = {...nights.keys, ...sessions.keys}.toList()..sort();
    return [
      for (final id in ids)
        (
          id: id,
          nights: nights[id]?.records ?? 0,
          workouts: sessions[id]?.records ?? 0,
          last: _latest(nights[id]?.lastEnd, sessions[id]?.lastEnd),
        ),
    ];
  }

  static DateTime? _latest(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  static String _sourceDetail(
    _SeenSource source,
    AppLocalizations l10n,
    MetricFormat format,
    DateTime now,
  ) {
    final last = source.last;
    return [
      if (source.nights > 0) l10n.sourcesSourceNights(source.nights),
      if (source.workouts > 0) l10n.sourcesSourceWorkouts(source.workouts),
      if (last != null) l10n.sourcesSourceLast(format.clockOrDay(last, now)),
    ].join(' · ');
  }
}

class _ReadTile extends ConsumerWidget {
  const new({required this.kind, required this.view, required this.platform});

  final HealthRecordKind kind;
  final HealthReadView view;
  final String platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final available = view.access != HealthAccess.unavailable;
    final notifier = ref.read(healthReadsProvider(kind).notifier);
    final (title, accent) = switch (kind) {
      HealthRecordKind.workout => (l10n.sourcesReadWorkouts, colors.activity),
      _ => (l10n.sourcesReadSleep, colors.sleep),
    };
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              AccentDot(color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    CaptionText(_status(l10n)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                key: DataSourcesKeys.read(kind),
                value: view.enabled,
                onChanged: available
                    ? (on) => unawaited(notifier.setEnabled(enabled: on))
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _status(AppLocalizations l10n) =>
      switch ((view.enabled, view.access)) {
        (_, HealthAccess.unavailable) => l10n.sourcesReadUnavailable,
        (true, HealthAccess.granted) => l10n.sourcesReadOn(platform),
        (true, _) => l10n.sourcesReadRevoked(platform),
        (false, HealthAccess.granted) => l10n.sourcesReadOff,
        (false, _) => _ask(l10n),
      };

  String _ask(AppLocalizations l10n) => switch (kind) {
    HealthRecordKind.workout => l10n.sourcesReadAskWorkouts(platform),
    _ => l10n.sourcesReadAsk(platform),
  };
}

class _PriorityCard extends ConsumerWidget {
  const new({required this.kind, required this.view});

  final HealthRecordKind kind;
  final HealthReadView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final notifier = ref.read(healthReadsProvider(kind).notifier);
    final workouts = kind == HealthRecordKind.workout;
    return MetricCard(
      key: DataSourcesKeys.priorityOf(kind),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(
            title: workouts ? l10n.sourcesWorkouts : l10n.sourcesPrioritySleep,
            accent: workouts ? colors.activity : colors.sleep,
          ),
          const SizedBox(height: 8),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) => unawaited(notifier.move(from, to)),
            children: [
              for (final (index, source) in view.priority.indexed)
                _PriorityRow(
                  key: DataSourcesKeys.rank(source, kind: kind),
                  kind: kind,
                  source: source,
                  index: index,
                  count: view.priority.length,
                  onMove: (to) => unawaited(notifier.move(index, to)),
                ),
            ],
          ),
          if (view.single) CaptionText(l10n.sourcesPrioritySingle),
          if (workouts && !view.single)
            CaptionText(l10n.sourcesPriorityWorkoutsNote),
        ],
      ),
    );
  }
}

// Product name, never translated.
const _ownWorkoutsName = 'OpenRing';

class _PriorityRow extends StatelessWidget {
  const new({
    required this.kind,
    required this.source,
    required this.index,
    required this.count,
    required this.onMove,
    super.key,
  });

  final HealthRecordKind kind;
  final String source;
  final int index;
  final int count;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final (name, detail) = _describe(l10n);
    final label = Row(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 24),
          child: Text(
            '${index + 1}',
            style: numberStyle(
              theme.textTheme.titleMedium,
              color: colors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              CaptionText(detail),
            ],
          ),
        ),
      ],
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: DataSourcesKeys.moveUp(source, kind: kind),
          tooltip: l10n.sourcesMoveUp(name),
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
          onPressed: index == 0 ? null : () => onMove(index - 1),
        ),
        IconButton(
          key: DataSourcesKeys.moveDown(source, kind: kind),
          tooltip: l10n.sourcesMoveDown(name),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: index == count - 1 ? null : () => onMove(index + 1),
        ),
        ReorderableDragStartListener(
          key: DataSourcesKeys.drag(source, kind: kind),
          index: index,
          enabled: count > 1,
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: Icon(Icons.drag_handle_rounded, color: colors.textLabel),
            ),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: context.prefersSingleColumn
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label,
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: controls,
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: label),
                controls,
              ],
            ),
    );
  }

  (String, String) _describe(AppLocalizations l10n) {
    final app = l10n.sourcesPriorityAppDetail(healthPlatformName());
    if (source != ringSource) return (sourceName(source, l10n), app);
    return switch (kind) {
      HealthRecordKind.workout => (
        _ownWorkoutsName,
        l10n.sourcesPriorityOwnWorkoutDetail,
      ),
      _ => (sourceName(source, l10n), l10n.sourcesPriorityRingDetail),
    };
  }
}
