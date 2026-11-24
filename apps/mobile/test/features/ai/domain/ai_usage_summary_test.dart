import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/ai_usage_summary.dart';

final _now = DateTime.utc(2026, 11, 24, 12);

AiReport _report({
  int daysAgo = 1,
  AiReportStatus status = AiReportStatus.done,
  int? input = 100,
  int? output = 50,
  double? cost,
  String? currency,
  AiCostSource source = AiCostSource.none,
  String host = 'https://openrouter.ai:443',
}) => AiReport(
  createdAtUtc: _now.subtract(Duration(days: daysAgo)),
  offsetMin: 0,
  kind: 'weekly_review',
  contextSchema: 'health_context_v2',
  contextSha256: 'sha',
  detailLevel: 'standard',
  promptVersion: 'v1',
  providerHost: host,
  model: 'm',
  status: status,
  promptTokens: input,
  completionTokens: output,
  cost: cost,
  costCurrency: currency,
  costSource: source,
);

void main() {
  test('sums tokens and readings inside the 30 day window only', () {
    final summary = aiUsageSummary([
      _report(),
      _report(daysAgo: 30),
      _report(daysAgo: 31, input: 9000, output: 9000),
    ], _now);
    expect(summary.readings, 2);
    expect(summary.tokensIn, 200);
    expect(summary.tokensOut, 100);
  });

  test('failed reports add tokens only when usage exists, never readings', () {
    final summary = aiUsageSummary([
      _report(),
      _report(status: AiReportStatus.failed, input: 40, output: 10),
      _report(status: AiReportStatus.cancelled, input: null, output: null),
    ], _now);
    expect(summary.readings, 1);
    expect(summary.tokensIn, 140);
    expect(summary.tokensOut, 60);
  });

  test('one currency and source sums the money', () {
    final summary = aiUsageSummary([
      _report(cost: 0.02, currency: 'USD', source: AiCostSource.userPrice),
      _report(cost: 0.03, currency: 'USD', source: AiCostSource.userPrice),
      _report(),
    ], _now);
    expect(summary.cost?.cost, closeTo(0.05, 1e-12));
    expect(summary.cost?.currency, 'USD');
    expect(summary.cost?.source, AiCostSource.userPrice);
  });

  test('provider credits carry their host', () {
    final summary = aiUsageSummary([
      _report(cost: 0.001, currency: 'credits', source: AiCostSource.provider),
    ], _now);
    expect(summary.costHost, 'openrouter.ai');
  });

  test('mixed currencies give no money total, tokens still count', () {
    final summary = aiUsageSummary([
      _report(cost: 0.02, currency: 'USD', source: AiCostSource.userPrice),
      _report(cost: 0.02, currency: 'EUR', source: AiCostSource.userPrice),
    ], _now);
    expect(summary.cost, isNull);
    expect(summary.tokensIn, 200);
  });

  test('mixed sources give no money total', () {
    final summary = aiUsageSummary([
      _report(cost: 0.02, currency: 'credits', source: AiCostSource.provider),
      _report(cost: 0.02, currency: 'credits', source: AiCostSource.userPrice),
    ], _now);
    expect(summary.cost, isNull);
  });

  test('credits from two hosts give no money total', () {
    final summary = aiUsageSummary([
      _report(cost: 0.02, currency: 'credits', source: AiCostSource.provider),
      _report(
        cost: 0.02,
        currency: 'credits',
        source: AiCostSource.provider,
        host: 'https://other.ai:443',
      ),
    ], _now);
    expect(summary.cost, isNull);
  });

  test('no costed report gives no money, never 0', () {
    expect(aiUsageSummary([_report()], _now).cost, isNull);
  });
}
