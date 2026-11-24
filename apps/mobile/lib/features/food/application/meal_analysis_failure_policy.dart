import 'dart:math';

import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';

/// Requests one tap may cost a photo: the first and one automatic resend.
const int aiPhotoMaxRequests = 2;

/// The wait before the next queued item after a run of 5xx or timeouts.
const List<Duration> aiPhotoBackoff = [
  Duration(minutes: 1),
  Duration(minutes: 5),
  Duration(minutes: 30),
];

Duration aiPhotoBackoffAfter(int failures) =>
    aiPhotoBackoff[min(max(failures, 1), aiPhotoBackoff.length) - 1];

/// The pause a failure sets, or null when it only touches its own row. Only
/// photo requests reach this, so a no vision 400 means the photo target.
AiPhotoQueuePauseReason? aiPhotoPauseReason(AnalysisFailure failure) {
  if (isNoVisionFailure(failure, imageRequest: true)) {
    return AiPhotoQueuePauseReason.noVision;
  }
  return switch (failure.kind) {
    AnalysisFailureKind.unauthorized => AiPhotoQueuePauseReason.unauthorized,
    AnalysisFailureKind.noCredit => AiPhotoQueuePauseReason.noCredit,
    AnalysisFailureKind.forbidden => AiPhotoQueuePauseReason.forbidden,
    _ => null,
  };
}

bool aiPhotoBacksOff(AnalysisFailureKind kind) =>
    kind == AnalysisFailureKind.serverError ||
    kind == AnalysisFailureKind.timeout;
