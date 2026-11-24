import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

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

typedef MealAnalysisQueueState = ({int? sendingId, bool capReached});

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
  bool _dead = false;
  bool _background = false;
  bool _running = false;
  bool _again = false;
  Completer<void> _cancel = Completer<void>();
  Future<void> _lock = Future.value();
  late DateTime Function() _clock;

  /// Settles when the pass in flight, if any, has finished or aborted.
  Future<void> idle = Future.value();

  @override
  MealAnalysisQueueState build() {
    _clock = ref.read(clockProvider);
    ref.onDispose(() {
      _dead = true;
      _abort();
    });
    return (sendingId: null, capReached: false);
  }

  bool get _awake => !_dead && !_background;

  /// Calls run one at a time, so the daily check and its count are atomic.
  Future<EnqueueOutcome> enqueue(int mealId, {bool again = false}) {
    final run = _lock.then((_) => _enqueue(mealId, again: again));
    _lock = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<EnqueueOutcome> _enqueue(int mealId, {required bool again}) async {
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
        .where(
          (r) =>
              r.target.providerHost == target.providerHost &&
              r.target.model == target.model &&
              r.target.promptVersion == target.promptVersion,
        )
        .firstOrNull;
    final writes = _writesQueue(current, photo, target, again: again);
    final day = aiPhotoDayKey(_clock());
    final used = await markers.photoUses(day);
    if (writes && used >= gate.config.photoDailyLimit) {
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
    if (writes) await markers.addPhotoUses(day, 1);
    unawaited(drain().catchError((Object _) {}));
    return EnqueueOutcome.queued;
  }

  /// A queued row is skipped and gives its use back. The row being sent is
  /// aborted and kept as failed, since the provider may still bill it.
  Future<void> cancel(int id) async {
    if (state.sendingId == id) {
      _abort();
      return;
    }
    final analyses = ref.read(mealAnalysisStoreProvider);
    final row = await analyses.byId(id);
    if (row == null) return;
    final now = _clock();
    final skipped = await analyses.skip(
      id,
      MealAnalysisErrorKind.cancelled,
      now: now,
    );
    if (!skipped && state.sendingId == id) _abort();
    if (!skipped) return;
    final day = aiPhotoDayKey(row.queuedAt.toLocal());
    if (day != aiPhotoDayKey(now)) return;
    await ref.read(aiRunMarkerStoreProvider).addPhotoUses(day, -1);
  }

  void toBackground() => _background = true;

  void toForeground() => _background = false;

  /// A call during a pass asks for one more pass instead of running beside
  /// it, so two requests are never in flight.
  Future<void> drain() {
    if (_running) {
      _again = true;
      return idle;
    }
    _running = true;
    _dead = false;
    return idle = _loop();
  }

  Future<void> _loop() async {
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
    MealAnalysis row,
    _Ready gate,
    Uint8List stored,
  ) async {
    final markers = ref.read(aiRunMarkerStoreProvider);
    final language = ref.read(aiReplyLanguageProvider);
    final wire = await ref.read(wirePhotoEncoderProvider)(stored);
    // The encode takes up to a second, so everything is checked again.
    final fresh = await _gate();
    if (fresh is! _Ready || _targetOf(fresh) != _targetOf(gate) || !_awake) {
      throw _notNow;
    }
    if (await _skipReason(analyses, row) != null) throw _notNow;
    final config = fresh.config;
    final model = ref.read(keyedAnalysisModelFactoryProvider)(
      config.copyWith(model: fresh.model),
      fresh.key,
    );
    final done = await _generate(
      model,
      buildMealPhotoRequest(
        base64Encode(wire.bytes),
        withItems: false,
        replyLanguage: language,
        maxOutputTokens: config.maxOutputTokens,
        profile: fresh.profile,
        pin: aiOutputPin(config),
      ),
    );
    final usage = done.usage;
    final tokens = (usage?.promptTokens ?? 0) + (usage?.completionTokens ?? 0);
    await markers.addMonthTokens(aiMonthKey(_clock()), tokens);
    final outcome = MealPhotoValidator.read(
      done.text,
      shortEdgePx: wire.shortEdge,
      withItems: false,
      replyLanguage: language,
    );
    if (_dead) return;
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

  // Mirrors the store: a row already queued or sending, or an answer it
  // hands back, writes no new queue entry and uses nothing of the day.
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

  void _abort() {
    if (!_cancel.isCompleted) _cancel.complete();
  }

  void _set({required int? sendingId}) {
    if (!ref.mounted) return;
    state = (sendingId: sendingId, capReached: state.capReached);
  }
}
