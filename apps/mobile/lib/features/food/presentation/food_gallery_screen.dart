import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/application/gallery_backfill.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/presentation/meal_saved_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

typedef GalleryDateTimePicker = Future<DateTime?> Function(
  BuildContext context, {
  required DateTime initial,
  required DateTime lastDate,
});

final Provider<GalleryDateTimePicker> galleryDateTimePickerProvider =
    Provider<GalleryDateTimePicker>((ref) => _showGalleryDateTimePicker);

DateTime _clampDate(DateTime value, DateTime min, DateTime max) {
  if (value.isBefore(min)) return min;
  if (value.isAfter(max)) return max;
  return value;
}

Future<DateTime?> _showGalleryDateTimePicker(
  BuildContext context, {
  required DateTime initial,
  required DateTime lastDate,
}) async {
  final first = DateTime(2000);
  final clamped = _clampDate(initial, first, lastDate);
  final date = await showDatePicker(
    context: context,
    initialDate: clamped,
    firstDate: first,
    lastDate: lastDate,
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(clamped),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

abstract final class FoodGalleryKeys {
  static const save = Key('food_gallery_save');
  static const pickAgain = Key('food_gallery_pick_again');

  static Key item(int index) => Key('food_gallery_item_$index');
  static Key anotherMeal(int index) => Key('food_gallery_another_$index');
  static Key skip(int index) => Key('food_gallery_skip_$index');
  static Key pickTime(int index) => Key('food_gallery_time_$index');
  static Key saveOld(int index) => Key('food_gallery_old_$index');
}

class FoodGalleryScreen extends ConsumerWidget {
  const new({super.key, this.initialDay, this.autoPick = true});

  final LocalDate? initialDay;
  final bool autoPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = MetricFormat.of(context).l10n;
    final on = ref.watch(foodEnabledProvider);
    if (!on) {
      return AppPage(title: l10n.foodGalleryTitle, children: const []);
    }
    return _FoodGalleryBody(initialDay: initialDay, autoPick: autoPick);
  }
}

class _FoodGalleryBody extends ConsumerStatefulWidget {
  const new({required this.initialDay, required this.autoPick});

  final LocalDate? initialDay;
  final bool autoPick;

  @override
  ConsumerState<_FoodGalleryBody> createState() => _FoodGalleryBodyState();
}

class _FoodGalleryBodyState extends ConsumerState<_FoodGalleryBody> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(galleryBackfillProvider, _onStateChanged);
    if (!widget.autoPick) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ref.read(foodEnabledProvider)) return;
      final notifier = ref.read(galleryBackfillProvider.notifier)..reset();
      unawaited(notifier.pick());
    });
  }

  void _onStateChanged(GalleryImportState? previous, GalleryImportState next) {
    if (!mounted) return;
    final l10n = MetricFormat.of(context).l10n;
    if (previous?.phase == GalleryImportPhase.picking &&
        next.phase == GalleryImportPhase.idle) {
      if (next.pickFailed) _snack(l10n.foodGalleryPickFailed);
      _popIfMounted();
      return;
    }
    if (next.phase == GalleryImportPhase.done &&
        previous?.phase != GalleryImportPhase.done) {
      final message = _doneMessage(l10n, next);
      if (message != null) _snack(message);
      _popIfMounted(reset: true);
    }
  }

  void _popIfMounted({bool reset = false}) {
    final router = GoRouter.maybeOf(context);
    if (router == null || !router.canPop()) return;
    if (reset) ref.read(galleryBackfillProvider.notifier).reset();
    router.pop();
  }

  String? _doneMessage(AppLocalizations l10n, GalleryImportState next) {
    if (next.noSpace) return l10n.foodNoSpaceTitle;
    if (next.saveFailed && next.savedCount == 0) return l10n.foodAddFailed;
    if (next.savedCount > 0) return l10n.foodGallerySavedCount(next.savedCount);
    return null;
  }

  Future<void> _pickTime(int index) async {
    final picker = ref.read(galleryDateTimePickerProvider);
    final now = ref.read(clockProvider)().toLocal();
    final backfill = ref.read(galleryBackfillProvider.notifier);
    final day = widget.initialDay;
    final initial = day == null || day == foodDay(now)
        ? now
        : DateTime(day.year, day.month, day.day, 12);
    final picked = await picker(context, initial: initial, lastDate: now);
    if (!mounted || picked == null) return;
    final ok = await backfill.setManualTime(index, picked);
    if (!mounted || ok) return;
    _snack(MetricFormat.of(context).l10n.foodAddFutureError);
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final now = ref.watch(clockProvider)().toLocal();
    final importState = ref.watch(galleryBackfillProvider);
    final notifier = ref.read(galleryBackfillProvider.notifier);
    final saving = importState.phase == GalleryImportPhase.saving;
    final inReview = importState.phase == GalleryImportPhase.review;
    return AppPage(
      title: l10n.foodGalleryTitle,
      subtitle: l10n.foodGallerySubtitle,
      children: [
        if (importState.phase == GalleryImportPhase.idle ||
            importState.phase == GalleryImportPhase.done)
          ActionButton(
            buttonKey: FoodGalleryKeys.pickAgain,
            label: l10n.foodGalleryTitle,
            onPressed: () => unawaited(notifier.pick()),
          ),
        if (importState.phase == GalleryImportPhase.picking)
          const SizedBox(height: 96),
        if (inReview || saving) ...[
          CaptionText(l10n.foodGalleryPickerNote),
          const SizedBox(height: cardGap),
          for (final item in importState.items) ...[
            _GalleryItemCard(
              item: item,
              format: format,
              now: now,
              enabled: inReview,
              onAnotherMeal: () => notifier.confirmAnotherMeal(item.index),
              onPickTime: () => unawaited(_pickTime(item.index)),
              onSaveOld: () => notifier.confirmOld(item.index),
              onSkip: () => notifier.skip(item.index),
            ),
            const SizedBox(height: cardGap),
          ],
          ActionButton(
            buttonKey: FoodGalleryKeys.save,
            label: l10n.foodGallerySaveButton(importState.readyCount),
            onPressed: inReview && importState.readyCount > 0
                ? () => unawaited(notifier.saveReady())
                : null,
          ),
          const SizedBox(height: 8),
          CaptionText(
            importState.openCount > 0
                ? l10n.foodGalleryOpenChoices(importState.openCount)
                : l10n.foodGalleryStripNote,
            textAlign: TextAlign.center,
          ),
        ] else ...[
          const SizedBox(height: cardGap),
          CaptionText(l10n.foodGalleryPickerNote),
        ],
      ],
    );
  }
}

