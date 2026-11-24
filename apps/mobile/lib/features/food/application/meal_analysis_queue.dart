import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/application/health_context_providers.dart';
import 'package:open_ring/features/ai/application/vision_probe_runner.dart';
import 'package:open_ring/features/ai/domain/ai_advanced_input.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_cost.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/meal_photo_prompt.dart';
import 'package:open_ring/features/ai/domain/meal_photo_validator.dart';
import 'package:open_ring/features/ai/domain/meal_photo_wire.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/domain/meal_analysis_store.dart';

const Duration aiPhotoSendSpacing = Duration(seconds: 1);
const Duration aiPhotoQueueExpiry = Duration(days: 7);

const _cancelled = AnalysisFailure(kind: AnalysisFailureKind.cancelled);
const _unreadable = AnalysisFailure(kind: AnalysisFailureKind.unreadable);

enum EnqueueOutcome {
  queued,
  cached,
  dailyLimit,
  keptOnPhone,
  noPhoto,
  unavailable,
  noPhotoConsent,
  visionUntested,
  visionNo,
  demo,
}

typedef MealAnalysisQueueState = ({int? sendingId, bool capReached});

typedef WirePhotoEncoder = Future<WirePhoto> Function(Uint8List stored);

final wirePhotoEncoderProvider = Provider<WirePhotoEncoder>(
  (ref) =>
      (stored) => Isolate.run(() => prepareWirePhoto(stored)),
);

// A null retry falls back to Riverpod's default, which retries; a paid
// request must never be resent by the framework.
final mealAnalysisQueueProvider =
    NotifierProvider<MealAnalysisQueue, MealAnalysisQueueState>(
      MealAnalysisQueue.new,
      retry: (_, _) => null,
    );

enum _Closed { badUrl }

enum _Step { stop, next, sent }

final class _Ready {
  const new(
    this.config,
    this.host,
    this.model,
    this.key,
    this.profile, {
    required this.consented,
  });

  final AiConfig config;
  final String host;
  final String model;
  final String? key;
  final AiCapabilityProfile profile;
  final bool consented;

  bool get sees => profile.vision == AiVisionSupport.yes;

  MealAnalysisTarget get target => (
    providerHost: host,
    model: model,
    promptVersion: aiMealPromptVersion,
    outputSchema: mealPhotoOutputSchemaVersion(withItems: false),
  );
}

/// Sends queued meal photos one at a time while the app is in the
/// foreground. A pass in the background starts no new request.
class MealAnalysisQueue extends Notifier<MealAnalysisQueueState> {
  bool _dead = false;
  bool _background = false;
  bool _running = false;
  bool _again = false;
  Completer<void> _cancel = Completer<void>();
  late DateTime Function() _clock;

  @override
  MealAnalysisQueueState build() {
    _dead = false;
    _clock = ref.read(clockProvider);
    ref.onDispose(() {
      _dead = true;
      _abort();
    });
    return (sendingId: null, capReached: false);
  }

  bool get _awake => !_dead && !_background;

  Future<EnqueueOutcome> enqueue(int mealId, {bool again = false}) async {
    final gate = await _gate();
    if (gate is! _Ready) {
      return gate is EnqueueOutcome ? gate : EnqueueOutcome.unavailable;
    }
    if (!gate.consented) return EnqueueOutcome.noPhotoConsent;
    final vision = switch (gate.profile.vision) {
      AiVisionSupport.yes => null,
      AiVisionSupport.no => EnqueueOutcome.visionNo,
      AiVisionSupport.unknown => EnqueueOutcome.visionUntested,
    };
    if (vision != null) return vision;
    final photo = (await ref.read(mealStoreProvider).byId(mealId))?.photo;
    if (photo == null) return EnqueueOutcome.noPhoto;
    final analyses = ref.read(mealAnalysisStoreProvider);
    if (await analyses.keepOnPhone(mealId)) return EnqueueOutcome.keptOnPhone;
    final target = gate.target;
    final current = (await analyses.byMeal(mealId))
        .where(
          (r) =>
              r.target.providerHost == target.providerHost &&
              r.target.model == target.model &&
              r.target.promptVersion == target.promptVersion,
        )
        .firstOrNull;
    final writes = _writesQueue(current, photo, target, again: again);
    if (writes && await _dailyFull(analyses, gate.config)) {
      return EnqueueOutcome.dailyLimit;
    }
    final row = await analyses.enqueue(
      mealId,
      photo,
      target,
      now: _clock(),
      again: again,
    );
    if (row.status.isAnswer) return EnqueueOutcome.cached;
    unawaited(drain().catchError((Object _) {}));
    return EnqueueOutcome.queued;
  }

