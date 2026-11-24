import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
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
import 'package:open_ring/features/food/application/meal_analysis_failure_policy.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/domain/meal_analysis_store.dart';

const Duration aiPhotoSendSpacing = Duration(seconds: 1);
const Duration aiPhotoQueueExpiry = Duration(days: 7);

const _cancelled = AnalysisFailure(kind: AnalysisFailureKind.cancelled);
const _unreadable = AnalysisFailure(kind: AnalysisFailureKind.unreadable);
// Handled like unreachable: the row goes back to queued, uncounted.
const _notNow = AnalysisFailure(kind: AnalysisFailureKind.unreachable);

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

/// The pause is the stored one while it still holds for the current target.
typedef MealAnalysisQueueState = ({
  int? sendingId,
  bool capReached,
  AiPhotoQueuePause? pause,
});

typedef WirePhotoEncoder = Future<WirePhoto> Function(Uint8List stored);

final wirePhotoEncoderProvider = Provider<WirePhotoEncoder>(
  (ref) =>
      (stored) => Isolate.run(() => prepareWirePhoto(stored)),
);

/// The local day a photo use counts toward; [offset] defaults to the zone of
/// [instant].
String aiPhotoDayKey(DateTime instant, [Duration? offset]) =>
    LocalDate.fromInstant(instant, offset ?? instant.timeZoneOffset).iso;

// A null retry falls back to Riverpod's default, which retries; a paid
// request must never be resent by the framework.
final mealAnalysisQueueProvider =
    NotifierProvider<MealAnalysisQueue, MealAnalysisQueueState>(
      MealAnalysisQueue.new,
      retry: (_, _) => null,
    );

enum _Closed { badUrl }

enum _Step { stop, next, sent }

typedef _Ready = ({
  AiConfig config,
  String host,
  String model,
  String? key,
  AiCapabilityProfile profile,
});

MealAnalysisTarget _targetOf(_Ready gate) => (
  providerHost: gate.host,
  model: gate.model,
  promptVersion: aiMealPromptVersion,
  outputSchema: mealPhotoOutputSchemaVersion(withItems: false),
);

/// Sends queued meal photos one at a time while the app is in the
/// foreground. A pass in the background starts no new request.
class MealAnalysisQueue extends Notifier<MealAnalysisQueueState> {
  // Disposal bumps the epoch; a pass or enqueue of an older epoch is dead.
  int _epoch = 0;
  int _runEpoch = -1;
  bool _alive = false;
  bool _background = false;
  bool _running = false;
  bool _again = false;
  Completer<void> _cancel = Completer<void>();
  Future<void> _lock = Future.value();
  Future<void> _drained = Future.value();
  late DateTime Function() _clock;
  // In memory on purpose: a restart starts the backoff over.
  int _failures = 0;
  DateTime? _holdUntil;

  /// Settles, never with an error, once the pass and the enqueue or cancel
  /// in flight have finished or aborted.
  Future<void> get idle => Future.wait([_drained, _lock]);

  @override
  MealAnalysisQueueState build() {
    _clock = ref.read(clockProvider);
    _alive = true;
    ref.onDispose(() {
      _epoch++;
      _alive = false;
      _abort();
    });
    return (sendingId: null, capReached: false, pause: null);
  }

  bool get _dead => _runEpoch != _epoch;

  bool get _awake => !_dead && !_background;

  void toBackground() => _background = true;

  void toForeground() => _background = false;

