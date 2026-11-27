import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_consent_scope.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';

BuiltAiPayload _payload(Map<String, Object?> context) => BuiltAiPayload(
  contextMap: context,
  canonicalContextJson: '{}',
  systemPrompt: 's',
  userMessage: 'u',
  facts: const [],
  estimatedTokens: 1,
  contextTokens: 1,
  cacheKey: 'k',
  droppedCount: 0,
);

const _config = AiConfig(baseUrl: 'https://api.example.com/v1', model: 'm');
const _host = 'https://api.example.com:443';

AiConsent _consent({
  String host = _host,
  Set<AiDataCategory> categories = const {},
  String policy = aiCurrentPolicyEffectiveDate,
  String schema = aiContextSchemaVersion,
}) => AiConsent(
  consentedAtUtcMs: 1,
  policyEffectiveDate: policy,
  hostKey: host,
  detailLevel: AiDetailLevel.standard,
  contextSchemaVersion: schema,
  categories: categories,
);

void main() {
  group('aiPayloadCategories', () {
    test('a core payload has no optional category', () {
      expect(
        aiPayloadCategories({
          'days': {
            'd': ['D0'],
            'sleep_min': [400],
          },
          'workouts': <Object?>[],
          'coverage': {'imported_included': false},
        }),
        isEmpty,
      );
    });

    test('each optional section maps to its category', () {
      expect(
        aiPayloadCategories({
          'weigh_ins': {'n30': 4},
          'energy': {'bmr_kcal': 1700},
          'plan': <Object?>[],
          'food': {'complete_days': 3},
          'coverage': {'imported_included': true},
        }),
        AiDataCategory.values.toSet(),
      );
    });

    test('a weight column alone counts as body data', () {
      expect(
        aiPayloadCategories({
          'days': {
            'weight_delta': [0, 0.2],
          },
        }),
        {AiDataCategory.body},
      );
    });
  });

  group('consent rules', () {
    test('categories round trip through JSON, unknown names dropped', () {
      final consent = _consent(
        categories: {AiDataCategory.food, AiDataCategory.goals},
      );
      final json = consent.toJson();
      expect(json['categories'], ['goals', 'food']);
      expect(AiConsent.tryFromJson(json), consent);
      expect(
        AiConsent.tryFromJson({
          ...json,
          'categories': ['food', 'gps'],
        })!.categories,
        {AiDataCategory.food},
      );
    });

    test('a stored consent without categories still loads, covering none', () {
      final json = _consent().toJson()..remove('categories');
      final consent = AiConsent.tryFromJson(json)!;
      expect(consent.categories, isEmpty);
      expect(
        aiConsentCoversPayload(consent, _config, _payload({'food': {}})),
        isFalse,
      );
    });

    test('covers only the categories it lists', () {
      final payload = _payload({'food': {}, 'goal': {}});
      expect(
        aiConsentCoversPayload(
          _consent(categories: {AiDataCategory.food}),
          _config,
          payload,
        ),
        isFalse,
      );
      expect(
        aiConsentCoversPayload(
          _consent(categories: {AiDataCategory.food, AiDataCategory.goals}),
          _config,
          payload,
        ),
        isTrue,
      );
    });

    test('new categories are listed only against the same host', () {
      final payload = _payload({'food': {}, 'goal': {}});
      final previous = _consent(categories: {AiDataCategory.food});
      expect(aiNewCategories(previous, _config, payload), {
        AiDataCategory.goals,
      });
      expect(
        aiNewCategories(
          _consent(host: 'https://x.example:443'),
          _config,
          payload,
        ),
        isEmpty,
      );
      expect(aiNewCategories(null, _config, payload), isEmpty);
    });

    test('a granted consent keeps earlier categories of the same host', () {
      final at = DateTime.utc(2026, 11, 24, 9);
      final consent = aiConsentFor(
        config: _config.copyWith(detailLevel: AiDetailLevel.full),
        payload: _payload({'goal': {}}),
        previous: _consent(categories: {AiDataCategory.food}),
        at: at,
      );
      expect(consent.hostKey, _host);
      expect(consent.detailLevel, AiDetailLevel.full);
      expect(consent.categories, {AiDataCategory.food, AiDataCategory.goals});
      expect(consent.consentedAtUtcMs, at.millisecondsSinceEpoch);
      final moved = aiConsentFor(
        config: _config,
        payload: _payload({}),
        previous: _consent(
          host: 'https://x.example:443',
          categories: {AiDataCategory.food},
        ),
        at: at,
      );
      expect(moved.categories, isEmpty);
    });

    test('categories of an outdated policy or schema are dropped', () {
      final at = DateTime.utc(2026, 11, 24, 9);
      for (final previous in [
        _consent(categories: {AiDataCategory.food}, policy: '2026-01-01'),
        _consent(
          categories: {AiDataCategory.food},
          schema: 'openring.context/1',
        ),
      ]) {
        final consent = aiConsentFor(
          config: _config,
          payload: _payload({'goal': {}}),
          previous: previous,
          at: at,
        );
        expect(consent.categories, {AiDataCategory.goals});
      }
    });
  });
}
