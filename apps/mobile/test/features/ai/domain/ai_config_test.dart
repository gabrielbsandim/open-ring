import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/ai_provider_preset.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';

import '../../../helpers/ai_fakes.dart';

void main() {
  group('AiConfig', () {
    test('round-trips JSON and verifies non-const value equality', () {
      const a = AiConfig(
        preset: AiProviderPreset.openRouter,
        baseUrl: 'https://openrouter.ai/api/v1/chat/completions',
        model: ' openai/gpt-5 ',
        detailLevel: AiDetailLevel.full,
        contextWindow: AiContextWindow.extended,
        importedIncluded: true,
        maxOutputTokens: 8000,
        requestTimeoutSeconds: 600,
        structuredOutputMode: AiStructuredOutputMode.jsonObject,
        streamingMode: AiStreamingMode.off,
        reasoningEffort: AiReasoningEffort.medium,
        inputPricePerMillion: 1.5,
        outputPricePerMillion: 6,
        priceCurrency: 'EUR',
        monthlyTokenCap: 500000,
        keyLastFour: 'ab3X',
        testedAtUtcMs: 1764000000000,
        testedHostKey: 'https://openrouter.ai:443',
        testedModel: 'openai/gpt-5',
        photoModel: 'openai/gpt-5-vision',
        photoDailyLimit: 3,
      );
      final restored = AiConfig.fromJson(a.toJson());
      final again = AiConfig.fromJson(a.toJson());
      expect(identical(restored, again), isFalse);
      expect(restored, a);
      expect(restored.hashCode, a.hashCode);
      expect(restored.hashCode, again.hashCode);
      expect(restored.trimmedModel, 'openai/gpt-5');
      expect(restored.hostKey, 'https://openrouter.ai:443');
      expect(restored.isTestedForCurrentTarget, isTrue);

      for (final variant in [
        a.copyWith(preset: AiProviderPreset.groq),
        a.copyWith(baseUrl: 'https://api.groq.com/openai/v1'),
        a.copyWith(model: 'other'),
        a.copyWith(detailLevel: AiDetailLevel.minimal),
        a.copyWith(contextWindow: AiContextWindow.compact),
        a.copyWith(importedIncluded: false),
        a.copyWith(maxOutputTokens: 2048),
        a.copyWith(requestTimeoutSeconds: 60),
        a.copyWith(structuredOutputMode: AiStructuredOutputMode.auto),
      ]) {
        expect(restored, isNot(variant));
      }
      expect(
        restored,
        isNot(a.copyWith(structuredOutputMode: AiStructuredOutputMode.off)),
      );
      expect(restored, isNot(a.copyWith(streamingMode: AiStreamingMode.auto)));
      expect(restored, isNot(a.copyWith(clearReasoningEffort: true)));
      expect(restored, isNot(a.copyWith(clearInputPrice: true)));
      expect(restored, isNot(a.copyWith(clearOutputPrice: true)));
      expect(restored, isNot(a.copyWith(priceCurrency: 'USD')));
      expect(restored, isNot(a.copyWith(clearMonthlyTokenCap: true)));
      expect(restored, isNot(a.copyWith(clearKeyLastFour: true)));
      expect(restored, isNot(a.copyWith(testedAtUtcMs: 1)));
      expect(
        restored,
        isNot(a.copyWith(testedHostKey: 'https://other.example:443')),
      );
      expect(restored, isNot(a.copyWith(testedModel: 'other')));
      expect(restored, isNot(a.copyWith(clearTested: true)));
      expect(restored, isNot(a.copyWith(clearPhotoModel: true)));
      expect(restored, isNot(a.copyWith(photoDailyLimit: 8)));
      expect(restored.photoDailyLimit, 3);
    });

    test('photoDailyLimit defaults to 8 and keeps only 1 to 30', () {
      expect(AiConfig.defaults.photoDailyLimit, 8);
      expect(AiConfig.fromJson(const {}).photoDailyLimit, 8);
      for (final kept in [1, 30]) {
        expect(
          AiConfig.fromJson({'photoDailyLimit': kept}).photoDailyLimit,
          kept,
        );
      }
      for (final bad in <Object>[0, 31, -4, 8.5, '12']) {
        expect(AiConfig.fromJson({'photoDailyLimit': bad}).photoDailyLimit, 8);
      }
    });

    test('clamps out-of-range JSON values and sanitizes corrupted inputs', () {
      final lowClamped = AiConfig.fromJson(const {
        'importedIncluded': 'true',
        'maxOutputTokens': 10,
        'requestTimeoutSeconds': 999,
        'priceCurrency': '   ',
        'monthlyTokenCap': 0,
        'inputPricePerMillion': -1,
        'outputPricePerMillion': double.infinity,
        'keyLastFour': '12345',
        'testedHostKey': '   ',
        'testedModel': '',
        'preset': 'unknown_provider',
        'reasoningEffort': 'extreme',
      });
      expect(lowClamped.importedIncluded, isFalse);
      expect(lowClamped.maxOutputTokens, aiMinOutputTokens);
      expect(lowClamped.requestTimeoutSeconds, 180);
      expect(lowClamped.priceCurrency, 'USD');
      expect(lowClamped.monthlyTokenCap, isNull);
      expect(lowClamped.inputPricePerMillion, isNull);
      expect(lowClamped.outputPricePerMillion, isNull);
      expect(lowClamped.keyLastFour, isNull);
      expect(lowClamped.testedHostKey, isNull);
      expect(lowClamped.testedModel, isNull);
      expect(lowClamped.preset, AiProviderPreset.openAi);
      expect(lowClamped.reasoningEffort, isNull);

      final highClamped = AiConfig.fromJson(const {
        'importedIncluded': 1,
        'maxOutputTokens': 999999,
        'keyLastFour': '',
        'inputPricePerMillion': 0,
        'outputPricePerMillion': double.nan,
      });
      expect(highClamped.importedIncluded, isFalse);
      expect(highClamped.maxOutputTokens, aiMaxOutputTokens);
      expect(highClamped.keyLastFour, '');
      expect(highClamped.inputPricePerMillion, 0);
      expect(highClamped.outputPricePerMillion, isNull);
    });

    test('lastFourOf masks short keys, trims whitespace, and preserves '
        'surrogate pairs', () {
      expect(AiConfig.lastFourOf('   '), isNull);
      expect(AiConfig.lastFourOf('short77'), '');
      expect(AiConfig.lastFourOf('  sk-1234ab3X  '), 'ab3X');
      expect(AiConfig.lastFourOf('prefix😀😁😂😃'), '😀😁😂😃');
    });

    test('hostKey, isTestedForCurrentTarget, and toString behave safely', () {
      const publicHttp = AiConfig(
        baseUrl: 'http://api.openai.com/v1',
        model: 'gpt-5',
        keyLastFour: 'ab3X',
        testedAtUtcMs: 1,
        testedHostKey: 'http://api.openai.com:80',
        testedModel: 'gpt-5',
      );
      expect(publicHttp.normalizedUrl, isNull);
      expect(publicHttp.hostKey, isNull);
      expect(publicHttp.isTestedForCurrentTarget, isFalse);

      const valid = AiConfig(
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-5',
        keyLastFour: 'ab3X',
        testedAtUtcMs: 1,
        testedHostKey: 'https://api.openai.com:443',
        testedModel: 'gpt-5',
      );
      expect(valid.isTestedForCurrentTarget, isTrue);
      expect(
        valid
            .copyWith(baseUrl: 'https://other.example/v1')
            .isTestedForCurrentTarget,
        isFalse,
      );
      expect(
        const AiConfig(
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-5',
          testedHostKey: 'https://api.openai.com:443',
          testedModel: 'gpt-5',
        ).isTestedForCurrentTarget,
        isFalse,
      );
      expect(
        valid.copyWith(testedModel: 'other').isTestedForCurrentTarget,
        isFalse,
      );
      expect(valid.copyWith(model: '   ').isTestedForCurrentTarget, isFalse);
      expect(valid.toString(), isNot(contains('ab3X')));
      expect(valid.toString(), contains('https://api.openai.com:443'));
    });
  });

  group('AiConsent and AiMealPhotoConsent', () {
    test('covers validates host, schema, policy date, and detail ordering', () {
      const json = <String, Object?>{
        'consentedAtUtcMs': 1764000000000,
        'policyEffectiveDate': aiCurrentPolicyEffectiveDate,
        'hostKey': 'https://openrouter.ai:443',
        'detailLevel': 'standard',
        'contextSchemaVersion': aiContextSchemaVersion,
      };
      final c1 = AiConsent.tryFromJson(json)!;
      final c2 = AiConsent.tryFromJson(json)!;
      expect(identical(c1, c2), isFalse);
      expect(c1, c2);
      expect(c1.hashCode, c2.hashCode);
      expect(c1.toJson(), {...json, 'categories': <String>[]});

      // Lower or equal detail is covered; higher detail asks again.
      expect(
        c1.covers(
          hostKey: 'https://openrouter.ai:443',
          detailLevel: AiDetailLevel.minimal,
          contextSchemaVersion: aiContextSchemaVersion,
          policyEffectiveDate: aiCurrentPolicyEffectiveDate,
        ),
        isTrue,
      );
      expect(
        c1.covers(
          hostKey: 'https://openrouter.ai:443',
          detailLevel: AiDetailLevel.standard,
          contextSchemaVersion: aiContextSchemaVersion,
          policyEffectiveDate: aiCurrentPolicyEffectiveDate,
        ),
        isTrue,
      );
      expect(
        c1.covers(
          hostKey: 'https://openrouter.ai:443',
          detailLevel: AiDetailLevel.full,
          contextSchemaVersion: aiContextSchemaVersion,
          policyEffectiveDate: aiCurrentPolicyEffectiveDate,
        ),
        isFalse,
      );
      expect(
        c1.covers(
          hostKey: 'https://openrouter.ai:8443',
          detailLevel: AiDetailLevel.standard,
          contextSchemaVersion: aiContextSchemaVersion,
          policyEffectiveDate: aiCurrentPolicyEffectiveDate,
        ),
        isFalse,
      );
      expect(
        c1.covers(
          hostKey: 'https://openrouter.ai:443',
          detailLevel: AiDetailLevel.standard,
          contextSchemaVersion: 'openring.context/3',
          policyEffectiveDate: aiCurrentPolicyEffectiveDate,
        ),
        isFalse,
      );
      expect(
        c1.covers(
          hostKey: 'https://openrouter.ai:443',
          detailLevel: AiDetailLevel.standard,
          contextSchemaVersion: aiContextSchemaVersion,
          policyEffectiveDate: '2026-12-01',
        ),
        isFalse,
      );

      expect(AiConsent.tryFromJson(const {'detailLevel': 'standard'}), isNull);
      expect(AiConsent.tryFromJson({...json, 'detailLevel': 'future'}), isNull);
    });

    test(
      'AiMealPhotoConsent round-trips and validates host and policy date',
      () {
        const json = <String, Object?>{
          'consentedAtUtcMs': 1764000000000,
          'policyEffectiveDate': aiCurrentPolicyEffectiveDate,
          'hostKey': 'https://api.openai.com:443',
        };
        final p1 = AiMealPhotoConsent.tryFromJson(json)!;
        final p2 = AiMealPhotoConsent.tryFromJson(json)!;
        expect(identical(p1, p2), isFalse);
        expect(p1, p2);
        expect(p1.hashCode, p2.hashCode);
        expect(p1.toJson(), json);
        expect(
          p1.covers(
            hostKey: 'https://api.openai.com:443',
            policyEffectiveDate: aiCurrentPolicyEffectiveDate,
          ),
          isTrue,
        );
        expect(
          p1.covers(
            hostKey: 'http://192.168.1.10:11434',
            policyEffectiveDate: aiCurrentPolicyEffectiveDate,
          ),
          isFalse,
        );
        expect(
          p1.covers(
            hostKey: 'https://api.openai.com:443',
            policyEffectiveDate: '2026-12-01',
          ),
          isFalse,
        );
        expect(AiMealPhotoConsent.tryFromJson(const {'hostKey': ''}), isNull);
      },
    );
  });

  group('resolveAiAvailability and aiCapabilityProfileKey', () {
    const baseConfig = AiConfig(
      baseUrl: 'https://openrouter.ai/api/v1',
      model: 'gpt-5',
      testedAtUtcMs: 100,
      testedHostKey: 'https://openrouter.ai:443',
      testedModel: 'gpt-5',
    );
    const baseConsent = AiConsent(
      consentedAtUtcMs: 100,
      policyEffectiveDate: aiCurrentPolicyEffectiveDate,
      hostKey: 'https://openrouter.ai:443',
      detailLevel: AiDetailLevel.standard,
      contextSchemaVersion: aiContextSchemaVersion,
    );

    test('resolves all 5 availability states and local optional-key path', () {
      expect(
        resolveAiAvailability(
          moduleEnabled: false,
          config: baseConfig,
          hasStoredKey: true,
          consent: baseConsent,
        ),
        AiAvailability.off,
      );
      expect(
        resolveAiAvailability(
          moduleEnabled: true,
          config: baseConfig.copyWith(baseUrl: ''),
          hasStoredKey: true,
          consent: baseConsent,
        ),
        AiAvailability.notConfigured,
      );
      expect(
        resolveAiAvailability(
          moduleEnabled: true,
          config: baseConfig.copyWith(model: '   '),
          hasStoredKey: true,
          consent: baseConsent,
        ),
        AiAvailability.notConfigured,
      );
      expect(
        resolveAiAvailability(
          moduleEnabled: true,
          config: baseConfig,
          hasStoredKey: false,
          consent: baseConsent,
        ),
        AiAvailability.notConfigured,
      );
      expect(
        resolveAiAvailability(
          moduleEnabled: true,
          config: baseConfig.copyWith(clearTested: true),
          hasStoredKey: true,
          consent: baseConsent,
        ),
        AiAvailability.notTested,
      );
      expect(
        resolveAiAvailability(
          moduleEnabled: true,
          config: baseConfig,
          hasStoredKey: true,
          consent: null,
        ),
        AiAvailability.consentNeeded,
      );
      expect(
        resolveAiAvailability(
          moduleEnabled: true,
          config: baseConfig.copyWith(detailLevel: AiDetailLevel.full),
          hasStoredKey: true,
          consent: baseConsent,
        ),
        AiAvailability.consentNeeded,
      );
      expect(
        resolveAiAvailability(
          moduleEnabled: true,
          config: baseConfig.copyWith(
            baseUrl: 'https://other.example/v1',
            testedHostKey: 'https://other.example:443',
          ),
          hasStoredKey: true,
          consent: baseConsent,
        ),
        AiAvailability.consentNeeded,
      );
      expect(
        resolveAiAvailability(
          moduleEnabled: true,
          config: baseConfig,
          hasStoredKey: true,
          consent: baseConsent,
          contextSchemaVersion: 'openring.context/3',
        ),
        AiAvailability.consentNeeded,
      );
      expect(
        resolveAiAvailability(
          moduleEnabled: true,
          config: baseConfig,
          hasStoredKey: true,
          consent: baseConsent,
          policyEffectiveDate: '2026-12-01',
        ),
        AiAvailability.consentNeeded,
      );
      expect(
        resolveAiAvailability(
          moduleEnabled: true,
          config: baseConfig,
          hasStoredKey: true,
          consent: baseConsent,
        ),
        AiAvailability.ready,
      );

      // Local preset reaches ready without an API key once tested & consented.
      const localConfig = AiConfig(
        preset: AiProviderPreset.ollama,
        baseUrl: 'http://192.168.1.10:11434/v1',
        model: 'llama3.2',
        testedAtUtcMs: 100,
        testedHostKey: 'http://192.168.1.10:11434',
        testedModel: 'llama3.2',
      );
      const localConsent = AiConsent(
        consentedAtUtcMs: 100,
        policyEffectiveDate: aiCurrentPolicyEffectiveDate,
        hostKey: 'http://192.168.1.10:11434',
        detailLevel: AiDetailLevel.standard,
        contextSchemaVersion: aiContextSchemaVersion,
      );
      expect(
        resolveAiAvailability(
          moduleEnabled: true,
          config: localConfig,
          hasStoredKey: false,
          consent: localConsent,
        ),
        AiAvailability.ready,
      );
      expect(
        aiCapabilityProfileKey('https://openrouter.ai:443', ' gpt-5 '),
        'https://openrouter.ai:443|gpt-5',
      );
    });
  });

  group('AI test fakes', () {
    test(
      'InMemorySecretStore, FailingSecretStore, and InMemoryAiConfigStore',
      () async {
        final secrets = InMemorySecretStore();
        await secrets.write(aiApiKeySecretName, 'sk-12345678');
        expect(await secrets.read(aiApiKeySecretName), 'sk-12345678');
        await secrets.delete(aiApiKeySecretName);
        expect(secrets.deleteCalls, 1);
        expect(await secrets.read(aiApiKeySecretName), isNull);

        final failing = FailingSecretStore(failRead: true, failWrite: true);
        await expectLater(failing.read('k'), throwsStateError);
        await expectLater(failing.write('k', 'v'), throwsStateError);
        await failing.delete('k');
        expect(failing.deleteCalls, 1);

        final failDel = FailingSecretStore(failDelete: true);
        await failDel.write('k', 'v');
        expect(await failDel.read('k'), 'v');
        await expectLater(failDel.delete('k'), throwsStateError);

        final store = InMemoryAiConfigStore();
        await store.writeConfig(const AiConfig(model: 'gpt-5'));
        await store.writeConsent(
          const AiConsent(
            consentedAtUtcMs: 1,
            policyEffectiveDate: aiCurrentPolicyEffectiveDate,
            hostKey: 'https://api.openai.com:443',
            detailLevel: AiDetailLevel.standard,
            contextSchemaVersion: aiContextSchemaVersion,
          ),
        );
        await store.writeMealPhotoConsent(
          const AiMealPhotoConsent(
            consentedAtUtcMs: 2,
            policyEffectiveDate: aiCurrentPolicyEffectiveDate,
            hostKey: 'https://api.openai.com:443',
          ),
        );
        await store.writeCapabilityProfile(
          'https://api.openai.com:443',
          'gpt-5',
          AiCapabilityProfile.defaults,
        );
        expect((await store.readConfig()).model, 'gpt-5');
        expect(await store.readConsent(), isNotNull);
        expect(await store.readMealPhotoConsent(), isNotNull);
        expect(
          await store.readCapabilityProfile(
            'https://api.openai.com:443',
            'gpt-5',
          ),
          AiCapabilityProfile.defaults,
        );
        await store.clearConsent();
        await store.clearMealPhotoConsent();
        await store.clearCapabilityProfiles();
        expect(await store.readConsent(), isNull);
        expect(await store.readMealPhotoConsent(), isNull);
        expect(
          await store.readCapabilityProfile(
            'https://api.openai.com:443',
            'gpt-5',
          ),
          isNull,
        );
        await store.clearAll();
        expect(await store.readConfig(), AiConfig.defaults);

        // Re-seed all 4 slots so clearAll() is proven to wipe populated state.
        await store.writeConfig(const AiConfig(model: 'gpt-5'));
        await store.writeConsent(
          const AiConsent(
            consentedAtUtcMs: 1,
            policyEffectiveDate: aiCurrentPolicyEffectiveDate,
            hostKey: 'https://api.openai.com:443',
            detailLevel: AiDetailLevel.standard,
            contextSchemaVersion: aiContextSchemaVersion,
          ),
        );
        await store.writeMealPhotoConsent(
          const AiMealPhotoConsent(
            consentedAtUtcMs: 2,
            policyEffectiveDate: aiCurrentPolicyEffectiveDate,
            hostKey: 'https://api.openai.com:443',
          ),
        );
        await store.writeCapabilityProfile(
          'https://api.openai.com:443',
          'gpt-5',
          AiCapabilityProfile.defaults,
        );
        await store.clearAll();
        expect(await store.readConfig(), AiConfig.defaults);
        expect(await store.readConsent(), isNull);
        expect(await store.readMealPhotoConsent(), isNull);
        expect(
          await store.readCapabilityProfile(
            'https://api.openai.com:443',
            'gpt-5',
          ),
          isNull,
        );
      },
    );
  });
}
