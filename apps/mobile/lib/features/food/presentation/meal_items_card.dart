import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/domain/meal_analysis_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class MealItemsKeys {
  static const card = Key('meal_ai_items');
  static const confirm = Key('meal_ai_items_confirm');
  static Key less(int itemId) => Key('meal_ai_item_less_$itemId');
  static Key more(int itemId) => Key('meal_ai_item_more_$itemId');
  static Key hidden(MealHiddenChip chip) => Key('meal_ai_hidden_${chip.name}');
}

enum MealHiddenChip { oil, sauce, sugar }

const int _maxCountX2 = 12;

/// Household items and the hidden fat chips of a done analysis. The section
/// builds it only behind [mealPhotoItemsEnabledProvider].
class MealItemsCard extends ConsumerStatefulWidget {
  const new({required this.row, super.key});

  final MealAnalysis row;

  @override
  ConsumerState<MealItemsCard> createState() => _MealItemsCardState();
}

class _MealItemsCardState extends ConsumerState<MealItemsCard> {
  // The store deletes an item at 0; the row stays here, read as Removed,
  // until the screen closes.
  final Map<int, (int, MealAnalysisItem)> _removed = {};

  // Each tap steps from the last count asked for, and writes go one at a
  // time, so quick taps all land in order.
  final Map<int, int> _counts = {};
  Future<void> _writes = Future.value();

  MealAnalysisStore get _store => ref.read(mealAnalysisStoreProvider);

  List<(MealAnalysisItem, bool)> _rows() {
    final rows = [for (final item in widget.row.items) (item, false)];
    final live = {for (final item in widget.row.items) item.id};
    for (final MapEntry(:key, value: (index, item)) in _removed.entries) {
      if (live.contains(key)) continue;
      rows.insert(index.clamp(0, rows.length), (item, true));
    }
    return rows;
  }

  void _step(MealAnalysisItem item, int index, int delta) {
    final next = _count(item) + delta;
    if (next < 0 || next > _maxCountX2) return;
    setState(() {
      _counts[item.id] = next;
      if (next == 0) _removed[item.id] = (index, item);
    });
    // Each link catches its own failure, so later taps still land, and the
    // store is taken now, so a write queued before the screen closes still runs.
    final store = _store;
    _writes = _writes
        .then<void>((_) => store.setItemCount(item.id, next))
        .catchError((Object _) => _reset(item.id));
    unawaited(_writes);
  }

  void _reset(int itemId) {
    if (!mounted) return;
    setState(() => _counts.remove(itemId));
  }

  int _count(MealAnalysisItem item) => _counts[item.id] ?? item.countX2;

  // After any pending step; a failed write leaves the button for another tap.
  void _confirm() {
    final store = _store;
    final id = widget.row.id;
    _writes = _writes
        .then<void>((_) => store.confirmItems(id))
        .catchError((Object _) {});
    unawaited(_writes);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final row = widget.row;
    final open = row.items.any((item) => !item.confirmed);
    final hidden = {
      MealHiddenChip.oil: (l10n.foodAiHiddenOil, row.hiddenOil),
      MealHiddenChip.sauce: (l10n.foodAiHiddenSauce, row.hiddenSauce),
      MealHiddenChip.sugar: (l10n.foodAiHiddenSugar, row.hiddenSugar),
    };
    return Column(
      key: MealItemsKeys.card,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        _Title(l10n.foodAiItemsTitle),
        if (open) CaptionText(l10n.foodAiItemsCheck),
        for (final (index, (item, removed)) in _rows().indexed)
          _ItemRow(
            item: item,
            removed: removed,
            countX2: _count(item),
            onStep: (delta) => _step(item, index, delta),
          ),
        const SizedBox(height: 12),
        _Title(l10n.foodAiHiddenTitle),
        Wrap(
          spacing: 8,
          children: [
            for (final MapEntry(key: chip, value: (label, on))
                in hidden.entries)
              FilterChip(
                key: MealItemsKeys.hidden(chip),
                label: Text(label),
                selected: on,
                onSelected: (value) => unawaited(_toggle(chip, value)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        CaptionText(l10n.foodAiItemsNote),
        const SizedBox(height: 8),
        if (open)
          SecondaryButton(
            buttonKey: MealItemsKeys.confirm,
            label: l10n.foodAiItemsConfirm,
            onPressed: _confirm,
          )
        else if (row.items.isNotEmpty)
          BodyText(l10n.foodAiItemsDone),
      ],
    );
  }

  Future<bool> _toggle(MealHiddenChip chip, bool on) {
    final id = widget.row.id;
    return switch (chip) {
      MealHiddenChip.oil => _store.setHidden(id, oil: on),
      MealHiddenChip.sauce => _store.setHidden(id, sauce: on),
      MealHiddenChip.sugar => _store.setHidden(id, sugar: on),
    };
  }
}

class _Title extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}

class _ItemRow extends StatelessWidget {
  const new({
    required this.item,
    required this.removed,
    required this.countX2,
    required this.onStep,
  });

  final MealAnalysisItem item;
  final bool removed;
  final int countX2;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final count = NumberFormat('0.#', l10n.localeName).format(countX2 / 2);
    // The wire names are snake case and the select cases camelCase; the enum
    // name is the camelCase one, and unit falls to other.
    final measure = l10n.foodAiMeasure(item.measure.name);
    final line = removed
        ? l10n.foodAiItemRemoved
        : l10n.foodAiItemLine(count, measure, item.grams);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [BodyText(item.name), CaptionText(line)],
          ),
        ),
        IconButton(
          key: MealItemsKeys.less(item.id),
          tooltip: l10n.foodAiItemLess(item.name),
          icon: const Icon(Icons.remove_rounded),
          onPressed: removed ? null : () => onStep(-1),
        ),
        Text(removed ? '0' : count),
        IconButton(
          key: MealItemsKeys.more(item.id),
          tooltip: l10n.foodAiItemMore(item.name),
          icon: const Icon(Icons.add_rounded),
          onPressed: removed || countX2 >= _maxCountX2 ? null : () => onStep(1),
        ),
      ],
    );
  }
}
