import 'dart:convert';

import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';

/// Demo mode model: answers from the request itself, with no network call.
final class SampleAnalysisModel implements AnalysisModel {
  const new(this.factId);

  final String? factId;

  static const String summary = 'Sample. No model was called.';

  @override
  Stream<AnalysisEvent> generate(
    AnalysisRequest request, {
    required Future<void> cancel,
  }) async* {
    final id = factId;
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
  Future<ConnectionProbe> probe({
    Future<void>? cancel,
    void Function()? onReached,
  }) => throw UnsupportedError('demo');
}
