import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:meta/meta.dart';
import 'package:open_ring/features/ai/domain/ai_output_extractor.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/openai_wire_codec.dart';

const int visionProbeSize = 96;
const int visionProbeCell = 48;
const String visionProbeSchemaName = 'openring_vision_probe';

const String visionProbeSystemPrompt =
    'You are a vision test. Look at the image and answer with JSON only.';

enum VisionProbeColor {
  red(255, 0, 0),
  green(0, 255, 0),
  blue(0, 0, 255),
  yellow(255, 255, 0);

  new(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;
}

/// Cell names in reading order, as the schema properties.
const List<String> visionProbeCellNames = [
  'top_left',
  'top_right',
  'bottom_left',
  'bottom_right',
];

/// Four cells drawn with replacement, so a blind guess passes 1 time in 256.
@immutable
final class VisionProbeGrid {
  const new(this.cells);

  factory random(Random random) => VisionProbeGrid([
    for (var i = 0; i < 4; i++)
      VisionProbeColor.values[random.nextInt(VisionProbeColor.values.length)],
  ]);

  final List<VisionProbeColor> cells;

  @override
  bool operator ==(Object other) =>
      other is VisionProbeGrid &&
      Iterable<int>.generate(4).every((i) => other.cells[i] == cells[i]);

  @override
  int get hashCode => Object.hashAll(cells);
}

enum VisionProbeResult { pass, fail, unreadable }

Uint8List encodeProbeJpeg(VisionProbeGrid grid) {
  final image = img.Image(width: visionProbeSize, height: visionProbeSize);
  for (var i = 0; i < 4; i++) {
    final color = grid.cells[i];
    final x = (i % 2) * visionProbeCell;
    final y = (i ~/ 2) * visionProbeCell;
    img.fillRect(
      image,
      x1: x,
      y1: y,
      x2: x + visionProbeCell - 1,
      y2: y + visionProbeCell - 1,
      color: img.ColorRgb8(color.r, color.g, color.b),
    );
  }
  return img.encodeJpg(image, quality: 90);
}

final Map<String, Object?> visionProbeSchema = {
  'type': 'object',
  'properties': {
    for (final name in visionProbeCellNames)
      name: {
        'type': 'string',
        'enum': [for (final c in VisionProbeColor.values) c.name],
      },
  },
  'required': visionProbeCellNames,
  'additionalProperties': false,
};

AnalysisRequest visionProbeRequest(
  VisionProbeGrid grid, {
  required int maxOutputTokens,
  AiCapabilityProfile profile = AiCapabilityProfile.defaults,
  AiOutputPin pin = AiOutputPin.none,
}) => AnalysisRequest(
  systemPrompt: visionProbeSystemPrompt,
  userContent: AiImageContent(
    text:
        'The image is a 2 x 2 grid of coloured squares. Name the colour of '
        'each square.\nOutput schema:\n'
        '${canonicalJsonEncode(visionProbeSchema)}',
    base64Jpeg: base64Encode(encodeProbeJpeg(grid)),
  ),
  maxOutputTokens: maxOutputTokens,
  profile: profile,
  jsonSchema: visionProbeSchema,
  pin: pin,
  schemaName: visionProbeSchemaName,
  stream: false,
);

/// A pass needs all four cells right. A colour outside the list counts as a
/// wrong answer, since only a model that answered at all can name one.
VisionProbeResult readVisionProbe(String text, VisionProbeGrid grid) {
  final answer = _decode(text);
  if (answer == null) return VisionProbeResult.unreadable;
  final named = [for (final name in visionProbeCellNames) answer[name]];
  if (named.any((value) => value is! String)) {
    return VisionProbeResult.unreadable;
  }
  for (var i = 0; i < 4; i++) {
    final said = (named[i]! as String).trim().toLowerCase();
    if (said != grid.cells[i].name) return VisionProbeResult.fail;
  }
  return VisionProbeResult.pass;
}

Map<String, Object?>? _decode(String text) {
  final json = AiOutputExtractor.extractFirstJsonObject(
    OpenAiWireCodec.stripThinkBlocks(text),
  );
  if (json == null) return null;
  try {
    final decoded = jsonDecode(json);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}
