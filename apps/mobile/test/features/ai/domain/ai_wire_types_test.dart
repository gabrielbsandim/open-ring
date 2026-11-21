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

      // Drop stream_options when explicitly named.
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

      final step4 = step3.nextOnBadRequest('stream mode unsupported')!;
      expect(step4.jsonMode, AiJsonMode.none);
      expect(step4.streamOk, isFalse);

      expect(step4.nextOnBadRequest('bad request'), isNull);
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
    });
  });

  group('value equality', () {
    test('covers non-identical instances and differing fields', () {
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
          AiTokenUsage(
            promptTokens: promptA,
            completionTokens: 21,
            totalTokens: 120,
            reasoningTokens: 5,
            providerCost: 0.001,
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
          AnalysisCompleted(text: textA, finishReason: 'length', usage: u1),
        ),
      );

      final statusA = int.parse('429');
      final statusB = int.parse('429');
      final f1 = AnalysisFailure(
        kind: AnalysisFailureKind.rateLimited,
        detail: 'slow',
        statusCode: statusA,
        retryAfterSeconds: 10,
      );
      final f2 = AnalysisFailure(
        kind: AnalysisFailureKind.rateLimited,
        detail: 'slow',
        statusCode: statusB,
        retryAfterSeconds: 10,
      );
      expect(identical(f1, f2), isFalse);
      expect(f1, f2);
      expect(f1.hashCode, f2.hashCode);
      expect(
        f1,
        isNot(
          AnalysisFailure(
            kind: AnalysisFailureKind.rateLimited,
            detail: 'slow',
            statusCode: statusA,
            retryAfterSeconds: 20,
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
        expect(files, hasLength(3));
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
