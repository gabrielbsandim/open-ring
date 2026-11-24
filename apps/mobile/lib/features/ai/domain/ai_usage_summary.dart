import 'package:open_ring/features/ai/domain/ai_cost.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';

const Duration aiUsageWindow = Duration(days: 30);

typedef AiUsageSummary = ({
  int readings,
  int tokensIn,
  int tokensOut,
  AiCost? cost,
  String costHost,
});

/// Money is summed only when every costed report shares one currency and
/// source (and host, for credits), since unlike amounts do not add.
AiUsageSummary aiUsageSummary(List<AiReport> reports, DateTime nowUtc) {
  final since = nowUtc.subtract(aiUsageWindow);
  final window = [
    for (final r in reports)
      if (!r.createdAtUtc.isBefore(since)) r,
  ];
  final costed = [
    for (final r in window)
      if (r.cost case final cost? when r.costSource != AiCostSource.none)
        (r, cost),
  ];
  final kinds = {
    for (final (r, _) in costed)
      (
        r.costCurrency ?? '',
        r.costSource,
        r.costSource == AiCostSource.provider ? _host(r) : '',
      ),
  };
  final total = kinds.length == 1
      ? (
          cost: costed.fold<double>(0, (sum, c) => sum + c.$2),
          currency: kinds.first.$1,
          source: kinds.first.$2,
        )
      : null;
  return (
    readings: window.where((r) => r.status == AiReportStatus.done).length,
    tokensIn: window.fold(0, (sum, r) => sum + (r.promptTokens ?? 0)),
    tokensOut: window.fold(0, (sum, r) => sum + (r.completionTokens ?? 0)),
    cost: total,
    costHost: kinds.length == 1 ? kinds.first.$3 : '',
  );
}

String _host(AiReport r) => Uri.tryParse(r.providerHost)?.host ?? '';