class _GalleryItemCard extends StatelessWidget {
  const new({
    required this.item,
    required this.format,
    required this.now,
    required this.enabled,
    required this.onAnotherMeal,
    required this.onPickTime,
    required this.onSaveOld,
    required this.onSkip,
  });

  final GalleryItem item;
  final MetricFormat format;
  final DateTime now;
  final bool enabled;
  final VoidCallback onAnotherMeal;
  final VoidCallback onPickTime;
  final VoidCallback onSaveOld;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final l10n = format.l10n;
    final theme = Theme.of(context);
    return MetricCard(
      key: FoodGalleryKeys.item(item.index),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GalleryThumb(
            bytes: item.strippedBytes,
            unreadableLabel: l10n.foodGalleryUnreadable,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title(l10n),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                ..._details(context, l10n),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _title(AppLocalizations l10n) {
    if (item.status == GalleryItemStatus.unreadable) {
      return l10n.foodGalleryUnreadable;
    }
    if (item.captureAt == null || item.offsetMinutes == null) {
      return l10n.foodGalleryNoTimeTitle;
    }
    return format.clockOrDay(
      item.captureAt!,
      now,
      offset: Duration(minutes: item.offsetMinutes!),
    );
  }

  List<Widget> _details(BuildContext context, AppLocalizations l10n) {
    switch (item.status) {
      case GalleryItemStatus.ready:
        return [_ReadyLine(label: _readyLabel(l10n))];
      case GalleryItemStatus.skipped:
        return [CaptionText(l10n.foodGallerySkipped)];
      case GalleryItemStatus.unreadable:
        return const [];
      case GalleryItemStatus.nearDuplicate:
        final dupWhen = format.clockOrDay(
          item.duplicateOfAt!,
          now,
          offset: Duration(minutes: item.duplicateOfOffsetMinutes ?? 0),
        );
        return [
          BodyText(l10n.foodGalleryDuplicateBody(dupWhen)),
          const SizedBox(height: 8),
          AdaptiveColumns(
            first: SecondaryButton(
              buttonKey: FoodGalleryKeys.anotherMeal(item.index),
              label: l10n.foodGalleryAnotherMeal,
              onPressed: enabled ? onAnotherMeal : null,
            ),
            second: SecondaryButton(
              buttonKey: FoodGalleryKeys.skip(item.index),
              label: l10n.foodGallerySkip,
              onPressed: enabled ? onSkip : null,
            ),
          ),
        ];
      case GalleryItemStatus.needsTime:
        return [
          BodyText(l10n.foodGalleryNoTimeBody),
          const SizedBox(height: 8),
          AdaptiveColumns(
            first: SecondaryButton(
              buttonKey: FoodGalleryKeys.pickTime(item.index),
              label: l10n.foodGalleryPickTime,
              onPressed: enabled ? onPickTime : null,
            ),
            second: SecondaryButton(
              buttonKey: FoodGalleryKeys.skip(item.index),
              label: l10n.foodGallerySkip,
              onPressed: enabled ? onSkip : null,
            ),
          ),
        ];
      case GalleryItemStatus.tooOld:
        return [
          BodyText(l10n.foodGalleryOldBody),
          const SizedBox(height: 8),
          AdaptiveColumns(
            first: SecondaryButton(
              buttonKey: FoodGalleryKeys.saveOld(item.index),
              label: l10n.foodGallerySaveAnyway,
              onPressed: enabled ? onSaveOld : null,
            ),
            second: SecondaryButton(
              buttonKey: FoodGalleryKeys.skip(item.index),
              label: l10n.foodGallerySkip,
              onPressed: enabled ? onSkip : null,
            ),
          ),
        ];
    }
  }

  String _readyLabel(AppLocalizations l10n) {
    final at = item.captureAt!;
    final offset = item.offsetMinutes!;
    if (!item.timeFromPhoto) {
      return l10n.foodGalleryChosenTime(
        format.clockOrDay(at, now, offset: Duration(minutes: offset)),
      );
    }
    final slot = mealSlotLabel(
      l10n,
      Meal(id: item.index, at: at, offsetMinutes: offset, createdAt: at),
    );
    return l10n.foodGalleryFromPhoto(slot);
  }
}

class _ReadyLine extends StatelessWidget {
  const new({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.of(context).activity;
    return Row(
      children: [
        Icon(Icons.check_rounded, size: 16, color: color),
        const SizedBox(width: 4),
        Expanded(child: BodyText(label)),
      ],
    );
  }
}

class _GalleryThumb extends StatefulWidget {
  const new({required this.bytes, required this.unreadableLabel});

  final Uint8List bytes;
  final String unreadableLabel;

  @override
  State<_GalleryThumb> createState() => _GalleryThumbState();
}

class _GalleryThumbState extends State<_GalleryThumb> {
  bool _failed = false;

  @override
  void didUpdateWidget(_GalleryThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.bytes, oldWidget.bytes)) _failed = false;
  }

  Widget _placeholder(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      label: widget.unreadableLabel,
      child: SizedBox(
        width: 48,
        height: 48,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceInner,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.broken_image_outlined,
            size: 20,
            color: colors.textLabel,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || widget.bytes.isEmpty) return _placeholder(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.memory(
        widget.bytes,
        width: 48,
        height: 48,
        cacheWidth: 96,
        fit: BoxFit.cover,
        errorBuilder: (context, _, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_failed) setState(() => _failed = true);
          });
          return _placeholder(context);
        },
      ),
    );
  }
}
