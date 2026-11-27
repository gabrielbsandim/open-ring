import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/text_scale.dart';
import 'package:open_ring/features/effort/application/effort_gate.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';

abstract final class EffortRatingKeys {
  static const card = Key('effort_rating_card');
  static const skip = Key('effort_rating_skip');
  static const rateNow = Key('effort_rating_rate_now');
  static const change = Key('effort_rating_change');
  static const clear = Key('effort_rating_clear');
  static const value = Key('effort_rating_value');
  static const failed = Key('effort_rating_failed');

  static Key option(int rating) => Key('effort_rating_option_$rating');
}

const _optionsPerRow = 5;
const _optionGap = 8.0;
const _optionSize = 48.0;
const int _optionCount = effortMaxRating - effortMinRating + 1;

/// Asks how hard one workout was and stores the answer. It shows only while
/// the Effort module is on and the workout is stored.
class EffortRatingCard extends ConsumerStatefulWidget {
  const new recorded({required int this.workoutId, super.key})
    : recordId = null;

  const new imported({required String this.recordId, super.key})
    : workoutId = null;

  final int? workoutId;
  final String? recordId;

  @override
  ConsumerState<EffortRatingCard> createState() => _EffortRatingCardState();
}

class _EffortRatingCardState extends ConsumerState<EffortRatingCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _skipped = false;
  bool _editing = false;
  bool _busy = false;
  bool _failed = false;

  ({int? rating})? _stored() {
    final recordId = widget.recordId;
    if (recordId != null) {
      final workout = ref.watch(importedWorkoutProvider(recordId)).value;
      return workout == null ? null : (rating: workout.rating);
    }
    final workout = ref.watch(savedWorkoutProvider(widget.workoutId!)).value;
    return workout == null ? null : (rating: workout.rating);
  }

  Future<bool> _write(int? rating) {
    final recordId = widget.recordId;
    if (recordId != null) return rateImportedWorkout(ref, recordId, rating);
    return rateRecordedWorkout(ref, widget.workoutId!, rating);
  }

  Future<void> _rate(int? rating) async {
    if (_busy) return;
    setState(() => _busy = true);
    final saved = await _saved(rating);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = !saved;
      if (!saved) return;
      _editing = false;
      _skipped = false;
    });
  }

  Future<bool> _saved(int? rating) async {
    try {
      return await _write(rating);
    } on Object {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!ref.watch(effortEnabledProvider)) return const SizedBox.shrink();
    final stored = _stored();
    if (stored == null) return const SizedBox.shrink();
    final l10n = MetricFormat.of(context).l10n;
    final colors = AppColors.of(context);
    final rating = stored.rating;
    return MetricCard(
      key: EffortRatingKeys.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccentTitle(title: l10n.effortRatingTitle, accent: colors.activity),
          const SizedBox(height: 8),
          ..._content(context, rating),
          if (_failed) ...[
            const SizedBox(height: 8),
            CaptionText(
              l10n.effortRatingFailed,
              key: EffortRatingKeys.failed,
              color: colors.heart,
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context, int? rating) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    if (rating == null && _skipped) {
      return [
        BodyText(l10n.effortRatingNotRated),
        _Link(
          id: EffortRatingKeys.rateNow,
          label: l10n.effortRatingRateNow,
          onPressed: () => setState(() => _skipped = false),
        ),
      ];
    }
    if (rating == null) {
      return [
        CaptionText(l10n.effortRatingBody),
        const SizedBox(height: 12),
        _Options(selected: null, onRate: _rate),
        _Link(
          id: EffortRatingKeys.skip,
          label: l10n.effortRatingSkip,
          onPressed: () => setState(() {
            _skipped = true;
            _failed = false;
          }),
        ),
      ];
    }
    final value = BodyText(
      l10n.effortRatingValue(
        format.integer(rating),
        format.integer(effortMaxRating),
      ),
      key: EffortRatingKeys.value,
    );
    if (!_editing) {
      return [
        value,
        _Link(
          id: EffortRatingKeys.change,
          label: l10n.effortRatingChange,
          onPressed: () => setState(() => _editing = true),
        ),
      ];
    }
    return [
      value,
      const SizedBox(height: 12),
      _Options(selected: rating, onRate: _rate),
      _Link(
        id: EffortRatingKeys.clear,
        label: l10n.effortRatingClear,
        onPressed: () => _rate(null),
      ),
    ];
  }
}

class _Options extends StatelessWidget {
  const new({required this.selected, required this.onRate});

  final int? selected;
  final ValueChanged<int> onRate;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gaps = _optionGap * (_optionsPerRow - 1);
      final cell = (constraints.maxWidth - gaps) / _optionsPerRow;
      if (context.prefersSingleColumn || cell < _optionSize) return _wrapped();
      return _grid();
    },
  );

  Widget _wrapped() => SizedBox(
    width: double.infinity,
    child: Wrap(
      spacing: _optionGap,
      runSpacing: _optionGap,
      children: [
        for (var index = 0; index < _optionCount; index++)
          _option(index, compact: true),
      ],
    ),
  );

  Widget _grid() => Column(
    children: [
      for (var row = 0; row < _optionCount ~/ _optionsPerRow; row++) ...[
        if (row > 0) const SizedBox(height: _optionGap),
        Row(
          children: [
            for (var column = 0; column < _optionsPerRow; column++) ...[
              if (column > 0) const SizedBox(width: _optionGap),
              Expanded(
                child: _option(row * _optionsPerRow + column, compact: false),
              ),
            ],
          ],
        ),
      ],
    ],
  );

  Widget _option(int index, {required bool compact}) {
    final rating = effortMinRating + index;
    return _Option(
      rating: rating,
      selected: rating == selected,
      compact: compact,
      onTap: () => onRate(rating),
    );
  }
}

class _Option extends StatelessWidget {
  const new({
    required this.rating,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final int rating;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: selected ? colors.activity : colors.strongBorder),
    );
    return Semantics(
      key: EffortRatingKeys.option(rating),
      button: true,
      selected: selected,
      label: format.l10n.effortRatingOption(
        format.integer(rating),
        format.integer(effortMaxRating),
      ),
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.activity : colors.surfaceInner,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: _optionSize,
              minHeight: _optionSize,
            ),
            child: Center(
              widthFactor: compact ? 1 : null,
              heightFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  format.integer(rating),
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: selected ? colors.onAccent : colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const new({required this.id, required this.label, required this.onPressed});

  final Key id;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton(
      key: id,
      style: TextButton.styleFrom(
        minimumSize: const Size(_optionSize, _optionSize),
        foregroundColor: AppColors.of(context).textSecondary,
      ),
      onPressed: onPressed,
      child: Text(label),
    ),
  );
}
