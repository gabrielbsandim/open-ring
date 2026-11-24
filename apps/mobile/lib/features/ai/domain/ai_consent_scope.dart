import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';

/// Read from the built payload itself, so a category counts only when its
/// data really leaves the phone.
Set<AiDataCategory> aiPayloadCategories(Map<String, Object?> context) {
  final days = context['days'];
  final coverage = context['coverage'];
  final weightDays =
      days is Map && days.keys.any((k) => '$k'.startsWith('weight'));
  return {
    if (context.containsKey('weigh_ins') || weightDays) AiDataCategory.body,
    if (context.containsKey('energy')) AiDataCategory.energy,
    if (context.containsKey('goal') || context.containsKey('plan'))
      AiDataCategory.goals,
    if (context.containsKey('food')) AiDataCategory.food,
    if (coverage is Map && coverage['imported_included'] == true)
      AiDataCategory.imported,
  };
}

bool aiConsentCoversPayload(
  AiConsent? consent,
  AiConfig config,
  BuiltAiPayload payload,
) {
  final hostKey = config.hostKey;
  if (consent == null || hostKey == null) return false;
  return consent.covers(
    hostKey: hostKey,
    detailLevel: config.detailLevel,
    contextSchemaVersion: aiContextSchemaVersion,
    policyEffectiveDate: aiCurrentPolicyEffectiveDate,
    categories: aiPayloadCategories(payload.contextMap),
  );
}

/// Categories in [payload] that a same host [previous] consent did not list.
Set<AiDataCategory> aiNewCategories(
  AiConsent? previous,
  AiConfig config,
  BuiltAiPayload payload,
) {
  if (previous == null || previous.hostKey != config.hostKey) return const {};
  return aiPayloadCategories(payload.contextMap)
      .difference(previous.categories);
}

AiConsent aiConsentFor({
  required AiConfig config,
  required BuiltAiPayload payload,
  required AiConsent? previous,
  required DateTime at,
}) {
  final valid =
      previous != null &&
      previous.hostKey == config.hostKey &&
      previous.policyEffectiveDate == aiCurrentPolicyEffectiveDate &&
      previous.contextSchemaVersion == aiContextSchemaVersion;
  final kept = valid ? previous.categories : const <AiDataCategory>{};
  return AiConsent(
    consentedAtUtcMs: at.toUtc().millisecondsSinceEpoch,
    policyEffectiveDate: aiCurrentPolicyEffectiveDate,
    hostKey: config.hostKey!,
    detailLevel: config.detailLevel,
    contextSchemaVersion: aiContextSchemaVersion,
    categories: {...kept, ...aiPayloadCategories(payload.contextMap)},
  );
}
