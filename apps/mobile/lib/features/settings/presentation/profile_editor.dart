import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

enum ProfileField { age, sex, height, weight, maxHeartRate, stepGoal }

typedef IntRange = ({int min, int max});

const _keep = Object();

UserProfile editProfile(
  UserProfile? profile, {
  Object? birthYear = _keep,
  Object? sex = _keep,
  Object? heightCentimeters = _keep,
  Object? weightKilograms = _keep,
  Object? maxHeartRate = _keep,
  Object? dailyStepGoal = _keep,
}) {
  final base = profile ?? const UserProfile();
  return UserProfile(
    birthYear: identical(birthYear, _keep) ? base.birthYear : birthYear as int?,
    sex: identical(sex, _keep) ? base.sex : sex as Sex?,
    heightCentimeters: identical(heightCentimeters, _keep)
        ? base.heightCentimeters
        : heightCentimeters as double?,
    weightKilograms: identical(weightKilograms, _keep)
        ? base.weightKilograms
        : weightKilograms as double?,
    maxHeartRate: identical(maxHeartRate, _keep)
        ? base.maxHeartRate
        : maxHeartRate as int?,
    dailyStepGoal: identical(dailyStepGoal, _keep)
        ? base.dailyStepGoal
        : dailyStepGoal as int?,
  );
}

@immutable
final class NumberEdit {
  const new(this.value);

  final double? value;
}

abstract final class ProfileEditorKeys {
  static const field = Key('profile_editor_field');
  static const save = Key('profile_editor_save');
  static const clear = Key('profile_editor_clear');
  static const cancel = Key('profile_editor_cancel');

  static Key sex(Sex? sex) => Key('profile_editor_sex_${sex?.name ?? 'none'}');
}

Future<NumberEdit?> showNumberEditor(
  BuildContext context, {
  required String title,
  required String unit,
  required double? initial,
  required IntRange range,
  bool decimal = false,
}) => showDialog<NumberEdit>(
  context: context,
  builder: (_) => _NumberDialog(
    title: title,
    unit: unit,
    initial: initial,
    range: range,
    decimal: decimal,
  ),
);

Future<({Sex? sex})?> showSexEditor(BuildContext context, Sex? current) {
  final l10n = AppLocalizations.of(context);
  final options = <(Sex?, String)>[
    (Sex.female, l10n.profileSexFemale),
    (Sex.male, l10n.profileSexMale),
    (null, l10n.profileSexUnspecified),
  ];
  return showDialog<({Sex? sex})>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(l10n.profileSex),
      children: [
        for (final (sex, label) in options)
          SimpleDialogOption(
            key: ProfileEditorKeys.sex(sex),
            onPressed: () => Navigator.pop(dialogContext, (sex: sex)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  Icon(
                    sex == current
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label)),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _NumberDialog extends StatefulWidget {
  const new({
    required this.title,
    required this.unit,
    required this.initial,
    required this.range,
    required this.decimal,
  });

  final String title;
  final String unit;
  final double? initial;
  final IntRange range;
  final bool decimal;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final _controller = TextEditingController(text: _text(widget.initial));
  String? _error;

  static String _text(double? value) => switch (value) {
    null => '',
    final v when v == v.roundToDouble() => '${v.round()}',
    final v => v.toStringAsFixed(1),
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    final range = widget.range;
    if (value == null || value < range.min || value > range.max) {
      setState(
        () =>
            _error = AppLocalizations.of(context)
                .profileRangeError(range.min, range.max),
      );
      return;
    }
    Navigator.pop(context, NumberEdit(value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: TextField(
        key: ProfileEditorKeys.field,
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            widget.decimal ? RegExp('[0-9.,]') : RegExp('[0-9]'),
          ),
        ],
        decoration: InputDecoration(
          suffixText: widget.unit,
          errorText: _error,
          errorMaxLines: 3,
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          key: ProfileEditorKeys.clear,
          onPressed: () => Navigator.pop(context, const NumberEdit(null)),
          child: Text(l10n.settingsClear),
        ),
        TextButton(
          key: ProfileEditorKeys.cancel,
          onPressed: () => Navigator.pop(context),
          child: Text(material.cancelButtonLabel),
        ),
        TextButton(
          key: ProfileEditorKeys.save,
          onPressed: _save,
          child: Text(material.saveButtonLabel),
        ),
      ],
    );
  }
}
