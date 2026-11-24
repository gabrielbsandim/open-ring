import 'dart:convert';

import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/openai_wire_codec.dart';

/// Demo mode model: answers from the request itself, with no network call.
final class SampleAnalysisModel implements AnalysisModel {
  const new();

  static const String summary = 'Sample. No model was called.';

  @override
  Stream<AnalysisEvent> generate(
    AnalysisRequest request, {
    required Future<void> cancel,
  }) async* {
    final id = _firstFactId(request.userContent);
    final text = jsonEncode({
      'summary': summary,
      'cards': [
        if (id != null)
          {
            'family': 'overall',
            'title': 'Sample card',
            'insight':
                'This card shows where an insight from your model appears.',
            'evidence': [id],
            'action': 'Add your own model in Settings to analyze your data.',
            'confidence': 'low',
          },
      ],
    });
    yield AnalysisProgress(text.length);
    yield AnalysisCompleted(text: text, finishReason: 'stop');
  }

  @override
  Future<List<String>> listModels() async => const [];

  @override
  Future<ConnectionProbe> probe() async => const ConnectionProbe(
    profile: AiCapabilityProfile.defaults,
    latency: Duration.zero,
  );

  static String? _firstFactId(AiUserContent content) {
    if (content is! AiTextContent) return null;
    final start = content.text.indexOf('DATA:\n');
    if (start < 0) return null;
    final data = jsonDecode(content.text.substring(start + 6));
    final facts = data is Map<String, Object?> ? data['facts'] : null;
    if (facts is! List<Object?> || facts.isEmpty) return null;
    final first = facts.first;
    return first is Map<String, Object?> ? first['id'] as String? : null;
  }
}
