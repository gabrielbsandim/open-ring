import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/food/application/food_photo_storage.dart';

abstract final class FoodStorageKeys {
  static const summary = Key('food_storage_summary');
  static const totalSize = Key('food_storage_total_size');
  static const photoCount = Key('food_storage_photo_count');
  static const average = Key('food_storage_average');
  static const oldest = Key('food_storage_oldest');
  static const pace = Key('food_storage_pace');
  static const deleteOldButton = Key('food_storage_delete_old');
  static const purgeSheet = Key('food_storage_purge_sheet');
  static const confirmDialog = Key('food_storage_confirm_dialog');
  static const confirmDelete = Key('food_storage_confirm_delete');
  static const confirmCancel = Key('food_storage_confirm_cancel');
  static const footnote = Key('food_storage_footnote');

  static Key option(PhotoPurgeRange range) =>
      Key('food_storage_option_${range.name}');
}

class FoodStorageScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<FoodStorageScreen> createState() => _FoodStorageScreenState();
}

class _FoodStorageScreenState extends ConsumerState<FoodStorageScreen> {
  var _purging = false;

  @override
  Widget build(BuildContext context) {
    final f = MetricFormat.of(context);
    final storage = ref.watch(foodPhotoStorageProvider);
    return AppPage(
      title: f.l10n.foodPhotosTitle,
      children: _body(context, storage, f),
    );
  }

  List<Widget> _body(
    BuildContext context,
    AsyncValue<FoodPhotoStorageView> storage,
    MetricFormat f,
  ) {
    if (storage.hasValue && !storage.hasError) {
      return _loaded(context, storage.requireValue, f);
    }
    if (storage.hasError) return [BodyText(f.l10n.metricLoadError)];
    return const [SizedBox(height: 96)];
  }

  List<Widget> _loaded(
    BuildContext context,
    FoodPhotoStorageView view,
    MetricFormat f,
  ) {
    final l10n = f.l10n;
    final colors = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final details = [
      if (view.averageBytes case final avg?)
        MetricRow(
          key: FoodStorageKeys.average,
          label: l10n.foodPhotosAverageLabel,
          value: formatPhotoBytes(f, avg),
        ),
      if (view.earliestDay case final earliest?)
        MetricRow(
          key: FoodStorageKeys.oldest,
          label: l10n.foodPhotosOldestLabel,
          value: f.date(earliest),
        ),
      if (view.projectedBytesPerYear case final pace?)
        MetricRow(
          key: FoodStorageKeys.pace,
          label: l10n.foodPhotosPaceLabel,
          value: l10n.foodPhotosPaceValue(formatPhotoBytes(f, pace)),
        ),
    ];
    return [
      MetricCard(
        key: FoodStorageKeys.summary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              key: FoodStorageKeys.totalSize,
              formatPhotoBytes(f, view.totalBytes),
              style: numberStyle(t.headlineMedium, color: colors.textPrimary),
            ),
            const SizedBox(height: 4),
            CaptionText(
              key: FoodStorageKeys.photoCount,
              l10n.foodPhotosCount(view.photoCount),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: colors.surfaceBorder),
              const SizedBox(height: 12),
              for (final (index, row) in details.indexed) ...[
                if (index > 0) const SizedBox(height: 8),
                row,
              ],
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      OutlinedButton(
        key: FoodStorageKeys.deleteOldButton,
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.heart,
          minimumSize: const Size.fromHeight(48),
        ),
        onPressed: !_purging && view.canDeleteAny
            ? () => unawaited(_startPurge(view))
            : null,
        child: Text(l10n.foodPhotosDeleteButton, textAlign: TextAlign.center),
      ),
      const SizedBox(height: 12),
      CaptionText(l10n.foodPhotosFootnote, key: FoodStorageKeys.footnote),
    ];
  }

  Future<void> _startPurge(FoodPhotoStorageView view) async {
    if (_purging) return;
    setState(() => _purging = true);
    try {
      final range = await showModalBottomSheet<PhotoPurgeRange>(
        context: context,
        isScrollControlled: true,
        builder: (sheetCtx) => _purgeSheet(sheetCtx, view),
      );
      if (!mounted || range == null) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) =>
            _confirmDialog(dialogCtx, view.previews[range]!),
      );
      if (!mounted || confirmed != true) return;
      final messenger = ScaffoldMessenger.of(context);
      final f = MetricFormat.of(context);
      final result = await ref
          .read(foodPhotoPurgerProvider)
          .purge(range, asOf: view.asOf);
      if (!mounted) return;
      final text = result == null
          ? f.l10n.foodPhotosDeleteFailed
          : f.l10n.foodPhotosDeleted(
              result.removedPhotos,
              formatPhotoBytes(f, result.freedBytes),
            );
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(text)));
    } finally {
      if (mounted) setState(() => _purging = false);
    }
  }
}

Widget _purgeSheet(BuildContext context, FoodPhotoStorageView view) {
  final f = MetricFormat.of(context);
  final l10n = f.l10n;
  final colors = AppColors.of(context);
  return SafeArea(
    child: SingleChildScrollView(
      key: FoodStorageKeys.purgeSheet,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.foodPhotosSheetTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 6),
          BodyText(l10n.foodPhotosSheetBody),
          const SizedBox(height: 12),
          for (final (index, range) in PhotoPurgeRange.values.indexed) ...[
            if (index > 0) Divider(height: 1, color: colors.surfaceBorder),
            _optionTile(context, f, colors, range, view.previews[range]!),
          ],
        ],
      ),
    ),
  );
}

Widget _optionTile(
  BuildContext context,
  MetricFormat f,
  AppColors colors,
  PhotoPurgeRange range,
  PhotoPurgePreview preview,
) {
  final l10n = f.l10n;
  final orphan =
      range == PhotoPurgeRange.all && preview.count == 0 && preview.bytes > 0;
  final hasFiles = preview.count > 0 || orphan;
  final sizeText = formatPhotoBytes(f, preview.bytes);
  return ListTile(
    key: FoodStorageKeys.option(range),
    contentPadding: EdgeInsets.zero,
    enabled: hasFiles,
    title: Text(l10n.foodPhotosRangeLabel(range.name)),
    subtitle: CaptionText(
      orphan
          ? l10n.foodPhotosPreviewOrphan(sizeText)
          : l10n.foodPhotosPreviewLine(preview.count, sizeText),
    ),
    trailing: hasFiles
        ? Icon(Icons.chevron_right_rounded, color: colors.textLabel)
        : null,
    onTap: hasFiles ? () => Navigator.of(context).pop(range) : null,
  );
}

Widget _confirmDialog(BuildContext context, PhotoPurgePreview preview) {
  final f = MetricFormat.of(context);
  final l10n = f.l10n;
  final colors = AppColors.of(context);
  return AlertDialog(
    key: FoodStorageKeys.confirmDialog,
    scrollable: true,
    title: Text(l10n.foodPhotosConfirmTitle),
    content: Text(
      l10n.foodPhotosConfirmBody(
        preview.count,
        formatPhotoBytes(f, preview.bytes),
      ),
    ),
    actions: [
      TextButton(
        key: FoodStorageKeys.confirmCancel,
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(l10n.settingsDeleteCancel),
      ),
      FilledButton(
        key: FoodStorageKeys.confirmDelete,
        style: FilledButton.styleFrom(
          backgroundColor: colors.heart,
          foregroundColor: colors.onAccent,
        ),
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(l10n.settingsDeleteConfirm),
      ),
    ],
  );
}
