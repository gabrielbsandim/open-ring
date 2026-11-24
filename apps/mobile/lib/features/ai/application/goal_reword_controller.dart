import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/domain/ai_advanced_input.dart';
import 'package:open_ring/features/ai/domain/ai_consent_scope.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/ai_report_models.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/analysis_run_state.dart';
import 'package:open_ring/features/ai/domain/goal_reword.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/domain/openai_wire_codec.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';

const _cancelled = AnalysisFailure(kind: AnalysisFailureKind.cancelled);
const _unreadable = AnalysisFailure(kind: AnalysisFailureKind.unreadable);

/// Every state names the payload it belongs to, so a rewording is never
/// shown under a different decision.
sealed class GoalRewordState {
  const new(this.key);
  final String? key;
}

final class GoalRewordIdle extends GoalRewordState {
  const new() : super(null);
}

final class GoalRewordSending extends GoalRewordState {
  const new(super.key);
}

final class GoalRewordShown extends GoalRewordState {
  const new(super.key, {required this.text, required this.model});
  final String text;
  final String model;
}

final class GoalRewordDropped extends GoalRewordState {
  const new(super.key, {required this.reason, required this.model});
  final AiCardDropReason reason;
  final String model;
}

final class GoalRewordFailed extends GoalRewordState {
  const new(super.key, this.failure);
  final AnalysisRunFailure failure;
}

// Disposed with the review screen, which aborts a send in flight, so a
// result never outlives the screen or Delete all data.
final NotifierProvider<GoalRewordController, GoalRewordState>
goalRewordControllerProvider =
    NotifierProvider.autoDispose<GoalRewordController, GoalRewordState>(
      GoalRewordController.new,
      retry: (_, _) => null,
    );

class GoalRewordController extends Notifier<GoalRewordState> {
  bool _busy = false;
  Completer<void> _cancel = Completer<void>();

  @override
  GoalRewordState build() {
    ref.onDispose(cancel);
    return const GoalRewordIdle();
  }

  void cancel() {
    if (!_cancel.isCompleted) _cancel.complete();
  }

  Future<void> send(BuiltAiPayload payload) async {
    if (_busy || !ref.read(aiEnabledProvider)) return;
    if (ref.read(demoModeProvider)) return;
    _busy = true;
    _cancel = Completer<void>();
    final key = payload.cacheKey;
    try {
      _set(await _run(payload, key));
    } on AnalysisFailure catch (failure) {
      final shown = _cancel.isCompleted ? _cancelled : failure;
      _set(GoalRewordFailed(key, RunModelFailure(shown)));
    } on Object catch (error) {
      _set(GoalRewordFailed(key, RunUnexpected(error)));
    } finally {
      _busy = false;
    }
  }

  Future<GoalRewordState> _run(BuiltAiPayload payload, String key) async {
    final config = await ref.read(aiConfigProvider.future);
    final store = ref.read(aiConfigStoreProvider);
    final consent = await store.readConsent();
    final host = config.hostKey;
    if (host == null || config.trimmedModel.isEmpty) {
      return const GoalRewordIdle();
    }
    if (!aiConsentCoversPayload(consent, config, payload)) {
      return GoalRewordFailed(key, const RunConsentNeeded());
    }
    final markers = ref.read(aiRunMarkerStoreProvider);
    final month = aiMonthKey(ref.read(clockProvider)());
    final cap = config.monthlyTokenCap;
    final used = cap == null ? 0 : await markers.monthTokens(month);
    if (cap != null && used >= cap) {
      return GoalRewordFailed(key, RunCeilingReached(used: used, cap: cap));
    }
    final model = await ref.read(analysisModelFactoryProvider)(config);
    final profile = await store.readCapabilityProfile(
      host,
      config.trimmedModel,
    );
    _set(GoalRewordSending(key));
    final done = await _generate(
      model,
      AnalysisRequest(
        systemPrompt: payload.systemPrompt,
        userContent: AiTextContent(payload.userMessage),
        maxOutputTokens: config.maxOutputTokens,
        profile: profile ?? AiCapabilityProfile.defaults,
        pin: aiOutputPin(config),
        jsonSchema: aiReportOutputSchema,
        reasoningEffort: config.reasoningEffort,
      ),
    );
    final usage = done.usage;
    final tokens = (usage?.promptTokens ?? 0) + (usage?.completionTokens ?? 0);
    await markers.addMonthTokens(month, tokens);
    final name = config.trimmedModel;
    return switch (readGoalReword(done.text, payload)) {
      AiRewordAccepted(:final text) => GoalRewordShown(
        key,
        text: text,
        model: name,
      ),
      AiRewordDropped(:final reason) => GoalRewordDropped(
        key,
        reason: reason,
        model: name,
      ),
      null => GoalRewordFailed(key, const RunModelFailure(_unreadable)),
    };
  }

  Future<AnalysisCompleted> _generate(
    AnalysisModel model,
    AnalysisRequest request,
  ) async {
    final done = model
        .generate(request, cancel: _cancel.future)
        .firstWhere(
          (e) => e is AnalysisCompleted,
          orElse: () => throw _unreadable,
        );
    final stop = _cancel.future.then<AnalysisEvent>((_) => throw _cancelled);
    final event = await Future.any([done, stop]);
    if (event is! AnalysisCompleted) throw _unreadable;
    return event;
  }

  void _set(GoalRewordState next) {
    if (ref.mounted) state = next;
  }
}
