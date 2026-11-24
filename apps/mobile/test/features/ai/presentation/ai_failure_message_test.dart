import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/ai_provider_preset.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_run_state.dart';
import 'package:open_ring/features/ai/domain/openai_wire_codec.dart';
import 'package:open_ring/features/ai/presentation/ai_failure_message.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

const _remote = AiConfig(baseUrl: 'https://api.example.com/v1', model: 'gpt-x');
const _local = AiConfig(
  preset: AiProviderPreset.ollama,
  baseUrl: 'http://192.168.1.10:11434/v1',
  model: 'llama',
  requestTimeoutSeconds: 600,
);

RunModelFailure _f(
  AnalysisFailureKind kind, {
  int? status,
  int? retryAfter,
  TimeoutStage? stage,
  String detail = '',
}) => RunModelFailure(
  AnalysisFailure(
    kind: kind,
    statusCode: status,
    retryAfterSeconds: retryAfter,
    timeoutStage: stage,
    detail: detail,
  ),
);

AiReport _report({
  AiReportStatus status = AiReportStatus.done,
  int dropped = 2,
  List<Object?> cards = const [],
}) => AiReport(
  createdAtUtc: DateTime.utc(2026, 11, 24),
  offsetMin: 0,
  kind: 'weekly_review',
  contextSchema: aiContextSchemaVersion,
  contextSha256: 'sha',
  detailLevel: 'standard',
  promptVersion: 'v$aiPromptVersion',
  providerHost: 'https://api.example.com:443',
  model: 'gpt-x',
  status: status,
  droppedCards: dropped,
  cardsJson: jsonEncode({'summary': '', 'cards': cards}),
);

