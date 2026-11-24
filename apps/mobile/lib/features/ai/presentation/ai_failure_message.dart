import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_reading.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_run_state.dart';
import 'package:open_ring/features/ai/infrastructure/http_analysis_model.dart';
import 'package:open_ring/features/ai/presentation/ai_test_connection_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

enum AiFailureAction { retry, connection, larger, raw }

/// The 2.3 line for a reading that did not finish. Null for a missing
/// consent, which reopens the consent sheet instead of showing a line.
String? aiFailureMessage(
  AppLocalizations l10n,
  AnalysisRunFailure failure,
  AiConfig config,
) => switch (failure) {
  RunModelFailure(:final failure) => _modelLine(l10n, failure, config),
  RunNotEnoughData(:final days) => l10n.aiPreviewNotEnough(days),
  RunCeilingReached(:final used, :final cap) => l10n.aiErrorCeiling(used, cap),
  RunUnexpected() => l10n.aiErrorUnreadable('phone'),
  RunConsentNeeded() => null,
};

String _modelLine(
  AppLocalizations l10n,
  AnalysisFailure failure,
  AiConfig config,
) {
  final url = config.normalizedUrl;
  final host = url?.asciiHost ?? '';
  final model = config.trimmedModel;
  final local = config.preset.isLocal;
  final known = aiTestFailureMessage(
    l10n,
    failure,
    host: host,
    model: model,
    local: local || (url?.isCleartext ?? false),
  );
  if (known != null) return known;
  return switch (failure.kind) {
    AnalysisFailureKind.badRequest => l10n.aiErrorRejected,
    AnalysisFailureKind.noCredit => l10n.aiErrorNoCredit,
    AnalysisFailureKind.forbidden => l10n.aiErrorForbidden(model),
    AnalysisFailureKind.contextTooLong => l10n.aiErrorTooLong,
    AnalysisFailureKind.rateLimited => l10n.aiErrorRateLimited(
      (failure.retryAfterSeconds ?? 0).clamp(0, 86400),
    ),
    AnalysisFailureKind.serverError => l10n.aiErrorServer(
      host,
      '${failure.statusCode ?? 'none'}',
    ),
    AnalysisFailureKind.timeout => _timeoutLine(l10n, failure, config, host),
    AnalysisFailureKind.emptyAfterLimit => l10n.aiErrorOutputLimit,
    AnalysisFailureKind.refused => l10n.aiErrorRefused,
    AnalysisFailureKind.cancelled => l10n.aiReadingCancelled,
    _ => l10n.aiErrorUnreadable('model'),
  };
}

// Only the total stage follows Advanced; first byte and idle are fixed, so
// the Advanced hint shows for the total alone.
String _timeoutLine(
  AppLocalizations l10n,
  AnalysisFailure failure,
  AiConfig config,
  String host,
) {
  final stage = failure.timeoutStage ?? TimeoutStage.total;
  final seconds = aiTimeoutStageSeconds(
    stage,
    local: config.preset.isLocal,
    totalSeconds: config.requestTimeoutSeconds,
  );
  return l10n.aiErrorTimeout(host, seconds, stage.name);
}

/// Status and the provider's own text, already scrubbed of the key where
/// the failure was built.
String? aiFailureDetails(AnalysisRunFailure failure) {
  final text = switch (failure) {
    RunModelFailure(:final failure)
        when failure.kind != AnalysisFailureKind.cancelled =>
      aiTestFailureDetails(failure, null),
    RunUnexpected(:final error) => '${error.runtimeType}',
    _ => '',
  };
  return text.isEmpty ? null : text;
}

/// Every retry spends the user's money, so each is a button and none runs
/// by itself.
List<AiFailureAction> aiFailureActions(
  AnalysisRunFailure failure, {
  required bool canRetryLarger,
  required bool hasRaw,
}) {
  if (failure is RunUnexpected) return const [AiFailureAction.retry];
  if (failure is! RunModelFailure) return const [];
  if (canRetryLarger) return const [AiFailureAction.larger];
  return switch (failure.failure.kind) {
    AnalysisFailureKind.unauthorized ||
    AnalysisFailureKind.forbidden ||
    AnalysisFailureKind.modelNotFound => const [AiFailureAction.connection],
    AnalysisFailureKind.timeout || AnalysisFailureKind.refused => const [
      AiFailureAction.retry,
      AiFailureAction.connection,
    ],
    AnalysisFailureKind.unreadable => [
      AiFailureAction.retry,
      if (hasRaw) AiFailureAction.raw,
    ],
    _ => const [AiFailureAction.retry],
  };
}

/// A done answer whose every card failed the check (decision 9).
bool aiNoMatch(AiReport report) =>
    report.status == AiReportStatus.done &&
    report.droppedCards > 0 &&
    AiReading.fromReport(report).cards.isEmpty;
