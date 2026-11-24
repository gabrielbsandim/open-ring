import 'package:meta/meta.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/openai_wire_codec.dart';

@immutable
final class AnalysisRequest {
  const new({
    required this.systemPrompt,
    required this.userContent,
    required this.maxOutputTokens,
    this.profile = AiCapabilityProfile.defaults,
    this.jsonSchema,
    this.reasoningEffort,
    this.pin = AiOutputPin.none,
  });

  final String systemPrompt;
  final AiUserContent userContent;
  final int maxOutputTokens;
  final AiCapabilityProfile profile;
  final Map<String, Object?>? jsonSchema;
  final AiReasoningEffort? reasoningEffort;
  final AiOutputPin pin;
}

@immutable
final class ConnectionProbe {
  const new({
    required this.profile,
    required this.latency,
    this.models,
    this.usage,
  });

  final AiCapabilityProfile profile;
  final Duration latency;

  /// Null when the server has no model list (404 or 405).
  final List<String>? models;
  final AiTokenUsage? usage;
}

abstract interface class AnalysisModel {
  Stream<AnalysisEvent> generate(
    AnalysisRequest request, {
    required Future<void> cancel,
  });
  Future<List<String>> listModels();

  /// [onReached] fires once the model list answered or was tolerated as
  /// missing, before the fixed sentence is sent.
  Future<ConnectionProbe> probe({
    Future<void>? cancel,
    void Function()? onReached,
  });
}
