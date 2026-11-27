import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';

final aiReportStoreProvider = Provider<AiReportStore>(
  (ref) => throw UnimplementedError('Override aiReportStoreProvider.'),
);

/// Every stored report, newest first, from the store only: opening the
/// readings screen never calls the network.
final FutureProvider<List<AiReport>> aiRecentReportsProvider =
    FutureProvider.autoDispose(
      (ref) => ref.watch(aiReportStoreProvider).recent(),
    );

/// Stored reports of any status for the saved host and model, newest first.
final FutureProvider<List<AiReport>>
aiHostReportsProvider = FutureProvider.autoDispose((ref) async {
  final config = await ref.watch(aiConfigProvider.future);
  final reports = await ref.watch(aiRecentReportsProvider.future);
  return [
    for (final r in reports)
      if (r.providerHost == config.hostKey && r.model == config.trimmedModel) r,
  ];
});

final FutureProvider<AiReport?> aiLatestReadingProvider =
    FutureProvider.autoDispose(
      (ref) async =>
          (await ref.watch(aiHostReportsProvider.future))
              .where((r) => r.status == AiReportStatus.done)
              .firstOrNull,
    );
