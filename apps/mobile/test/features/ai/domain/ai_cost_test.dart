import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_cost.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';

const _priced = AiConfig(inputPricePerMillion: 3, outputPricePerMillion: 15);

const _usage = AiTokenUsage(promptTokens: 1776, completionTokens: 1180);

void main() {
  test('the A7e formula on 1,776 in and 1,180 out', () {
    final cost = aiReportCost(_usage, _priced)!;
    expect(cost.cost, closeTo(1776 / 1e6 * 3 + 1180 / 1e6 * 15, 1e-12));
    expect(cost.cost, closeTo(0.023028, 1e-9));
    expect(cost.currency, 'USD');
    expect(cost.source, AiCostSource.userPrice);
  });

  test('the provider cost wins over entered prices', () {
    const usage = AiTokenUsage(
      promptTokens: 1776,
      completionTokens: 1180,
      providerCost: 0.0031,
    );
    expect(aiReportCost(usage, _priced), (
      cost: 0.0031,
      currency: 'credits',
      source: AiCostSource.provider,
    ));
  });

  test('a provider cost needs no prices', () {
    const usage = AiTokenUsage(providerCost: 0.5);
    expect(
      aiReportCost(usage, AiConfig.defaults)?.source,
      AiCostSource.provider,
    );
  });

  group('prices need both values and both token counts', () {
    test('only the input price gives none', () {
      const config = AiConfig(inputPricePerMillion: 3);
      expect(aiReportCost(_usage, config), isNull);
    });

    test('only the output price gives none', () {
      const config = AiConfig(outputPricePerMillion: 15);
      expect(aiReportCost(_usage, config), isNull);
    });

    test('a missing completion count gives none', () {
      const usage = AiTokenUsage(promptTokens: 1776);
      expect(aiReportCost(usage, _priced), isNull);
    });

    test('a missing prompt count gives none', () {
      const usage = AiTokenUsage(completionTokens: 1180);
      expect(aiReportCost(usage, _priced), isNull);
    });
  });

  test('no usage gives none, never 0', () {
    expect(aiReportCost(null, _priced), isNull);
  });
}
