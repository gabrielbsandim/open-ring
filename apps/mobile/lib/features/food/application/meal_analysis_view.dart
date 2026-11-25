import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/vision_probe_runner.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';

enum MealAnalysisViewKind {
  demo,
  kept,
  none,
  queued,
  paused,
  sending,
  done,
  notFood,
  rejected,
  failed,
  skipped,
}

/// `reason` is the camelCase select case of the paused, failed or skipped
/// line; `failure` is set for a failed row the A9 lines can word.
typedef MealAnalysisView = ({
  MealAnalysisViewKind kind,
  MealAnalysis? row,
  String reason,
  AnalysisFailureKind? failure,
  bool capReached,
});

const Map<String, String> _reasonCases = {
  MealAnalysisErrorKind.expired: 'expired',
  MealAnalysisErrorKind.targetChanged: 'targetChanged',
  MealAnalysisErrorKind.interrupted: 'interrupted',
  MealAnalysisErrorKind.keptOnPhone: 'keptOnPhone',
  MealAnalysisErrorKind.noConsent: 'noConsent',
  MealAnalysisErrorKind.photoMissing: 'photoMissing',
  MealAnalysisErrorKind.urlRejected: 'urlRejected',
  MealAnalysisErrorKind.cancelled: 'cancelled',
  MealAnalysisErrorKind.unexpected: 'unexpected',
};

const Set<String> _photoStops = {
  MealAnalysisErrorKind.cancelled,
  MealAnalysisErrorKind.interrupted,
  MealAnalysisErrorKind.unexpected,
};

/// ICU select keys must be identifiers, while stored kinds are snake case.
String mealAnalysisReasonCase(String? kind) => _reasonCases[kind] ?? 'other';

// A name an older or newer build wrote must not throw, as byName would.
AnalysisFailureKind? _failureOf(String? kind) => _photoStops.contains(kind)
    ? null
    : AnalysisFailureKind.values.asNameMap()[kind];

/// What the meal screen draws for its latest analysis row. A skip the person
/// asked for reads as never analyzed.
MealAnalysisView mealAnalysisViewOf(
  MealAnalysis? row, {
  required bool keep,
  required AiPhotoQueuePause? pause,
  required int? sendingId,
  required bool capReached,
  required bool demo,
}) {
  MealAnalysisView view(
    MealAnalysisViewKind kind, [
    String reason = 'other',
    AnalysisFailureKind? failure,
  ]) => (
    kind: kind,
    row: row,
    reason: reason,
    failure: failure,
    capReached: capReached && kind == MealAnalysisViewKind.queued,
  );
  if (demo) return view(MealAnalysisViewKind.demo);
  if (keep) return view(MealAnalysisViewKind.kept);
  if (row == null) return view(MealAnalysisViewKind.none);
  if (row.id == sendingId) return view(MealAnalysisViewKind.sending);
  final reason = mealAnalysisReasonCase(row.errorKind);
  return switch (row.status) {
    MealAnalysisStatus.queued when pause != null => view(
      MealAnalysisViewKind.paused,
      pause.reason.name,
    ),
    MealAnalysisStatus.queued => view(MealAnalysisViewKind.queued),
    MealAnalysisStatus.sending => view(MealAnalysisViewKind.sending),
    MealAnalysisStatus.done => view(MealAnalysisViewKind.done),
    MealAnalysisStatus.notFood => view(MealAnalysisViewKind.notFood),
    MealAnalysisStatus.rejected => view(MealAnalysisViewKind.rejected),
    MealAnalysisStatus.failed => view(
      MealAnalysisViewKind.failed,
      reason,
      _failureOf(row.errorKind),
    ),
    MealAnalysisStatus.skipped
        when row.errorKind == MealAnalysisErrorKind.cancelled =>
      view(MealAnalysisViewKind.none),
    MealAnalysisStatus.skipped => view(MealAnalysisViewKind.skipped, reason),
  };
}

/// The stored pause while it holds for the current target, read from storage
/// so the screens are right before the first pass and after a key change.
final aiPhotoQueuePauseProvider = FutureProvider<AiPhotoQueuePause?>((
  ref,
) async {
  // Every queue change rereads it: Resume clears a pause the state never held.
  ref.watch(mealAnalysisQueueProvider);
  final config = await ref.watch(aiConfigProvider.future);
  final pause = await ref.read(aiConfigStoreProvider).readPhotoQueuePause();
  final holds =
      pause?.holds(
        hostKey: config.hostKey,
        model: aiPhotoTarget(config),
        keyLastFour: config.keyLastFour,
      ) ??
      false;
  return holds ? pause : null;
});

final mealPhotoQueuedCountProvider = FutureProvider<int>((ref) {
  ref.watch(mealAnalysisRevisionProvider);
  return ref.watch(mealAnalysisStoreProvider).countQueued();
});
