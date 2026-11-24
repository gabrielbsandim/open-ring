import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/vision_probe_runner.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_run_state.dart';

/// What the stored profile says about the photo target. Only invalidated,
/// never written, so the trigger listening to it cannot loop.
final aiPhotoVisionProvider = FutureProvider<AiVisionSupport>((ref) async {
  final config = await ref.watch(aiConfigProvider.future);
  final host = config.hostKey;
  final target = aiPhotoTarget(config);
  if (host == null || target.isEmpty) return AiVisionSupport.unknown;
  final profile = await ref
      .read(aiConfigStoreProvider)
      .readCapabilityProfile(host, target);
  return profile?.vision ?? AiVisionSupport.unknown;
});

final visionProbeRandomProvider = Provider<Random>((_) => Random.secure());

typedef VisionProbeState = ({
  bool running,
  AiVisionSupport? result,
  AnalysisRunFailure? failure,
});

const VisionProbeState _idle = (running: false, result: null, failure: null);

/// Each probe costs a request, so Riverpod never retries it. Leaving the
/// screen disposes it, which aborts a probe in flight.
final NotifierProvider<VisionProbeController, VisionProbeState>
visionProbeControllerProvider =
    NotifierProvider.autoDispose<VisionProbeController, VisionProbeState>(
      VisionProbeController.new,
      retry: (_, _) => null,
    );

class VisionProbeController extends Notifier<VisionProbeState> {
  Completer<void>? _cancel;

  @override
  VisionProbeState build() {
    ref.onDispose(_abort);
    return _idle;
  }

  Future<void> run() async {
    if (state.running) return;
    final cancel = _cancel = Completer<void>();
    state = (running: true, result: null, failure: null);
    try {
      final seen = await runVisionProbe(
        ref,
        cancel: cancel.future,
        random: ref.read(visionProbeRandomProvider),
      );
      _finish(cancel, (running: false, result: seen, failure: null));
    } on AnalysisFailure catch (failure) {
      _finish(cancel, (
        running: false,
        result: null,
        failure: RunModelFailure(failure),
      ));
    } on Object catch (error) {
      _finish(cancel, (
        running: false,
        result: null,
        failure: RunUnexpected(error),
      ));
    }
  }

  void cancel() {
    if (!state.running) return;
    _abort();
    state = _idle;
  }

  void _abort() {
    final cancel = _cancel;
    _cancel = null;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
  }

  void _finish(Completer<void> run, VisionProbeState next) {
    if (!ref.mounted) return;
    ref.invalidate(aiPhotoVisionProvider);
    if (_cancel != run) return;
    _cancel = null;
    state = next;
  }
}