  /// A queued row is skipped and leaves the daily count. The row in flight
  /// is aborted and kept as failed, since the provider may still bill it.
  Future<void> cancel(int id) async {
    if (state.sendingId == id) {
      _abort();
      return;
    }
    await ref
        .read(mealAnalysisStoreProvider)
        .skip(id, MealAnalysisErrorKind.cancelled, now: _clock());
  }

  void toBackground() => _background = true;

  void toForeground() => _background = false;

  /// A call during a pass asks for one more pass instead of running beside
  /// it, so two requests are never in flight.
  Future<void> drain() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _pass();
      } while (_again && _awake);
    } finally {
      _running = false;
    }
  }

  Future<void> _pass() async {
    if (!_awake) return;
    final gate = await _gate();
    if (gate is! _Ready || !gate.sees) return await _skipRejectedUrl(gate);
    final analyses = ref.read(mealAnalysisStoreProvider);
    await analyses.recoverInterrupted(now: _clock());
    var step = await _step(analyses);
    while (step != _Step.stop) {
      if (step == _Step.sent) await Future<void>.delayed(aiPhotoSendSpacing);
      step = await _step(analyses);
    }
  }

  Future<void> _skipRejectedUrl(Object gate) async {
    if (gate != _Closed.badUrl) return;
    final analyses = ref.read(mealAnalysisStoreProvider);
    for (var row = await analyses.next(); row != null && !_dead;) {
      await analyses.skip(
        row.id,
        MealAnalysisErrorKind.urlRejected,
        now: _clock(),
      );
      row = await analyses.next();
    }
  }

  Future<_Step> _step(MealAnalysisStore analyses) async {
    if (!_awake) return _Step.stop;
    final gate = await _gate();
    if (gate is! _Ready || !gate.sees || _dead) return _Step.stop;
    final now = _clock();
    await analyses.expireBefore(now.subtract(aiPhotoQueueExpiry), now: now);
    await analyses.skipOffTarget(gate.host, gate.model, now: now);
    final row = await analyses.next();
    if (row == null || await _capReached(gate.config)) return _Step.stop;
    if (await analyses.keepOnPhone(row.mealId)) {
      return await _skip(analyses, row, MealAnalysisErrorKind.keptOnPhone);
    }
    if (!gate.consented) {
      return await _skip(analyses, row, MealAnalysisErrorKind.noConsent);
    }
    final stored = await _photo(row);
    if (stored == null) {
      return await _skip(analyses, row, MealAnalysisErrorKind.photoMissing);
    }
    if (!_awake) return _Step.stop;
    return await _send(analyses, row, gate, stored);
  }

  Future<_Step> _skip(
    MealAnalysisStore analyses,
    MealAnalysis row,
    String reason,
  ) async {
    await analyses.skip(row.id, reason, now: _clock());
    return _Step.next;
  }

  Future<_Step> _send(
    MealAnalysisStore analyses,
    MealAnalysis row,
    _Ready gate,
    Uint8List stored,
  ) async {
    if (!await analyses.markSending(row.id, now: _clock())) return _Step.next;
    _cancel = Completer<void>();
    _set(sendingId: row.id);
    try {
      await _request(analyses, row.id, gate, stored);
      return _Step.sent;
    } on AnalysisFailure catch (failure) {
      if (_dead) return _Step.stop;
      final kind = _cancel.isCompleted
          ? AnalysisFailureKind.cancelled
          : failure.kind;
      if (kind != AnalysisFailureKind.unreachable) {
        await analyses.fail(row.id, kind.name, now: _clock());
        return _Step.sent;
      }
      // No network: the row waits for the next trigger, uncounted.
      await analyses.requeue(row.id, now: _clock());
      return _Step.stop;
    } on Object {
      if (_dead) return _Step.stop;
      await analyses.fail(
        row.id,
        MealAnalysisErrorKind.unexpected,
        now: _clock(),
      );
      return _Step.sent;
    } finally {
      _set(sendingId: null);
    }
  }

  Future<void> _request(
    MealAnalysisStore analyses,
    int id,
    _Ready gate,
    Uint8List stored,
  ) async {
    final config = gate.config;
    final markers = ref.read(aiRunMarkerStoreProvider);
    final language = ref.read(aiReplyLanguageProvider);
    final model = ref.read(keyedAnalysisModelFactoryProvider)(
      config.copyWith(model: gate.model),
      gate.key,
    );
    final wire = await ref.read(wirePhotoEncoderProvider)(stored);
    final request = buildMealPhotoRequest(
      base64Encode(wire.bytes),
      withItems: false,
      replyLanguage: language,
      maxOutputTokens: config.maxOutputTokens,
      profile: gate.profile,
      pin: aiOutputPin(config),
    );
    final done = await _generate(model, request);
    final usage = done.usage;
    final tokens = (usage?.promptTokens ?? 0) + (usage?.completionTokens ?? 0);
    await markers.addMonthTokens(aiMonthKey(_clock()), tokens);
    final (
      status,
      suggestion,
      confidence,
      error,
    ) = switch (MealPhotoValidator.read(
      done.text,
      shortEdgePx: wire.shortEdge,
      withItems: false,
      replyLanguage: language,
    )) {
      MealPhotoDone(:final suggestion, :final confidence) => (
        MealAnalysisStatus.done,
        suggestion,
        confidence,
        null,
      ),
      MealPhotoNotFood() => (MealAnalysisStatus.notFood, null, null, null),
      MealPhotoRejected(:final reason) => (
        MealAnalysisStatus.rejected,
        null,
        null,
        reason.name,
      ),
    };
    if (_dead) return;
    await analyses.complete(id, (
      status: status,
      sent: (
        sha256: wire.sha256,
        width: wire.width,
        height: wire.height,
        bytes: wire.bytes.length,
      ),
      suggestion: suggestion,
      confidence: confidence,
      rawText: done.text,
      usage: usage,
      cost: aiReportCost(usage, config),
      errorKind: error,
    ), now: _clock());
  }

  Future<AnalysisCompleted> _generate(
    AnalysisModel model,
    AnalysisRequest request,
  ) async {
    if (_cancel.isCompleted) throw _cancelled;
    final done = model
        .generate(request, cancel: _cancel.future)
        .firstWhere(
          (e) => e is AnalysisCompleted,
          orElse: () => throw _unreadable,
        );
    final stop = _cancel.future.then<AnalysisEvent>((_) => throw _cancelled);
    return await Future.any([done, stop]) as AnalysisCompleted;
  }

  Future<Object> _gate() async {
    if (!ref.read(aiEnabledProvider) || !ref.read(foodEnabledProvider)) {
      return EnqueueOutcome.unavailable;
    }
    if (ref.read(demoModeProvider)) return EnqueueOutcome.demo;
    final store = ref.read(aiConfigStoreProvider);
    final secrets = ref.read(secretStoreProvider);
    final config = await ref.read(aiConfigProvider.future);
    final host = config.hostKey;
    if (host == null && config.baseUrl.trim().isNotEmpty) return _Closed.badUrl;
    final key = await secrets.read(aiApiKeySecretName);
    final keyed = !config.preset.keyRequired || (key?.isNotEmpty ?? false);
    if (host == null || !keyed || !config.isTestedForCurrentTarget) {
      return EnqueueOutcome.unavailable;
    }
    final model = aiPhotoTarget(config);
    final consent = await store.readMealPhotoConsent();
    final profile = await store.readCapabilityProfile(host, model);
    return _Ready(
      config,
      host,
      model,
      key,
      profile ?? AiCapabilityProfile.defaults,
      consented:
          consent?.covers(
            hostKey: host,
            policyEffectiveDate: aiCurrentPolicyEffectiveDate,
          ) ??
          false,
    );
  }

  // Mirrors the store: a row already queued or sending, or an answer it
  // hands back, writes no new queue entry and never meets the daily limit.
  static bool _writesQueue(
    MealAnalysis? row,
    String photo,
    MealAnalysisTarget target, {
    required bool again,
  }) {
    if (row == null) return true;
    final status = row.status;
    if (status == MealAnalysisStatus.queued) return false;
    if (status == MealAnalysisStatus.sending) return false;
    return again ||
        !status.isAnswer ||
        row.photoName != photo ||
        row.target != target;
  }

  Future<bool> _dailyFull(MealAnalysisStore analyses, AiConfig config) async {
    final local = _clock().toLocal();
    final midnight = DateTime(local.year, local.month, local.day);
    return await analyses.countQueuedSince(midnight) >= config.photoDailyLimit;
  }

  Future<bool> _capReached(AiConfig config) async {
    final cap = config.monthlyTokenCap;
    final markers = ref.read(aiRunMarkerStoreProvider);
    final used = cap == null
        ? 0
        : await markers.monthTokens(aiMonthKey(_clock()));
    final reached = cap != null && used >= cap;
    if (ref.mounted) state = (sendingId: state.sendingId, capReached: reached);
    return reached;
  }

  Future<Uint8List?> _photo(MealAnalysis row) async {
    final meal = await ref.read(mealStoreProvider).byId(row.mealId);
    if (meal?.photo != row.photoName) return null;
    return await ref.read(photoStoreProvider).read(row.photoName);
  }

  void _abort() {
    if (!_cancel.isCompleted) _cancel.complete();
  }

  void _set({required int? sendingId}) {
    if (!ref.mounted) return;
    state = (sendingId: sendingId, capReached: state.capReached);
  }
}
