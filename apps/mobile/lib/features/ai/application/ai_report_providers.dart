import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';

final aiReportStoreProvider = Provider<AiReportStore>(
  (ref) => throw UnimplementedError('Override aiReportStoreProvider.'),
);

/// The newest finished reading for the saved host and model, from the store
/// only: opening the readings screen never calls the network.
final FutureProvider<AiReport?> aiLatestReadingProvider =
    FutureProvider.autoDispose((ref) async {
      final config = await ref.watch(aiConfigProvider.future);
      final reports = await ref.watch(aiReportStoreProvider).recent();
      return reports
          .where(
            (r) =>
                r.status == AiReportStatus.done &&
                r.providerHost == config.hostKey &&
                r.model == config.trimmedModel,
          )
          .firstOrNull;
    });
