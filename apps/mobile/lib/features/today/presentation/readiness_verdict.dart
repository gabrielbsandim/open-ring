import 'package:metrics/metrics.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

String readinessVerdict(AppLocalizations l10n, int score) =>
    switch (readinessBand(score)) {
      ReadinessBand.optimal => l10n.readinessVerdictOptimal,
      ReadinessBand.good => l10n.readinessVerdictGood,
      ReadinessBand.fair => l10n.readinessVerdictFair,
      ReadinessBand.low => l10n.readinessVerdictLow,
    };
