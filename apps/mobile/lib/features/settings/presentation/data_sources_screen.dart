import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/core/widgets/text_scale.dart';
import 'package:open_ring/features/health_sync/application/enable_background_reads.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/health_sync/application/health_status_providers.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/features/settings/presentation/source_labels.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class DataSourcesKeys {
  static const readSleep = Key('sources_read_sleep');
  static const readWorkouts = Key('sources_read_workouts');
  static const openHealth = Key('sources_open_health');
  static const priority = Key('sources_priority');
  static const workoutPriority = Key('sources_priority_workout');

  static Key read(HealthRecordKind kind) => switch (kind) {
    HealthRecordKind.workout => readWorkouts,
    _ => readSleep,
  };

  static Key priorityOf(HealthRecordKind kind) => switch (kind) {
    HealthRecordKind.workout => workoutPriority,
    _ => priority,
  };

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
    final platform = healthPlatformName();
    return AppPage(
      title: l10n.sourcesTitle,
      subtitle: l10n.sourcesIntro(platform),
      children: [
        SectionHeader(l10n.sourcesOtherTitle(platform)),
        AsyncBody(
          value: ref.watch(healthReadProvider),
          builder: (sleep) => AsyncBody(
            value: ref.watch(workoutReadProvider),
            builder: (workouts) =>
                _Sources(sleep: sleep, workouts: workouts, platform: platform),
          ),
        ),
      ],
    );
  }
}

class _Sources extends ConsumerWidget {
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
    final askAgain = _askAgain(sleep) || _askAgain(workouts);
    final ranked = [
      if (_choosable(sleep)) (HealthRecordKind.sleep, sleep),
      if (_choosable(workouts)) (HealthRecordKind.workout, workouts),
    ];
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
        CaptionText(l10n.sourcesReadNote(platform)),
        if (ranked.isNotEmpty) ...[
          SectionHeader(l10n.sourcesPriorityTitle),
          CaptionText(l10n.sourcesPriorityBody),
          for (final (kind, view) in ranked) ...[
            const SizedBox(height: cardGap),
            _PriorityCard(kind: kind, view: view),
          ],
        ],
      ],
    );
  }

  static bool _askAgain(HealthReadView view) =>
      view.declined || (view.enabled && view.access == HealthAccess.denied);

  static bool _choosable(HealthReadView view) => view.enabled && !view.single;
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
                    ? (on) => unawaited(_setRead(ref, notifier, on: on))
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

// Turning a read on may let the job run without a ring; turning the last one
// off leaves it nothing to do.
Future<void> _setRead(
  WidgetRef ref,
  HealthReadController notifier, {
  required bool on,
}) async {
  final enable = ref.read(enableBackgroundReadsProvider);
  final interval = ref.read(syncIntervalProvider.notifier);
  await notifier.setEnabled(enabled: on);
  try {
    await (on ? enable() : interval.ensureScheduled());
  } on Object catch (error) {
    debugPrint('Background sync was not updated: $error');
  }
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
          if (workouts) CaptionText(l10n.sourcesPriorityWorkoutsNote),
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
    final name = _name(l10n);
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
          child: Text(
            name,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.textPrimary,
            ),
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

  String _name(AppLocalizations l10n) {
    if (source == ringSource && kind == HealthRecordKind.workout) {
      return _ownWorkoutsName;
    }
    return sourceName(source, l10n);
  }
}
