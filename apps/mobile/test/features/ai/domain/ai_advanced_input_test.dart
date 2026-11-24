import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_advanced_input.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';

void main() {
  group('max output tokens', () {
    test('accepts whole numbers inside the spec range', () {
      expect(parseAiOutputTokens('256'), 256);
      expect(parseAiOutputTokens(' 4000 '), 4000);
      expect(parseAiOutputTokens('32000'), 32000);
    });

    test('rejects anything else', () {
      for (final raw in [
        '',
        '0',
        '-5',
        '255',
        '32001',
        '4.5',
        '4,000',
        'abc',
      ]) {
        expect(parseAiOutputTokens(raw), isNull, reason: raw);
      }
    });
  });

  group('monthly token cap', () {
    test('empty is valid and means no cap', () {
      expect(parseAiTokenCap(''), (value: null));
      expect(parseAiTokenCap('   '), (value: null));
    });

    test('accepts a positive whole number', () {
      expect(parseAiTokenCap('200000'), (value: 200000));
    });

    test('rejects zero, negatives, decimals and text', () {
      for (final raw in ['0', '-1', '1.5', '1e5', 'ten']) {
        expect(parseAiTokenCap(raw), isNull, reason: raw);
      }
    });
  });

  group('price', () {
    test('empty is valid and means no price', () {
      expect(parseAiPrice(''), (value: null));
    });

    test('accepts a dot or a comma as the decimal mark', () {
      expect(parseAiPrice('0.15'), (value: 0.15));
      expect(parseAiPrice('2,5'), (value: 2.5));
      expect(parseAiPrice('3'), (value: 3.0));
    });

    test('rejects zero, negatives and text', () {
      for (final raw in ['0', '0.0', '-1', '1e3', 'NaN', 'Infinity', '1.2.3']) {
        expect(parseAiPrice(raw), isNull, reason: raw);
      }
    });

    test('formats a stored price back into the field', () {
      expect(formatAiPrice(null), '');
      expect(formatAiPrice(3), '3');
      expect(formatAiPrice(0.15), '0.15');
    });
  });

  test('currency must be a short non empty label', () {
    expect(parseAiCurrency(' EUR '), 'EUR');
    expect(parseAiCurrency(''), isNull);
    expect(parseAiCurrency('123456789'), isNull);
  });

  group('output modes', () {
    const ladder = AiCapabilityProfile(jsonMode: AiJsonMode.jsonObject);

    test('auto keeps what the ladder found', () {
      final out = applyAiOutputModes(AiConfig.defaults, ladder);
      expect(out, ladder);
    });

    test('auto streaming keeps a ladder that turned streaming off', () {
      final out = applyAiOutputModes(
        AiConfig.defaults,
        ladder.copyWith(streamOk: false),
      );
      expect(out.streamOk, isFalse);
    });

    test('a forced mode replaces the ladder step', () {
      const cases = {
        AiStructuredOutputMode.jsonSchema: AiJsonMode.jsonSchema,
        AiStructuredOutputMode.jsonObject: AiJsonMode.jsonObject,
        AiStructuredOutputMode.off: AiJsonMode.none,
      };
      cases.forEach((mode, json) {
        final config = AiConfig.defaults.copyWith(structuredOutputMode: mode);
        expect(applyAiOutputModes(config, ladder).jsonMode, json);
      });
    });

    test('streaming off turns streaming off', () {
      final config = AiConfig.defaults.copyWith(
        streamingMode: AiStreamingMode.off,
      );
      expect(applyAiOutputModes(config, ladder).streamOk, isFalse);
    });
  });
}
