import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';

void main() {
  group('AiCapabilityProfile', () {
    test('round-trips JSON and handles unknown enum names safely', () {
      const profile = AiCapabilityProfile(
        jsonMode: AiJsonMode.jsonObject,
        limitField: AiLimitField.maxTokens,
        streamOk: false,
        streamUsageOk: false,
        vision: AiVisionSupport.yes,
      );
      final restored = AiCapabilityProfile.fromJson(profile.toJson());
      expect(restored, profile);
      expect(restored.hashCode, profile.hashCode);

      final fallback = AiCapabilityProfile.fromJson(const {
        'jsonMode': 'future_mode',
        'limitField': 42,
        'vision': 'unknown_v2',
      });
      expect(fallback, AiCapabilityProfile.defaults);
    });

    test('steps monotonically through the capability ladder', () {
      var profile = AiCapabilityProfile.defaults;

      // Drop stream_options when explicitly named (never treat as 'stream').
      profile = profile.nextOnBadRequest(
        'Unrecognized field: stream_options is not supported',
      )!;
      expect(profile.streamUsageOk, isFalse);
      expect(profile.streamOk, isTrue);

      // Switch max_completion_tokens when explicitly named.
      profile = profile.nextOnBadRequest(
        'max_completion_tokens is not supported; use max_tokens',
      )!;
      expect(profile.limitField, AiLimitField.maxTokens);

      // Explicit json_schema rejection skips non-streaming jsonSchema.
      final skipped = AiCapabilityProfile.defaults.nextOnBadRequest(
        'json_schema unsupported',
      )!;
      expect(skipped.jsonMode, AiJsonMode.jsonObject);
      expect(skipped.streamOk, isTrue);

      // Streaming jsonObject drops streaming before dropping jsonObject on 'stream'.
      final objNonStream = skipped.nextOnBadRequest('stream mode unsupported')!;
      expect(objNonStream.jsonMode, AiJsonMode.jsonObject);
      expect(objNonStream.streamOk, isFalse);

      final noneFromObjNonStream = objNonStream.nextOnBadRequest(
        'bad request',
      )!;
      expect(noneFromObjNonStream.jsonMode, AiJsonMode.none);
      expect(noneFromObjNonStream.streamOk, isFalse);
      expect(
        noneFromObjNonStream.nextOnBadRequest('stream mode unsupported'),
        isNull,
      );

      // Groq: drop streaming under strict json_schema, keep streamUsageOk as-is.
      const fresh = AiCapabilityProfile.defaults;
      final step1 = fresh.nextOnBadRequest(
        'Streaming not supported with schema',
      )!;
      expect(step1.jsonMode, AiJsonMode.jsonSchema);
      expect(step1.streamOk, isFalse);
      expect(step1.streamUsageOk, isTrue);

      final step2 = step1.nextOnBadRequest('json_schema unsupported')!;
      expect(step2.jsonMode, AiJsonMode.jsonObject);
      expect(step2.streamOk, isTrue);
      expect(step2.streamUsageOk, isTrue);

      final step3 = step2.nextOnBadRequest(
        'response_format json_object error',
      )!;
      expect(step3.jsonMode, AiJsonMode.none);
      expect(step3.streamOk, isTrue);
      expect(step3.nextOnBadRequest('bad request'), isNull);
      expect(
        step3
            .copyWith(streamUsageOk: false)
            .nextOnBadRequest('stream_options unsupported'),
        isNull,
      );

      final step4 = step3.nextOnBadRequest('stream mode unsupported')!;
      expect(step4.jsonMode, AiJsonMode.none);
      expect(step4.streamOk, isFalse);

      expect(step4.nextOnBadRequest('bad request'), isNull);
      expect(step4.nextOnBadRequest('stream mode unsupported'), isNull);
    });
    test('preserves streamOk: false when stepping jsonObject to none', () {
      const nonStreamingObj = AiCapabilityProfile(
        jsonMode: AiJsonMode.jsonObject,
        streamOk: false,
      );
      final keptOff = nonStreamingObj.nextOnBadRequest('bad request')!;
      expect(keptOff.jsonMode, AiJsonMode.none);
      expect(keptOff.streamOk, isFalse);
      expect(keptOff.nextOnBadRequest('bad request'), isNull);
    });
    test('capability ladder is an acyclic DAG deeper than the attempt cap', () {
      const triggers = [
        'stream_options',
        'max_completion_tokens',
        'stream',
        'json_schema',
        'response_format',
        'bad request',
      ];
      const target = AiCapabilityProfile(
        jsonMode: AiJsonMode.jsonObject,
        streamOk: false,
      );
      final depths = <AiCapabilityProfile, int>{};
      final visiting = <AiCapabilityProfile>{};

      int visit(AiCapabilityProfile node, int depth) {
        if (visiting.contains(node)) {
          fail('Cycle detected at $node');
        }
        final known = depths[node];
        if (known == null || depth > known) {
          depths[node] = depth;
        }
        visiting.add(node);
        var best = 0;
        for (final trigger in triggers) {
          final next = node.nextOnBadRequest(trigger);
          if (next == null) continue;
          expect(next, isNot(node));
          final candidate = 1 + visit(next, depth + 1);
          if (candidate > best) best = candidate;
        }
        visiting.remove(node);
        return best;
      }

      final maxTransitions = visit(AiCapabilityProfile.defaults, 0);
      expect(maxTransitions, 6);
      expect(aiMaxLadderAttempts, 4);
      expect(depths.containsKey(target), isTrue);
    });
  });

  group('scrubApiKey', () {
    test('redacts exact and trimmed key before capping at 300 chars', () {
      const secret = 'sk-secret-value-1234';
      final scrubbed = scrubApiKey(
        'Auth failed for Bearer $secret and again $secret',
        '  $secret  ',
      );
      expect(scrubbed, isNot(contains(secret)));
      expect(
        scrubbed,
        'Auth failed for Bearer [redacted] and again [redacted]',
      );

      final crossBoundary = '${'a' * 292}$secret';
      final paddedLeft = '$secret ${'b' * 295}';
      final cappedCross = scrubApiKey(crossBoundary, secret);
      final cappedLeft = scrubApiKey(paddedLeft, secret);
      expect(cappedCross.length, aiMaxErrorDetailChars);
      expect(cappedCross, isNot(contains('sk-secret')));
      expect(cappedCross, endsWith('[redacte'));
      expect(cappedLeft.length, aiMaxErrorDetailChars);
      expect(cappedLeft, startsWith('[redacted] '));
      expect(cappedLeft, isNot(contains('sk-secret')));

      expect(scrubApiKey('  plain error  ', null), 'plain error');
      expect(scrubApiKey('plain error', ''), 'plain error');
      expect(scrubApiKey('plain error', '   '), 'plain error');
    });
  });

  group('value equality', () {
    test('covers non-identical instances and differing fields', () {
      final pFromJsonA = AiCapabilityProfile.fromJson(const {
        'jsonMode': 'jsonObject',
        'limitField': 'maxTokens',
        'streamOk': false,
        'streamUsageOk': false,
        'vision': 'yes',
      });
      final pFromJsonB = AiCapabilityProfile.fromJson(const {
        'jsonMode': 'jsonObject',
        'limitField': 'maxTokens',
        'streamOk': false,
        'streamUsageOk': false,
        'vision': 'yes',
      });
      expect(identical(pFromJsonA, pFromJsonB), isFalse);
      expect(pFromJsonA, pFromJsonB);
      expect(pFromJsonA.hashCode, pFromJsonB.hashCode);
      expect(pFromJsonA, isNot(pFromJsonA.copyWith(jsonMode: AiJsonMode.none)));
      expect(
        pFromJsonA,
        isNot(
          pFromJsonA.copyWith(limitField: AiLimitField.maxCompletionTokens),
        ),
      );
      expect(pFromJsonA, isNot(pFromJsonA.copyWith(streamOk: true)));
      expect(pFromJsonA, isNot(pFromJsonA.copyWith(streamUsageOk: true)));
      expect(
        pFromJsonA,
        isNot(pFromJsonA.copyWith(vision: AiVisionSupport.no)),
      );

      final promptA = int.parse('100');
      final promptB = int.parse('100');
      final u1 = AiTokenUsage(
        promptTokens: promptA,
        completionTokens: 20,
        totalTokens: 120,
        reasoningTokens: 5,
        providerCost: 0.001,
      );
      final u2 = AiTokenUsage(
        promptTokens: promptB,
        completionTokens: 20,
        totalTokens: 120,
        reasoningTokens: 5,
        providerCost: 0.001,
      );
      expect(identical(u1, u2), isFalse);
      expect(u1, u2);
      expect(u1.hashCode, u2.hashCode);
      expect(
        u1,
        isNot(
          const AiTokenUsage(
            promptTokens: 101,
            completionTokens: 20,
            totalTokens: 120,
            reasoningTokens: 5,
            providerCost: 0.001,
          ),
        ),
      );
      expect(
        u1,
        isNot(
          AiTokenUsage(
            promptTokens: promptA,
            completionTokens: 21,
            totalTokens: 120,
            reasoningTokens: 5,
            providerCost: 0.001,
          ),
        ),
      );
      expect(
        u1,
        isNot(
          AiTokenUsage(
            promptTokens: promptA,
            completionTokens: 20,
            totalTokens: 121,
            reasoningTokens: 5,
            providerCost: 0.001,
          ),
        ),
      );
      expect(
        u1,
        isNot(
          AiTokenUsage(
            promptTokens: promptA,
            completionTokens: 20,
            totalTokens: 120,
            reasoningTokens: 6,
            providerCost: 0.001,
          ),
        ),
      );
      expect(
        u1,
        isNot(
          AiTokenUsage(
            promptTokens: promptA,
            completionTokens: 20,
            totalTokens: 120,
            reasoningTokens: 5,
            providerCost: 0.002,
          ),
        ),
      );

      final charsA = int.parse('42');
      final charsB = int.parse('42');
      final p1 = AnalysisProgress(charsA);
      final p2 = AnalysisProgress(charsB);
      expect(identical(p1, p2), isFalse);
      expect(p1, p2);
      expect(p1.hashCode, p2.hashCode);
      expect(p1, isNot(AnalysisProgress(charsA + 1)));

      final textA = String.fromCharCodes('{}'.codeUnits);
      final textB = String.fromCharCodes('{}'.codeUnits);
      final c1 = AnalysisCompleted(
        text: textA,
        finishReason: 'stop',
        usage: u1,
      );
      final c2 = AnalysisCompleted(
        text: textB,
        finishReason: 'stop',
        usage: u2,
      );
      expect(identical(c1, c2), isFalse);
      expect(c1, c2);
      expect(c1.hashCode, c2.hashCode);
      expect(
        c1,
        isNot(
          AnalysisCompleted(text: '{"a":1}', finishReason: 'stop', usage: u1),
        ),
      );
      expect(
        c1,
        isNot(
          AnalysisCompleted(text: textA, finishReason: 'length', usage: u1),
        ),
      );
      expect(c1, isNot(AnalysisCompleted(text: textA, finishReason: 'stop')));

      final statusA = int.parse('429');
      final statusB = int.parse('429');
      final f1 = AnalysisFailure(
        kind: AnalysisFailureKind.rateLimited,
        detail: 'slow',
        statusCode: statusA,
        retryAfterSeconds: 10,
        timeoutStage: TimeoutStage.firstByte,
      );
      final f2 = AnalysisFailure(
        kind: AnalysisFailureKind.rateLimited,
        detail: 'slow',
        statusCode: statusB,
        retryAfterSeconds: 10,
        timeoutStage: TimeoutStage.firstByte,
      );
      expect(identical(f1, f2), isFalse);
      expect(f1, f2);
      expect(f1.hashCode, f2.hashCode);
      expect(
        f1,
        isNot(
          AnalysisFailure(
            kind: AnalysisFailureKind.serverError,
            detail: 'slow',
            statusCode: statusA,
            retryAfterSeconds: 10,
            timeoutStage: TimeoutStage.firstByte,
          ),
        ),
      );
      expect(
        f1,
        isNot(
          AnalysisFailure(
            kind: AnalysisFailureKind.rateLimited,
            detail: 'other',
            statusCode: statusA,
            retryAfterSeconds: 10,
            timeoutStage: TimeoutStage.firstByte,
          ),
        ),
      );
      expect(
        f1,
        isNot(
          const AnalysisFailure(
            kind: AnalysisFailureKind.rateLimited,
            detail: 'slow',
            statusCode: 500,
            retryAfterSeconds: 10,
            timeoutStage: TimeoutStage.firstByte,
          ),
        ),
      );
      expect(
        f1,
        isNot(
          AnalysisFailure(
            kind: AnalysisFailureKind.rateLimited,
            detail: 'slow',
            statusCode: statusA,
            retryAfterSeconds: 20,
            timeoutStage: TimeoutStage.firstByte,
          ),
        ),
      );
      expect(
        f1,
        isNot(
          AnalysisFailure(
            kind: AnalysisFailureKind.rateLimited,
            detail: 'slow',
            statusCode: statusA,
            retryAfterSeconds: 10,
            timeoutStage: TimeoutStage.total,
          ),
        ),
      );
    });
  });

  group('AI domain architectural invariants', () {
    test(
      'lib/features/ai/domain imports no Flutter or dart:io and has no dashes',
      () {
        final dir = Directory('lib/features/ai/domain');
        final files = dir.listSync().whereType<File>().toList();
        expect(
          files.map((f) => f.uri.pathSegments.last),
          containsAll([
            'ai_config.dart',
            'ai_output_extractor.dart',
            'ai_prompt.dart',
            'ai_provider_preset.dart',
            'ai_report_models.dart',
            'ai_report_validator.dart',
            'ai_safety_lexicon.dart',
            'ai_wire_types.dart',
            'base_url_policy.dart',
            'health_context_models.dart',
            'health_context_v2.dart',
            'openai_wire_codec.dart',
            'secret_store.dart',
          ]),
        );
        final dashes = RegExp(r'[\u2013\u2014]');
        for (final file in files) {
          final content = file.readAsStringSync();
          expect(
            content,
            isNot(contains('package:flutter/')),
            reason: file.path,
          );
          expect(content, isNot(contains('dart:io')), reason: file.path);
          expect(dashes.hasMatch(content), isFalse, reason: file.path);
        }
      },
    );
  });
}
