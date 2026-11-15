import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';

abstract final class WeighInSheetKeys {
  static const weight = Key('weigh_in_weight');
  static const decrease = Key('weigh_in_decrease');
  static const increase = Key('weigh_in_increase');
  static const when = Key('weigh_in_when');
  static const more = Key('weigh_in_more');
  static const bodyFat = Key('weigh_in_body_fat');
  static const waist = Key('weigh_in_waist');
  static const error = Key('weigh_in_error');
  static const hidden = Key('weigh_in_hidden');
  static const save = Key('weigh_in_save');
}

const _stepsPerUnit = 10;
const _earliestYearsBack = 10;

Future<void> showWeighInSheet(BuildContext context, {WeighIn? editing}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.of(context).surface,
      builder: (context) => SafeArea(child: WeighInSheet(editing: editing)),
    );

double? _parsed(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  return double.tryParse(trimmed.replaceAll(',', '.')) ?? double.nan;
}

class WeighInSheet extends ConsumerStatefulWidget {
  const new({this.editing, super.key});

  final WeighIn? editing;

  @override
  ConsumerState<WeighInSheet> createState() => _WeighInSheetState();
}

class _WeighInSheetState extends ConsumerState<WeighInSheet> {
  final _weight = TextEditingController();
  final _bodyFat = TextEditingController();
  final _waist = TextEditingController();
  DateTime? _at;
  String? _error;
  bool _saving = false;
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    if (ref.read(numbersHiddenProvider)) return;
    final units = UnitFormat(
      MetricFormat.of(context),
      ref.read(currentUnitSystemProvider),
    );
    final seed =
        widget.editing ?? ref.read(weighInsProvider).value?.firstOrNull;
    if (seed == null) return;
    _weight.text = units.bodyWeightNumber(seed.kilograms);
    final bodyFat = widget.editing?.bodyFatPercent;
    final waist = widget.editing?.waistCentimeters;
    if (bodyFat != null) _bodyFat.text = _oneDecimal(units, bodyFat);
    if (waist != null) _waist.text = _oneDecimal(units, units.waistIn(waist));
  }

  String _oneDecimal(UnitFormat units, double value) =>
      units.format.decimal(value, digits: 1);

  @override
  void dispose() {
    _weight.dispose();
    _bodyFat.dispose();
    _waist.dispose();
    super.dispose();
  }

  void _step(int direction) {
    final value = _parsed(_weight.text);
    if (value == null || !value.isFinite) return;
    final next = ((value * _stepsPerUnit).round() + direction) / _stepsPerUnit;
    setState(() {
      _weight.text = MetricFormat.of(context).decimal(next, digits: 1);
      _error = null;
    });
  }

  Future<void> _pickWhen() async {
    final now = ref.read(clockProvider)();
    final current = _at ?? widget.editing?.at.toLocal() ?? now;
    final day = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year - _earliestYearsBack),
      lastDate: now,
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    setState(() {
      _at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
      _error = null;
    });
  }

  void _fail(String message) => setState(() {
    _error = message;
    _saving = false;
  });

  Future<void> _save(UnitFormat units, {required bool hidden}) async {
    if (_saving) return;
    final l10n = units.l10n;
    final editing = widget.editing;
    // With numbers hidden the fields open blank, so a blank field keeps the
    // value the weigh-in already has.
    final kept = hidden ? editing : null;
    final weight = _parsed(_weight.text);
    final kilograms = weight == null
        ? kept?.kilograms
        : units.kilogramsFrom(weight);
    if (kilograms == null) {
      _fail(l10n.bodySheetErrorWeightEmpty);
      return;
    }
    final picked = _at;
    final at = picked ?? editing?.at ?? ref.read(clockProvider)();
    final waist = _parsed(_waist.text);
    // An edit that leaves the time alone keeps the offset it was logged with,
    // so the weigh-in stays on the same local day.
    final keepsOffset = picked == null && editing != null;
    final draft = WeighInDraft(
      at: at,
      offsetMinutes: keepsOffset
          ? editing.offsetMinutes
          : at.timeZoneOffset.inMinutes,
      source: editing?.source ?? WeighInSource.manual,
      kilograms: kilograms,
      bodyFatPercent: _parsed(_bodyFat.text) ?? kept?.bodyFatPercent,
      waistCentimeters: waist == null
          ? kept?.waistCentimeters
          : units.centimetersFrom(waist),
    );
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final issues = await _store(draft);
    if (!mounted) return;
    if (issues == null) {
      _fail(l10n.bodySheetSaveFailed);
      return;
    }
    if (issues.isNotEmpty) {
      _fail(_message(units, issues.first));
      return;
    }
    navigator.pop();
    final saved = units.bodyWeight(roundKilograms(draft.kilograms));
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch ((hidden, editing == null)) {
          (true, true) => l10n.bodySheetSavedHidden,
          (true, false) => l10n.bodySheetUpdatedHidden,
          (false, true) => l10n.bodySheetSaved(saved),
          (false, false) => l10n.bodySheetUpdated(saved),
        }),
      ),
    );
  }

  Future<Set<WeighInIssue>?> _store(WeighInDraft draft) async {
    final log = ref.read(weighInLogProvider.notifier);
    final editing = widget.editing;
    try {
      if (editing == null) return await log.add(draft);
      return await log.update(editing.id, draft);
    } on Exception {
      return null;
    }
  }

  String _message(UnitFormat units, WeighInIssue issue) {
    final l10n = units.l10n;
    final whole = units.format.integer;
    return switch (issue) {
      WeighInIssue.kilograms => l10n.bodySheetErrorWeight(
        whole(units.bodyWeightIn(weighInKilogramsRange.min).ceil()),
        whole(units.bodyWeightIn(weighInKilogramsRange.max).floor()),
        units.weightUnit,
      ),
      WeighInIssue.bodyFat => l10n.bodySheetErrorBodyFat(
        whole(weighInBodyFatRange.min),
        whole(weighInBodyFatRange.max),
      ),
      WeighInIssue.waist => l10n.bodySheetErrorWaist(
        whole(units.waistIn(weighInWaistRange.min).ceil()),
        whole(units.waistIn(weighInWaistRange.max).floor()),
        units.waistUnit,
      ),
      WeighInIssue.future => l10n.bodySheetErrorFuture,
    };
  }

  String _whenText(UnitFormat units, DateTime? picked, WeighIn? editing) {
    if (picked != null) {
      return units.format.dayAndClock(picked, picked.timeZoneOffset);
    }
    if (editing == null) return units.l10n.bodySheetNow;
    return units.format.dayAndClock(
      editing.at,
      Duration(minutes: editing.offsetMinutes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final units = UnitFormat.of(context, ref);
    final l10n = units.l10n;
    final editing = widget.editing;
    final hidden = ref.watch(numbersHiddenProvider);
    final at = _at;
    final error = _error;
    final step = '${units.format.decimal(0.1, digits: 1)} ${units.weightUnit}';
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              editing == null ? l10n.bodyWeightLog : l10n.bodySheetEditTitle,
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton.outlined(
                key: WeighInSheetKeys.decrease,
                tooltip: l10n.bodySheetDecrease(step),
                onPressed: () => _step(-1),
                icon: const Icon(Icons.remove_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumberField(
                  key: WeighInSheetKeys.weight,
                  controller: _weight,
                  label: l10n.profileWeight,
                  unit: units.weightUnit,
                  textAlign: TextAlign.center,
                  style: numberStyle(theme.textTheme.headlineMedium),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.outlined(
                key: WeighInSheetKeys.increase,
                tooltip: l10n.bodySheetIncrease(step),
                onPressed: () => _step(1),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          if (error == null && hidden) ...[
            const SizedBox(height: 8),
            CaptionText(
              key: WeighInSheetKeys.hidden,
              editing == null
                  ? l10n.bodySheetHiddenNew
                  : l10n.bodySheetHiddenEdit,
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: CaptionText(
                key: WeighInSheetKeys.error,
                error,
                color: colors.heart,
              ),
            ),
          ],
          const SizedBox(height: 8),
          ListTile(
            key: WeighInSheetKeys.when,
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.bodySheetWhen),
            subtitle: Text(_whenText(units, at, editing)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _pickWhen,
          ),
          ExpansionTile(
            key: WeighInSheetKeys.more,
            initiallyExpanded:
                !hidden &&
                (editing?.bodyFatPercent != null ||
                    editing?.waistCentimeters != null),
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text(l10n.bodySheetMore),
            subtitle: Text(l10n.bodySheetMoreDetail),
            children: [
              _NumberField(
                key: WeighInSheetKeys.bodyFat,
                controller: _bodyFat,
                label: l10n.bodySheetBodyFat,
                unit: '%',
              ),
              const SizedBox(height: 12),
              _NumberField(
                key: WeighInSheetKeys.waist,
                controller: _waist,
                label: l10n.bodySheetWaist,
                unit: units.waistUnit,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ActionButton(
            key: WeighInSheetKeys.save,
            label: l10n.workoutSave,
            onPressed: _saving ? null : () => _save(units, hidden: hidden),
          ),
          const SizedBox(height: 10),
          CaptionText(
            l10n.bodySheetUnitNote(units.weightUnit),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const new({
    required this.controller,
    required this.label,
    required this.unit,
    this.textAlign = TextAlign.start,
    this.style,
    super.key,
  });

  static const _maxLength = 5;

  final TextEditingController controller;
  final String label;
  final String unit;
  final TextAlign textAlign;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textAlign: textAlign,
      style: style,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
        LengthLimitingTextInputFormatter(_maxLength),
      ],
      decoration: InputDecoration(labelText: label, suffixText: unit),
    );
  }
}
