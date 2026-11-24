import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/openai_wire_codec.dart';
import 'package:open_ring/features/ai/domain/vision_probe.dart';

const _grid = VisionProbeGrid([
  VisionProbeColor.red,
  VisionProbeColor.yellow,
  VisionProbeColor.blue,
  VisionProbeColor.red,
]);

final Matcher isUnreadable = equals(VisionProbeResult.unreadable);

String _answer(List<String> colours) => jsonEncode({
  for (var i = 0; i < 4; i++) visionProbeCellNames[i]: colours[i],
});

void main() {
  group('probe image', () {
    test('decodes to 96 x 96 with every cell centre near its colour', () {
      final decoded = img.decodeJpg(encodeProbeJpeg(_grid))!;

      expect((decoded.width, decoded.height), (96, 96));
      const centres = [(24, 24), (72, 24), (24, 72), (72, 72)];
      for (var i = 0; i < 4; i++) {
        final (x, y) = centres[i];
        final pixel = decoded.getPixel(x, y);
        final want = _grid.cells[i];
        expect((pixel.r - want.r).abs(), lessThanOrEqualTo(24), reason: '$i r');
        expect((pixel.g - want.g).abs(), lessThanOrEqualTo(24), reason: '$i g');
        expect((pixel.b - want.b).abs(), lessThanOrEqualTo(24), reason: '$i b');
      }
    });

    test('the same seed gives the same grid', () {
      expect(
        VisionProbeGrid.random(Random(7)),
        VisionProbeGrid.random(Random(7)),
      );
    });

    test('cells are drawn with replacement from four colours', () {
      final random = Random(1);
      final seen = <VisionProbeColor>{};
      var repeats = 0;
      for (var i = 0; i < 200; i++) {
        final cells = VisionProbeGrid.random(random).cells;
        seen.addAll(cells);
        if (cells.toSet().length < 4) repeats++;
      }
      expect(seen, VisionProbeColor.values.toSet());
      expect(repeats, greaterThan(0));
    });
  });

  group('probe request', () {
    test('four required enum cells, non streaming, own schema name', () {
      final request = visionProbeRequest(_grid, maxOutputTokens: 300);

      final schema = request.jsonSchema!;
      final properties = schema['properties']! as Map<String, Object?>;
      expect(properties.keys, visionProbeCellNames);
      expect(schema['required'], visionProbeCellNames);
      expect(schema['additionalProperties'], isFalse);
      for (final cell in properties.values) {
        expect((cell! as Map<String, Object?>)['enum'], [
          'red',
          'green',
          'blue',
          'yellow',
        ]);
      }
      expect(request.stream, isFalse);
      expect(request.schemaName, visionProbeSchemaName);
      final content = request.userContent as AiImageContent;
      final sent = img.decodeJpg(base64Decode(content.base64Jpeg))!;
      expect(sent.width, visionProbeSize);
    });
  });

  group('readVisionProbe', () {
    test('all four right passes, fences and think blocks included', () {
      final text =
          '<think>squares</think>```json\n'
          '${_answer(['red', 'yellow', 'blue', 'RED'])}\n```';

      expect(readVisionProbe(text, _grid), VisionProbeResult.pass);
    });

    test('one wrong cell fails', () {
      final text = _answer(['red', 'yellow', 'green', 'red']);

      expect(readVisionProbe(text, _grid), VisionProbeResult.fail);
    });

    test('a colour outside the list fails', () {
      final text = _answer(['red', 'yellow', 'purple', 'red']);

      expect(readVisionProbe(text, _grid), VisionProbeResult.fail);
    });

    test('no JSON, a missing cell or a non string is unreadable', () {
      expect(readVisionProbe('I see squares', _grid), isUnreadable);
      expect(
        readVisionProbe('{"top_left":"red","top_right":"yellow"}', _grid),
        isUnreadable,
      );
      expect(
        readVisionProbe(
          '{"top_left":1,"top_right":"yellow","bottom_left":"blue",'
          '"bottom_right":"red"}',
          _grid,
        ),
        isUnreadable,
      );
    });
  });

  group('no vision refusal', () {
    AnalysisFailure badRequest(String detail) => AnalysisFailure(
      kind: AnalysisFailureKind.badRequest,
      statusCode: 400,
      detail: detail,
    );

    for (final detail in [
      'Model does not support image input',
      'Invalid content type: image_url',
      'This model has no Vision capability',
      'multimodal input is not enabled',
    ]) {
      test('"$detail" stops the ladder and counts as no vision', () {
        expect(AiCapabilityProfile.defaults.nextOnBadRequest(detail), isNull);
        expect(isNoVisionFailure(badRequest(detail)), isTrue);
      });
    }

    test('a content or stream message still walks the ladder', () {
      for (final detail in ['invalid content', 'stream not supported']) {
        expect(
          AiCapabilityProfile.defaults.nextOnBadRequest(detail),
          isNotNull,
        );
        expect(isNoVisionFailure(badRequest(detail)), isFalse);
      }
    });

    test('only a 400 bad request counts', () {
      const server = AnalysisFailure(
        kind: AnalysisFailureKind.serverError,
        statusCode: 500,
        detail: 'image decoder crashed',
      );
      expect(isNoVisionFailure(server), isFalse);
    });
  });
}
