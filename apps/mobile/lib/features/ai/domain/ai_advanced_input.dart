import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';

const int aiMaxCurrencyChars = 8;
final _digits = RegExp(r'^\d+$');
final _decimal = RegExp(r'^\d+([.,]\d+)?$');

/// A parsed optional field: a null result is invalid input, while a result
/// whose value is null is an empty field that clears the setting.
typedef AiOptional<T> = ({T? value});

int? parseAiOutputTokens(String raw) {
  final value = _positiveInt(raw.trim());
  if (value == null) return null;
  if (value < aiMinOutputTokens || value > aiMaxOutputTokens) return null;
  return value;
}

AiOptional<int>? parseAiTokenCap(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return (value: null);
  final value = _positiveInt(trimmed);
  if (value == null) return null;
  return (value: value);
}

AiOptional<double>? parseAiPrice(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return (value: null);
  if (!_decimal.hasMatch(trimmed)) return null;
  final value = double.tryParse(trimmed.replaceAll(',', '.'));
  if (value == null || !value.isFinite || value <= 0) return null;
  return (value: value);
}

String? parseAiCurrency(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.runes.length > aiMaxCurrencyChars) {
    return null;
  }
  return trimmed;
}

String formatAiPrice(double? value) {
  if (value == null) return '';
  if (value == value.truncateToDouble()) return value.toInt().toString();
  return value.toString();
}

int? _positiveInt(String text) {
  if (!_digits.hasMatch(text)) return null;
  final value = int.tryParse(text);
  if (value == null || value <= 0) return null;
  return value;
}

/// Forced modes replace what the ladder found; auto keeps the stored
/// profile, so a ladder step down still applies on the next run.
AiCapabilityProfile applyAiOutputModes(
  AiConfig config,
  AiCapabilityProfile profile,
) {
  final json = switch (config.structuredOutputMode) {
    AiStructuredOutputMode.auto => profile.jsonMode,
    AiStructuredOutputMode.jsonSchema => AiJsonMode.jsonSchema,
    AiStructuredOutputMode.jsonObject => AiJsonMode.jsonObject,
    AiStructuredOutputMode.off => AiJsonMode.none,
  };
  final stream =
      config.streamingMode == AiStreamingMode.auto && profile.streamOk;
  return profile.copyWith(jsonMode: json, streamOk: stream);
}
