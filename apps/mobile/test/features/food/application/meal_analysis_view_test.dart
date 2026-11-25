import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/food/application/meal_analysis_view.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';

import 'meal_analysis_harness.dart';

final _at = DateTime.utc(2026, 11, 24, 12);

MealAnalysis _row(MealAnalysisStatus status, {String? errorKind, int id = 7}) =>
    (
      id: id,
      mealId: 1,
      photoName: 'meal_1.jpg',
      status: status,
      target: photoTarget,
      queuedAt: _at,
      updatedAt: _at,
      sent: null,
      resultJson: null,
      rawText: null,
      confidence: null,
      attempts: 0,
      errorKind: errorKind,
      hiddenOil: false,
      hiddenSauce: false,
      hiddenSugar: false,
      items: const [],
    );

AiPhotoQueuePause _pause(AiPhotoQueuePauseReason reason) => AiPhotoQueuePause(
  reason: reason,
  hostKey: hostKey,
  model: photoModel,
  keyLastFour: '1234',
  atUtcMs: 0,
);

MealAnalysisView _view(
  MealAnalysis? row, {
  bool keep = false,
  AiPhotoQueuePause? pause,
  int? sendingId,
  bool capReached = false,
  bool demo = false,
}) => mealAnalysisViewOf(
  row,
  keep: keep,
  pause: pause,
  sendingId: sendingId,
  capReached: capReached,
  demo: demo,
);