void main() {
  for (final locale in ['en', 'pt']) {
    final l10n = lookupAppLocalizations(Locale(locale));

    test('$locale: every failure kind has its own line', () {
      final lines = <AnalysisFailureKind, String>{};
      for (final kind in AnalysisFailureKind.values) {
        final line = aiFailureMessage(l10n, _f(kind, status: 503), _remote);
        expect(line, isNotNull, reason: '$kind');
        expect(line, isNotEmpty, reason: '$kind');
        lines[kind] = line!;
      }
      for (final MapEntry(:key, :value) in lines.entries) {
        if (key == AnalysisFailureKind.unreadable) continue;
        expect(value, isNot(l10n.aiErrorUnreadable), reason: '$key');
      }
      expect(lines.values.toSet(), hasLength(lines.length));
    });

    test('$locale: run failures and the no match case have a line', () {
      expect(
        aiFailureMessage(l10n, const RunNotEnoughData(3), _remote),
        l10n.aiPreviewNotEnough(3),
      );
      expect(
        aiFailureMessage(
          l10n,
          const RunCeilingReached(used: 12000, cap: 10000),
          _remote,
        ),
        l10n.aiErrorCeiling(12000, 10000),
      );
      expect(
        aiFailureMessage(l10n, RunUnexpected(StateError('x')), _remote),
        l10n.aiErrorUnreadable,
      );
      expect(l10n.aiErrorNoMatch, isNotEmpty);
    });
  }

  final l10n = lookupAppLocalizations(const Locale('en'));
  final pt = lookupAppLocalizations(const Locale('pt'));

  test('a missing consent has no line, it reopens the sheet', () {
    expect(aiFailureMessage(l10n, const RunConsentNeeded(), _remote), isNull);
  });

  test('the ceiling line groups digits for the locale', () {
    final line = aiFailureMessage(
      l10n,
      const RunCeilingReached(used: 12000, cap: 10000),
      _remote,
    );
    expect(line, contains('12,000 of 10,000'));
  });

  test('429 names the retry-after seconds, or says in a moment', () {
    final rate = AnalysisFailureKind.rateLimited;
    expect(
      aiFailureMessage(l10n, _f(rate, retryAfter: 45), _remote),
      'The provider is limiting requests. Try again in 45 s.',
    );
    expect(
      aiFailureMessage(l10n, _f(rate), _remote),
      'The provider is limiting requests. Try again in a moment.',
    );
    expect(
      aiFailureMessage(pt, _f(rate, retryAfter: 45), _remote),
      contains('45 s'),
    );
  });

  test('5xx carries the status and the host', () {
    final line = aiFailureMessage(
      l10n,
      _f(AnalysisFailureKind.serverError, status: 503),
      _remote,
    );
    expect(
      line,
      'api.example.com had a problem (503). Nothing was shown. '
      'Try again later.',
    );
  });

  test('403 names the model', () {
    expect(
      aiFailureMessage(l10n, _f(AnalysisFailureKind.forbidden), _remote),
      l10n.aiErrorForbidden('gpt-x'),
    );
  });

  group('timeout seconds per stage', () {
    String? line(AiConfig config, TimeoutStage stage) => aiFailureMessage(
      l10n,
      _f(AnalysisFailureKind.timeout, stage: stage),
      config,
    );

    test('remote', () {
      expect(
        line(_remote, TimeoutStage.connect),
        l10n.aiErrorUnreachable('api.example.com'),
      );
      expect(
        line(_remote, TimeoutStage.firstByte),
        l10n.aiErrorTimeout('api.example.com', 60),
      );
      expect(
        line(_remote, TimeoutStage.idle),
        l10n.aiErrorTimeout('api.example.com', 45),
      );
      expect(
        line(_remote, TimeoutStage.total),
        l10n.aiErrorTimeout('api.example.com', 180),
      );
    });

    test('local', () {
      expect(
        line(_local, TimeoutStage.connect),
        l10n.aiErrorUnreachableLocal('192.168.1.10'),
      );
      expect(
        line(_local, TimeoutStage.firstByte),
        l10n.aiErrorTimeout('192.168.1.10', 180),
      );
      expect(
        line(_local, TimeoutStage.idle),
        l10n.aiErrorTimeout('192.168.1.10', 120),
      );
      expect(
        line(_local, TimeoutStage.total),
        l10n.aiErrorTimeout('192.168.1.10', 600),
      );
    });
  });

  test('the key never appears in Details', () {
    const key = 'sk-secret-123456';
    final failure = OpenAiWireCodec.classifyHttpError(
      statusCode: 401,
      body: '{"error":{"message":"Incorrect API key provided: $key"}}',
      apiKey: key,
    );
    final details = aiFailureDetails(RunModelFailure(failure))!;
    expect(details, startsWith('401'));
    expect(details, contains('Incorrect API key'));
    expect(details, isNot(contains(key)));
  });

  test('a cancelled run has no Details', () {
    expect(aiFailureDetails(_f(AnalysisFailureKind.cancelled)), isNull);
  });

  group('actions', () {
    List<AiFailureAction> actions(
      AnalysisRunFailure f, {
      bool larger = false,
      bool raw = true,
    }) => aiFailureActions(f, canRetryLarger: larger, hasRaw: raw);
    const retry = AiFailureAction.retry;
    const open = AiFailureAction.connection;

    test('per kind', () {
      for (final kind in [
        AnalysisFailureKind.unauthorized,
        AnalysisFailureKind.forbidden,
        AnalysisFailureKind.modelNotFound,
      ]) {
        expect(actions(_f(kind)), [open], reason: '$kind');
      }
      for (final kind in [
        AnalysisFailureKind.timeout,
        AnalysisFailureKind.refused,
      ]) {
        expect(actions(_f(kind)), [retry, open], reason: '$kind');
      }
      expect(actions(_f(AnalysisFailureKind.unreadable)), [
        retry,
        AiFailureAction.raw,
      ]);
      expect(actions(_f(AnalysisFailureKind.unreadable), raw: false), [retry]);
      expect(actions(_f(AnalysisFailureKind.emptyAfterLimit), larger: true), [
        AiFailureAction.larger,
      ]);
      expect(actions(_f(AnalysisFailureKind.serverError)), [retry]);
      expect(actions(_f(AnalysisFailureKind.rateLimited)), [retry]);
      expect(actions(RunUnexpected(StateError('x'))), [retry]);
    });

    test('nothing to retry for the ceiling or too few days', () {
      expect(actions(const RunCeilingReached(used: 1, cap: 1)), isEmpty);
      expect(actions(const RunNotEnoughData(2)), isEmpty);
      expect(actions(const RunConsentNeeded()), isEmpty);
    });
  });

  test('no match is a done answer with every card dropped', () {
    expect(aiNoMatch(_report()), isTrue);
    expect(aiNoMatch(_report(dropped: 0)), isFalse);
    expect(aiNoMatch(_report(status: AiReportStatus.failed)), isFalse);
    expect(
      aiNoMatch(
        _report(
          cards: [
            {
              'family': 'sleep',
              'title': 'Kept',
              'insight': 'Kept.',
              'evidenceIds': ['f.sleepMin.avg'],
              'action': 'Keep.',
              'modelConfidence': 'high',
              'coverageConfidence': 'high',
              'shownConfidence': 'high',
              'minEvidenceDays': 10,
            },
          ],
        ),
      ),
      isFalse,
    );
  });

  test('no em or en dash in any line', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l = lookupAppLocalizations(locale);
      final all = [
        for (final kind in AnalysisFailureKind.values)
          aiFailureMessage(l, _f(kind, status: 500, retryAfter: 5), _remote)!,
        l.aiErrorNoMatch,
        l.aiShowRaw('raw'),
        l.aiShowRaw('unverified'),
        l.aiRawTitle,
        l.aiRawBanner('m'),
        l.aiRetryLarger,
        l.aiErrorCeiling(1, 2),
        l.aiReadingFailedRow('cancelled'),
        l.aiReadingFailedRow('failed'),
      ];
      for (final text in all) {
        expect(text, isNot(contains(String.fromCharCode(0x2013))));
        expect(text, isNot(contains(String.fromCharCode(0x2014))));
      }
    }
  });
}
