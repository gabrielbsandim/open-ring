import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';

const String aiProviderCostCurrency = 'credits';
const int aiPriceTokens = 1000000;

typedef AiCost = ({double cost, String currency, AiCostSource source});

/// The provider's own figure wins; entered prices only fill in when it is
/// missing, and with neither there is no cost at all, never 0.
AiCost? aiReportCost(AiTokenUsage? usage, AiConfig config) {
  if (usage == null) return null;
  final reported = usage.providerCost;
  if (reported != null) {
    return (
      cost: reported,
      currency: aiProviderCostCurrency,
      source: AiCostSource.provider,
    );
  }
  final (inPrice, outPrice) = (
    config.inputPricePerMillion,
    config.outputPricePerMillion,
  );
  final (input, output) = (usage.promptTokens, usage.completionTokens);
  if (inPrice == null || outPrice == null) return null;
  if (input == null || output == null) return null;
  return (
    cost: input / aiPriceTokens * inPrice + output / aiPriceTokens * outPrice,
    currency: config.priceCurrency,
    source: AiCostSource.userPrice,
  );
}