  // Enqueues and cancels run one at a time, so a daily check and its count
  // never interleave with another counter write.
  Future<T> _serial<T>(Future<T> Function() body) {
    final run = _lock.then((_) => body());
    _lock = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<EnqueueOutcome> enqueue(int mealId, {bool again = false}) =>
      _serial(() => _enqueue(mealId, _epoch, again: again));

  Future<EnqueueOutcome> _enqueue(
    int mealId,
    int epoch, {
    required bool again,
  }) async {
    final gate = await _gate();
    if (gate is! _Ready) {
      return gate is EnqueueOutcome ? gate : EnqueueOutcome.unavailable;
    }
    final photo = (await ref.read(mealStoreProvider).byId(mealId))?.photo;
    if (photo == null) return EnqueueOutcome.noPhoto;
    final analyses = ref.read(mealAnalysisStoreProvider);
    final markers = ref.read(aiRunMarkerStoreProvider);
    if (await analyses.keepOnPhone(mealId)) return EnqueueOutcome.keptOnPhone;
    final target = _targetOf(gate);
    final current = (await analyses.byMeal(mealId))
        .where((r) => _sameKey(r.target, target))
        .firstOrNull;
    final writes = _writesQueue(current, photo, target, again: again);
    final day = aiPhotoDayKey(_clock());
    final used = await markers.photoUses(day);
    if (writes && used >= gate.config.photoDailyLimit) {
      return EnqueueOutcome.dailyLimit;
    }
    if (epoch != _epoch) return EnqueueOutcome.unavailable;
    final row = await analyses.enqueue(
      mealId,
      photo,
      target,
      now: _clock(),
      again: again,
    );
    if (row.status.isAnswer) return EnqueueOutcome.cached;
    if (writes && epoch == _epoch) await markers.addPhotoUses(day, 1);
    unawaited(drain());
    return EnqueueOutcome.queued;
  }

  /// A queued row is skipped and gives its use back. The row being sent is
  /// aborted and kept as failed, since the provider may still bill it.
  Future<void> cancel(int id) => _serial(() async {
    if (state.sendingId == id) return _abort();
    final analyses = ref.read(mealAnalysisStoreProvider);
    final row = await analyses.byId(id);
    final now = _clock();
    const cancelled = MealAnalysisErrorKind.cancelled;
    final skipped = await analyses.skip(id, cancelled, now: now);
    if (!skipped && state.sendingId == id) _abort();
    final day = aiPhotoDayKey(row?.queuedAt.toLocal() ?? now);
    if (!skipped || row == null || day != aiPhotoDayKey(now)) return;
    await ref.read(aiRunMarkerStoreProvider).addPhotoUses(day, -1);
  });

  /// Lifts the pause, whatever its reason, and sends what is queued.
  Future<void> resume() async {
    await ref.read(aiConfigStoreProvider).clearPhotoQueuePause();
    _setPause(null);
    await drain();
  }

  /// A failed or rejected row goes back to queued without a new daily use.
  Future<bool> retry(int id) async {
    final analyses = ref.read(mealAnalysisStoreProvider);
    if (!await analyses.retry(id, now: _clock())) return false;
    unawaited(drain());
    return true;
  }

  /// A call during a pass asks for one more pass instead of running beside
  /// it, so two requests are never in flight.
  Future<void> drain() {
    if (_running) {
      _again = true;
      return _drained;
    }
    if (!_alive) return _drained;
    _running = true;
    _runEpoch = _epoch;
    return _drained = _loop();
  }

  // Any failure, such as a read after disposal, only ends the pass.
  Future<void> _loop() async {
    try {
      do {
        _again = false;
        await _pass();
      } while (_again && _awake);
    } on Object catch (error) {
      debugPrint('Meal analysis pass failed: $error');
    } finally {
      _running = false;
    }
  }

  Future<void> _pass() async {
    if (!_awake) return;
    final analyses = ref.read(mealAnalysisStoreProvider);
    await analyses.recoverInterrupted(now: _clock());
    var step = await _step(analyses);
    while (step != _Step.stop) {
      if (step == _Step.sent) await Future<void>.delayed(aiPhotoSendSpacing);
      step = await _step(analyses);
    }
  }

  Future<_Step> _step(MealAnalysisStore analyses) async {
    if (!_awake) return _Step.stop;
    final gate = await _gate();
    if (await _paused()) return _Step.stop;
    final now = _clock();
    final closed = switch (gate) {
      _Closed.badUrl => MealAnalysisErrorKind.urlRejected,
      EnqueueOutcome.noPhotoConsent => MealAnalysisErrorKind.noConsent,
      _ => null,
    };
    if (gate is _Ready) {
      await analyses.expireBefore(now.subtract(aiPhotoQueueExpiry), now: now);
      await analyses.skipOffTarget(gate.host, gate.model, now: now);
    }
    final open = gate is _Ready || closed != null;
    final row = open ? await analyses.next() : null;
    if (row == null || _dead) return _Step.stop;
    final stored = await ref.read(photoStoreProvider).read(row.photoName);
    final reason =
        closed ??
        await _skipReason(analyses, row) ??
        (stored == null ? MealAnalysisErrorKind.photoMissing : null);
    if (reason != null) {
      await analyses.skip(row.id, reason, now: now);
      return _Step.next;
    }
    if (gate is! _Ready || stored == null) return _Step.stop;
    if (await _capReached(gate.config) || !_awake) return _Step.stop;
    await _holdOff();
    if (!_awake) return _Step.stop;
    return await _send(analyses, row, gate, stored);
  }

  // Null while the row may still go; checked again right before generate.
  Future<String?> _skipReason(
    MealAnalysisStore analyses,
    MealAnalysis row,
  ) async {
    if (await analyses.keepOnPhone(row.mealId)) {
      return MealAnalysisErrorKind.keptOnPhone;
    }
    final meal = await ref.read(mealStoreProvider).byId(row.mealId);
    if (meal?.photo == row.photoName) return null;
    return MealAnalysisErrorKind.photoMissing;
  }

  Future<_Step> _send(
    MealAnalysisStore analyses,
    MealAnalysis row,
    _Ready gate,
    Uint8List stored,
  ) async {
    _cancel = Completer<void>();
    _set(sendingId: row.id);
    try {
      if (!await analyses.markSending(row.id, now: _clock())) {
        return _Step.next;
      }
      await _request(analyses, row, gate, stored);
      _failures = 0;
      _holdUntil = null;
      return _Step.sent;
    } on AnalysisFailure catch (failure) {
      if (_dead) return _Step.stop;
      return await _failed(analyses, row, gate, failure);
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

  /// Unreachable, the pause reasons and a cancel touch no backoff; 5xx and
  /// timeouts hold the next item back.
  Future<_Step> _failed(
    MealAnalysisStore analyses,
    MealAnalysis row,
    _Ready gate,
    AnalysisFailure failure,
  ) async {
    final now = _clock();
    final kind = _cancel.isCompleted
        ? AnalysisFailureKind.cancelled
        : failure.kind;
    final reason = kind == AnalysisFailureKind.cancelled
        ? null
        : aiPhotoPauseReason(failure);
    if (reason != null) await _pause(reason, gate, now);
    if (reason != null || kind == AnalysisFailureKind.unreachable) {
      await analyses.requeue(row.id, now: now);
      return _Step.stop;
    }
    if (aiPhotoBacksOff(kind)) {
      _holdUntil = now.add(aiPhotoBackoffAfter(++_failures));
    }
    await analyses.fail(row.id, kind.name, now: now);
    return _Step.sent;
  }

  Future<void> _pause(
    AiPhotoQueuePauseReason reason,
    _Ready gate,
    DateTime now,
  ) async {
    final store = ref.read(aiConfigStoreProvider);
    if (reason == AiPhotoQueuePauseReason.noVision) {
      final stored = await store.readCapabilityProfile(gate.host, gate.model);
      final profile = stored ?? AiCapabilityProfile.defaults;
      await store.writeCapabilityProfile(
        gate.host,
        gate.model,
        profile.copyWith(vision: AiVisionSupport.no),
      );
    }
    if (_dead) return;
    final pause = AiPhotoQueuePause(
      reason: reason,
      hostKey: gate.host,
      model: gate.model,
      keyLastFour: gate.config.keyLastFour,
      atUtcMs: now.toUtc().millisecondsSinceEpoch,
    );
    await store.writePhotoQueuePause(pause);
    _setPause(pause);
  }

  Future<bool> _paused() async {
    final config = await ref.read(aiConfigProvider.future);
    final store = ref.read(aiConfigStoreProvider);
    final pause = await store.readPhotoQueuePause();
    final holds =
        pause?.holds(
          hostKey: config.hostKey,
          model: aiPhotoTarget(config),
          keyLastFour: config.keyLastFour,
        ) ??
        false;
    _setPause(holds ? pause : null);
    return holds;
  }

  // Ends early on Delete all data, which completes the cancel.
  Future<void> _holdOff() async {
    final left = _holdUntil?.difference(_clock()) ?? Duration.zero;
    if (left <= Duration.zero) return;
    _cancel = Completer<void>();
    await Future.any([Future<void>.delayed(left), _cancel.future]);
    _holdUntil = null;
  }

  /// The encode takes up to a second, so everything is checked again; null
  /// when the row may not go now.
  Future<_Ready?> _stillGoes(
    MealAnalysisStore analyses,
    MealAnalysis row,
    _Ready gate,
  ) async {
    final fresh = await _gate();
    if (fresh is! _Ready || _targetOf(fresh) != _targetOf(gate)) return null;
    if (fresh.config.keyLastFour != gate.config.keyLastFour) return null;
    if (!_awake || await _skipReason(analyses, row) != null) return null;
    return fresh;
  }

  // A second request goes out only while nothing changed and no cancel came.
  Future<bool> _resends(
    MealAnalysisStore analyses,
    MealAnalysis row,
    _Ready gate,
  ) async {
    if (_cancel.isCompleted) return false;
    if (await _stillGoes(analyses, row, gate) == null) return false;
    return await analyses.countResend(row.id, now: _clock());
  }

  Future<void> _request(
    MealAnalysisStore analyses,
    MealAnalysis row,
    _Ready gate,
    Uint8List stored,
  ) async {
    final markers = ref.read(aiRunMarkerStoreProvider);
    final language = ref.read(aiReplyLanguageProvider);
    final wire = await ref.read(wirePhotoEncoderProvider)(stored);
    final fresh = await _stillGoes(analyses, row, gate);
    if (fresh == null) throw _notNow;
    final config = fresh.config;
    final model = ref.read(keyedAnalysisModelFactoryProvider)(
      config.copyWith(model: fresh.model),
      fresh.key,
    );
    final request = buildMealPhotoRequest(
      base64Encode(wire.bytes),
      withItems: false,
      replyLanguage: language,
      maxOutputTokens: config.maxOutputTokens,
      profile: fresh.profile,
      pin: aiOutputPin(config),
    );
    var sent = 0;
    AnalysisCompleted? done;
    MealPhotoOutcome? outcome;
    while (done == null) {
      sent++;
      try {
        done = await _generate(model, request);
      } on AnalysisFailure catch (failure) {
        final wait = sent < aiPhotoMaxRequests
            ? aiAutoRetryWait(failure)
            : null;
        if (wait == null) rethrow;
        await Future.any([Future<void>.delayed(wait), _cancel.future]);
        if (!await _resends(analyses, row, gate)) rethrow;
        continue;
      }
      final usage = done.usage;
      final tokens =
          (usage?.promptTokens ?? 0) + (usage?.completionTokens ?? 0);
      await markers.addMonthTokens(aiMonthKey(_clock()), tokens);
      outcome = MealPhotoValidator.read(
        done.text,
        shortEdgePx: wire.shortEdge,
        withItems: false,
        replyLanguage: language,
      );
      final again = outcome is MealPhotoRejected && sent < aiPhotoMaxRequests;
      if (again && await _resends(analyses, row, gate)) done = null;
    }
    if (_dead || outcome == null) return;
    final usage = done.usage;
    await analyses.complete(row.id, (
      status: switch (outcome) {
        MealPhotoDone() => MealAnalysisStatus.done,
        MealPhotoNotFood() => MealAnalysisStatus.notFood,
        MealPhotoRejected() => MealAnalysisStatus.rejected,
      },
      sent: (
        sha256: wire.sha256,
        width: wire.width,
        height: wire.height,
        bytes: wire.bytes.length,
      ),
      suggestion: outcome is MealPhotoDone ? outcome.suggestion : null,
      confidence: outcome is MealPhotoDone ? outcome.confidence : null,
      rawText: done.text,
      usage: usage,
      cost: aiReportCost(usage, config),
      errorKind: outcome is MealPhotoRejected ? outcome.reason.name : null,
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

  /// A [_Ready] gate, or why nothing may be sent now.
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
    const date = aiCurrentPolicyEffectiveDate;
    if (consent?.covers(hostKey: host, policyEffectiveDate: date) != true) {
      return EnqueueOutcome.noPhotoConsent;
    }
    final profile =
        await store.readCapabilityProfile(host, model) ??
        AiCapabilityProfile.defaults;
    return switch (profile.vision) {
      AiVisionSupport.yes => (
        config: config,
        host: host,
        model: model,
        key: key,
        profile: profile,
      ),
      AiVisionSupport.no => EnqueueOutcome.visionNo,
      AiVisionSupport.unknown => EnqueueOutcome.visionUntested,
    };
  }

  // Mirrors the store: it writes, and so moves queued_at, unless the row is
  // sending or the same photo and target is queued or cached.
  static bool _writesQueue(
    MealAnalysis? row,
    String photo,
    MealAnalysisTarget target, {
    required bool again,
  }) {
    if (row == null) return true;
    final same = row.photoName == photo && row.target == target;
    final status = row.status;
    final reuse =
        status == MealAnalysisStatus.queued || status.isAnswer && !again;
    return status != MealAnalysisStatus.sending && !(same && reuse);
  }

  static bool _sameKey(MealAnalysisTarget a, MealAnalysisTarget b) =>
      (a.providerHost, a.model, a.promptVersion) ==
      (b.providerHost, b.model, b.promptVersion);

  Future<bool> _capReached(AiConfig config) async {
    final cap = config.monthlyTokenCap;
    final markers = ref.read(aiRunMarkerStoreProvider);
    final used = cap == null
        ? 0
        : await markers.monthTokens(aiMonthKey(_clock()));
    final reached = cap != null && used >= cap;
    if (ref.mounted) {
      state = (
        sendingId: state.sendingId,
        capReached: reached,
        pause: state.pause,
      );
    }
    return reached;
  }

  void _abort() {
    if (!_cancel.isCompleted) _cancel.complete();
  }

  void _set({required int? sendingId}) {
    if (!ref.mounted) return;
    state = (
      sendingId: sendingId,
      capReached: state.capReached,
      pause: state.pause,
    );
  }

  void _setPause(AiPhotoQueuePause? pause) {
    if (!ref.mounted) return;
    state = (
      sendingId: state.sendingId,
      capReached: state.capReached,
      pause: pause,
    );
  }
}
