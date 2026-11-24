import 'package:meta/meta.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';

const String aiSampleProviderHost = 'sample';

@immutable
sealed class AnalysisRunFailure {
  const new();
}

final class RunModelFailure extends AnalysisRunFailure {
  const new(this.failure);
  final AnalysisFailure failure;
}

final class RunNotEnoughData extends AnalysisRunFailure {
  const new(this.days);
  final int days;
}

final class RunUnexpected extends AnalysisRunFailure {
  const new(this.error);
  final Object error;
}

final class RunCeilingReached extends AnalysisRunFailure {
  const new({required this.used, required this.cap});
  final int used;
  final int cap;
}

@immutable
sealed class AnalysisRunState {
  const new();
}

final class AnalysisIdle extends AnalysisRunState {
  const new();
}

final class AnalysisSending extends AnalysisRunState {
  const new({required this.receivedChars, required this.startedAt});
  final int receivedChars;
  final DateTime startedAt;
}

final class AnalysisValidating extends AnalysisRunState {
  const new();
}

final class AnalysisDone extends AnalysisRunState {
  const new(this.report, {this.fromCache = false});
  final AiReport report;
  final bool fromCache;

  bool get isSample => report.providerHost == aiSampleProviderHost;
}

final class AnalysisFailed extends AnalysisRunState {
  const new(this.failure, {this.canRetryLarger = false});
  final AnalysisRunFailure failure;
  final bool canRetryLarger;
}

/// Run in flight (read back as cancelled) and a retention-proof month total.
abstract interface class AiRunMarkerStore {
  Future<AiReport?> read();
  Future<void> write(AiReport draft);
  Future<void> clear();
  Future<int> monthTokens(String month);
  Future<void> addMonthTokens(String month, int tokens);
}