void main() {
  const errorKinds = [
    MealAnalysisErrorKind.expired,
    MealAnalysisErrorKind.targetChanged,
    MealAnalysisErrorKind.interrupted,
    MealAnalysisErrorKind.keptOnPhone,
    MealAnalysisErrorKind.noConsent,
    MealAnalysisErrorKind.photoMissing,
    MealAnalysisErrorKind.urlRejected,
    MealAnalysisErrorKind.cancelled,
    MealAnalysisErrorKind.unexpected,
  ];

  test('every stored error kind maps to its camelCase select case', () {
    expect(
      {for (final k in errorKinds) k: mealAnalysisReasonCase(k)},
      {
        'expired': 'expired',
        'target_changed': 'targetChanged',
        'interrupted': 'interrupted',
        'kept_on_phone': 'keptOnPhone',
        'no_consent': 'noConsent',
        'photo_missing': 'photoMissing',
        'url_rejected': 'urlRejected',
        'cancelled': 'cancelled',
        'unexpected': 'unexpected',
      },
    );
    for (final k in errorKinds) {
      expect(mealAnalysisReasonCase(k), matches(RegExp(r'^[a-z][A-Za-z]*$')));
    }
    expect(mealAnalysisReasonCase('from_a_newer_build'), 'other');
    expect(mealAnalysisReasonCase(null), 'other');
  });

  test('demo wins over keep and any row; keep wins over every row', () {
    final row = _row(MealAnalysisStatus.done);
    expect(_view(row, demo: true, keep: true).kind, MealAnalysisViewKind.demo);
    expect(_view(row, keep: true).kind, MealAnalysisViewKind.kept);
    expect(_view(null, keep: true).kind, MealAnalysisViewKind.kept);
    final queued = _row(MealAnalysisStatus.queued);
    expect(_view(queued, keep: true).kind, MealAnalysisViewKind.kept);
    expect(
      _view(queued, keep: true, sendingId: queued.id).kind,
      MealAnalysisViewKind.kept,
    );
    final sending = _row(MealAnalysisStatus.sending);
    expect(_view(sending, keep: true).kind, MealAnalysisViewKind.kept);
  });

  test('a queued row behind a closed gate names why, unless paused', () {
    final row = _row(MealAnalysisStatus.queued);
    for (final closed in [
      EnqueueOutcome.unavailable,
      EnqueueOutcome.visionUntested,
      EnqueueOutcome.visionNo,
    ]) {
      final view = mealAnalysisViewOf(
        row,
        keep: false,
        pause: null,
        sendingId: null,
        capReached: false,
        demo: false,
        closed: closed,
      );
      expect(
        (view.kind, view.reason),
        (MealAnalysisViewKind.closed, closed.name),
      );
    }
    final paused = mealAnalysisViewOf(
      row,
      keep: false,
      pause: _pause(AiPhotoQueuePauseReason.noVision),
      sendingId: null,
      capReached: false,
      demo: false,
      closed: EnqueueOutcome.visionNo,
    );
    expect(paused.kind, MealAnalysisViewKind.paused);
    final done = mealAnalysisViewOf(
      _row(MealAnalysisStatus.done),
      keep: false,
      pause: null,
      sendingId: null,
      capReached: false,
      demo: false,
      closed: EnqueueOutcome.unavailable,
    );
    expect(done.kind, MealAnalysisViewKind.done);
  });

  test('no row, or a skip the person asked for, reads as not analyzed', () {
    expect(_view(null).kind, MealAnalysisViewKind.none);
    final cancelled = _row(
      MealAnalysisStatus.skipped,
      errorKind: MealAnalysisErrorKind.cancelled,
    );
    expect(_view(cancelled).kind, MealAnalysisViewKind.none);
  });

  test('each status maps to its view', () {
    expect(
      {
        for (final s in MealAnalysisStatus.values)
          s: _view(_row(s, errorKind: 'timeout')).kind,
      },
      {
        MealAnalysisStatus.queued: MealAnalysisViewKind.queued,
        MealAnalysisStatus.sending: MealAnalysisViewKind.sending,
        MealAnalysisStatus.done: MealAnalysisViewKind.done,
        MealAnalysisStatus.notFood: MealAnalysisViewKind.notFood,
        MealAnalysisStatus.rejected: MealAnalysisViewKind.rejected,
        MealAnalysisStatus.failed: MealAnalysisViewKind.failed,
        MealAnalysisStatus.skipped: MealAnalysisViewKind.skipped,
      },
    );
  });

  test('the row the queue is sending reads as sending before its write', () {
    final row = _row(MealAnalysisStatus.queued);
    expect(_view(row, sendingId: 7).kind, MealAnalysisViewKind.sending);
    expect(_view(row, sendingId: 8).kind, MealAnalysisViewKind.queued);
  });

  test('the monthly cap shows only on a queued row', () {
    final queued = _view(_row(MealAnalysisStatus.queued), capReached: true);
    expect(queued.capReached, isTrue);
    final done = _view(_row(MealAnalysisStatus.done), capReached: true);
    expect(done.capReached, isFalse);
  });

  test('a queued row under a holding pause reads paused with its reason', () {
    for (final reason in AiPhotoQueuePauseReason.values) {
      final view = _view(
        _row(MealAnalysisStatus.queued),
        pause: _pause(reason),
      );
      expect(
        (view.kind, view.reason),
        (MealAnalysisViewKind.paused, reason.name),
      );
    }
    final failed = _view(
      _row(MealAnalysisStatus.failed, errorKind: 'timeout'),
      pause: _pause(AiPhotoQueuePauseReason.unauthorized),
    );
    expect(failed.kind, MealAnalysisViewKind.failed);
  });

  test('a failed row carries the A9 kind, or the photo wording', () {
    MealAnalysisView failed(String? kind) =>
        _view(_row(MealAnalysisStatus.failed, errorKind: kind));
    for (final kind in AnalysisFailureKind.values) {
      if (kind == AnalysisFailureKind.cancelled) continue;
      expect(failed(kind.name).failure, kind, reason: kind.name);
    }
    expect(
      (failed('cancelled').failure, failed('cancelled').reason),
      (null, 'cancelled'),
    );
    expect(
      (failed('interrupted').failure, failed('interrupted').reason),
      (null, 'interrupted'),
    );
    expect(failed('unexpected').failure, isNull);
    expect(
      (failed('gone_kind').failure, failed('gone_kind').reason),
      (null, 'other'),
    );
    expect(failed(null).failure, isNull);
  });

  test('a skipped row carries its camelCase reason', () {
    const reasons = {
      MealAnalysisErrorKind.expired: 'expired',
      MealAnalysisErrorKind.keptOnPhone: 'keptOnPhone',
      MealAnalysisErrorKind.noConsent: 'noConsent',
      MealAnalysisErrorKind.photoMissing: 'photoMissing',
      MealAnalysisErrorKind.targetChanged: 'targetChanged',
      MealAnalysisErrorKind.urlRejected: 'urlRejected',
    };
    for (final MapEntry(:key, :value) in reasons.entries) {
      final view = _view(_row(MealAnalysisStatus.skipped, errorKind: key));
      expect((view.kind, view.reason), (MealAnalysisViewKind.skipped, value));
    }
  });
}
