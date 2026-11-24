import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/domain/ai_advanced_input.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/domain/vision_probe.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';

const _unreadable = AnalysisFailure(kind: AnalysisFailureKind.unreadable);

/// The model a photo goes to: the photo model when set, else the main one.
String aiPhotoTarget(AiConfig config) {
  final photo = config.photoModel?.trim() ?? '';
  return photo.isEmpty ? config.trimmedModel : photo;
}

/// Sends one probe image to the photo target and stores what it showed under
/// that model's capability profile. Returns null when nothing was sent: AI off,
/// demo mode, or no host or model. A failure other than a vision refusal
/// leaves the stored support as it was and is rethrown.
Future<AiVisionSupport?> runVisionProbe(
  Ref ref, {
  Future<void>? cancel,
  Random? random,
}) async {
  if (!ref.read(aiEnabledProvider) || ref.read(demoModeProvider)) return null;
  final config = await ref.read(aiConfigProvider.future);
  final host = config.hostKey;
  final target = aiPhotoTarget(config);
  if (host == null || target.isEmpty) return null;
  final store = ref.read(aiConfigStoreProvider);
  final key = await ref.read(secretStoreProvider).read(aiApiKeySecretName);
  final model = ref.read(keyedAnalysisModelFactoryProvider)(
    config.copyWith(model: target),
    key,
  );
  final grid = VisionProbeGrid.random(random ?? Random.secure());
  final request = visionProbeRequest(
    grid,
    maxOutputTokens: config.maxOutputTokens,
    profile:
        await store.readCapabilityProfile(host, target) ??
        AiCapabilityProfile.defaults,
    pin: aiOutputPin(config),
  );
  final AnalysisCompleted done;
  try {
    done = await _complete(model, request, cancel);
  } on AnalysisFailure catch (failure) {
    if (!isNoVisionFailure(failure, imageRequest: true)) rethrow;
    return await _store(ref, host, target, AiVisionSupport.no);
  }
  await _addTokens(ref, done.usage);
  final seen = switch (readVisionProbe(done.text, grid)) {
    VisionProbeResult.pass => AiVisionSupport.yes,
    VisionProbeResult.fail => AiVisionSupport.no,
    VisionProbeResult.unreadable => null,
  };
  if (seen == null) return AiVisionSupport.unknown;
  return await _store(ref, host, target, seen);
}

Future<AnalysisCompleted> _complete(
  AnalysisModel model,
  AnalysisRequest request,
  Future<void>? cancel,
) async {
  final event = await model
      .generate(request, cancel: cancel ?? Completer<void>().future)
      .firstWhere(
        (e) => e is AnalysisCompleted,
        orElse: () => throw _unreadable,
      );
  return event as AnalysisCompleted;
}

// Read again after the run, since the ladder may have stored what it learned.
Future<AiVisionSupport> _store(
  Ref ref,
  String host,
  String target,
  AiVisionSupport vision,
) async {
  final store = ref.read(aiConfigStoreProvider);
  final stored = await store.readCapabilityProfile(host, target);
  final profile = stored ?? AiCapabilityProfile.defaults;
  await store.writeCapabilityProfile(
    host,
    target,
    profile.copyWith(vision: vision),
  );
  return vision;
}

Future<void> _addTokens(Ref ref, AiTokenUsage? usage) async {
  final tokens = (usage?.promptTokens ?? 0) + (usage?.completionTokens ?? 0);
  final month = aiMonthKey(ref.read(clockProvider)());
  await ref.read(aiRunMarkerStoreProvider).addMonthTokens(month, tokens);
}
