import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/meal_photo_prompt.dart';
import 'package:open_ring/features/ai/domain/meal_photo_result.dart';
import 'package:open_ring/features/ai/domain/meal_photo_wire.dart';
import 'package:open_ring/features/ai/domain/openai_wire_codec.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';

import '../../../helpers/database.dart';
import '../../ai/wire_jpeg_fixture.dart';
import 'meal_analysis_harness.dart';

void main() {
  late MealQueueHarness h;

  setUp(() => h = MealQueueHarness());

  Future<(MealAnalysisStatus, String?)> statusOf(int mealId) async {
    final row = await h.row(mealId);
    return (row.status, row.errorKind);
  }

  group('acceptance 1: the daily limit', () {
    String today() => aiPhotoDayKey(h.now);

    Future<EnqueueOutcome> next() async {
      await h.start();
      h.queue.toBackground();
      return await h.queue.enqueue(await h.meal(photo: 'meal_next.jpg'));
    }

    test('with 8 uses today the next enqueue returns dailyLimit and writes '
        'no row', () async {
      await h.markers.addPhotoUses(today(), 8);

      expect(await next(), EnqueueOutcome.dailyLimit);
      expect(await rowCount(h.db, 'meal_analyses'), 0);
    });

    test('8 enqueues pass and the 9th returns dailyLimit', () async {
      await h.start();
      h.queue.toBackground();
      for (var i = 0; i < 8; i++) {
        final id = await h.meal(photo: 'meal_$i.jpg');
        expect(await h.queue.enqueue(id), EnqueueOutcome.queued);
      }

      expect(await next(), EnqueueOutcome.dailyLimit);
      expect(await h.markers.photoUses(today()), 8);
    });

    test("yesterday's uses do not count", () async {
      await h.markers.addPhotoUses(
        aiPhotoDayKey(h.now.subtract(const Duration(days: 1))),
        8,
      );

      expect(await next(), EnqueueOutcome.queued);
    });

    test('the day key is the date at the local offset, not in UTC (a UTC '
        'runner cannot move its own zone, so the offset is passed in)', () {
      final instant = DateTime.utc(2026, 11, 24, 2, 30);

      expect(aiPhotoDayKey(instant, const Duration(hours: -3)), '2026-11-23');
      expect(aiPhotoDayKey(instant, const Duration(hours: 1)), '2026-11-24');
      expect(
        aiPhotoDayKey(
          DateTime.utc(2026, 11, 23, 23, 30),
          const Duration(hours: 1),
        ),
        '2026-11-24',
      );
    });

    test('a cancelled queued row gives its use back', () async {
      h.configStore.config = testedConfig.copyWith(photoDailyLimit: 2);
      await h.start();
      h.queue.toBackground();
      await h.queue.enqueue(await h.meal());
      final second = await h.meal(photo: 'meal_2.jpg');
      await h.queue.enqueue(second);

      await h.queue.cancel((await h.row(second)).id);

      expect(await next(), EnqueueOutcome.queued);
    });

    test('photoDailyLimit 3 caps at 3', () async {
      h.configStore.config = testedConfig.copyWith(photoDailyLimit: 3);
      await h.markers.addPhotoUses(today(), 3);

      expect(await next(), EnqueueOutcome.dailyLimit);
    });

    test('an out of range stored limit falls back to 8', () async {
      h.configStore.config = AiConfig.fromJson({
        ...testedConfig.toJson(),
        'photoDailyLimit': 99,
      });
      await h.markers.addPhotoUses(today(), 7);

      expect(await next(), EnqueueOutcome.queued);
      expect(
        await h.queue.enqueue(await h.meal(photo: 'meal_ninth.jpg')),
        EnqueueOutcome.dailyLimit,
      );
    });

    test('again counts as a use, so it cannot pass the limit', () async {
      h.configStore.config = testedConfig.copyWith(photoDailyLimit: 3);
      await h.start();
      final mealId = await h.meal();
      expect(await h.queue.enqueue(mealId), EnqueueOutcome.queued);
      await h.queue.drain();
      for (var i = 0; i < 2; i++) {
        expect(
          await h.queue.enqueue(mealId, again: true),
          EnqueueOutcome.queued,
        );
        await h.queue.drain();
      }

      expect(
        await h.queue.enqueue(mealId, again: true),
        EnqueueOutcome.dailyLimit,
      );
      expect((await h.row(mealId)).status, MealAnalysisStatus.done);
    });

    test('two enqueues at once with 7 of 8 used: one queued, one '
        'dailyLimit', () async {
      await h.markers.addPhotoUses(today(), 7);
      await h.start();
      h.queue.toBackground();
      final a = await h.meal();
      final b = await h.meal(photo: 'meal_2.jpg');

      final outcomes = await Future.wait([
        h.queue.enqueue(a),
        h.queue.enqueue(b),
      ]);

      expect(outcomes, [EnqueueOutcome.queued, EnqueueOutcome.dailyLimit]);
      expect(await rowCount(h.db, 'meal_analyses'), 1);
    });

    test('a cached answer comes back without using the day', () async {
      await h.start();
      final mealId = await h.meal();
      final id = await h.queued(mealId);
      await h.queue.drain();
      await h.markers.addPhotoUses(today(), 8);
      h.queue.toBackground();

      expect(await h.queue.enqueue(mealId), EnqueueOutcome.cached);
      expect((await h.row(mealId)).id, id);
      expect(h.requests, hasLength(1));
    });
  });

  group('acceptance 2: queued rows skip without a request', () {
    Future<void> drained() async {
      await h.start();
      await h.queue.drain();
      expect(h.requests, isEmpty);
    }

    test('a row queued 7 days and 1 minute ago expires', () async {
      final mealId = await h.meal();
      await h.queued(
        mealId,
        at: h.now.subtract(const Duration(days: 7, minutes: 1)),
      );

      await drained();

      expect(await statusOf(mealId), (MealAnalysisStatus.skipped, 'expired'));
    });

    test('a row for another model is skipped as target_changed', () async {
      final mealId = await h.meal();
      await h.queued(
        mealId,
        target: (
          providerHost: hostKey,
          model: 'old-m',
          promptVersion: aiMealPromptVersion,
          outputSchema: 1,
        ),
      );

      await drained();

      expect(await statusOf(mealId), (
        MealAnalysisStatus.skipped,
        'target_changed',
      ));
    });

    test('keep on phone turned on after the enqueue skips the row', () async {
      final mealId = await h.meal();
      await h.queued(mealId);
      await h.analyses.setKeepOnPhone(mealId, keep: true);

      await drained();

      expect(await statusOf(mealId), (
        MealAnalysisStatus.skipped,
        'kept_on_phone',
      ));
    });

    test('a withdrawn photo consent skips the row', () async {
      final mealId = await h.meal();
      await h.queued(mealId);
      await h.configStore.clearMealPhotoConsent();

      await drained();

      expect(await statusOf(mealId), (
        MealAnalysisStatus.skipped,
        'no_consent',
      ));
    });

    test('a deleted photo skips the row', () async {
      final mealId = await h.meal();
      await h.queued(mealId);
      await h.photos.delete('meal_1.jpg');

      await drained();

      expect(await statusOf(mealId), (
        MealAnalysisStatus.skipped,
        'photo_missing',
      ));
    });

    test('a stored address the policy rejects skips the row', () async {
      final mealId = await h.meal();
      await h.queued(mealId);
      h.configStore.config = testedConfig.copyWith(
        baseUrl: 'http://api.example.com/v1',
      );

      await drained();

      expect(await statusOf(mealId), (
        MealAnalysisStatus.skipped,
        'url_rejected',
      ));
    });
  });

  group('acceptance 3: lifecycle', () {
    test('a pass in the background sends nothing and resume drains', () async {
      final mealId = await h.meal();
      await h.queued(mealId);
      await h.start();
      h.queue.toBackground();

      await h.queue.drain();
      expect(h.requests, isEmpty);
      expect(await statusOf(mealId), (MealAnalysisStatus.queued, null));

      h.queue.toForeground();
      await h.queue.drain();
      expect(h.requests, hasLength(1));
      expect((await h.row(mealId)).status, MealAnalysisStatus.done);
    });

    test('two queued rows are sent 1 s apart, never concurrently', () {
      fakeAsync((async) {
        h.elapsed = () => async.elapsed;
        void settle(Future<void> f) {
          var done = false;
          unawaited(f.then((_) => done = true));
          for (var i = 0; i < 50 && !done; i++) {
            async.elapse(const Duration(milliseconds: 100));
          }
          expect(done, isTrue);
        }

        settle(() async {
          await h.queued(await h.meal());
          await h.queued(await h.meal(photo: 'meal_2.jpg'));
          await h.start();
        }());
        final start = async.elapsed;
        settle(h.queue.drain());

        expect(h.sentAt.map((t) => t - start), [
          Duration.zero,
          aiPhotoSendSpacing,
        ]);
        expect(h.maxInFlight, 1);
      });
    });

    test('demo mode sends nothing', () async {
      h.demo = true;
      final mealId = await h.meal();
      await h.queued(mealId);
      await h.start();

      await h.queue.drain();

      expect(h.requests, isEmpty);
      expect(await h.queue.enqueue(mealId), EnqueueOutcome.demo);
    });

    test('AI off sends nothing', () async {
      h.modules = {ModuleId.food};
      final mealId = await h.meal();
      await h.queued(mealId);
      await h.start();

      await h.queue.drain();

      expect(h.requests, isEmpty);
      expect(await h.queue.enqueue(mealId), EnqueueOutcome.unavailable);
    });

    test('unreachable leaves the row queued with no attempt and ends the '
        'pass', () async {
      h.respond = () =>
          throw const AnalysisFailure(kind: AnalysisFailureKind.unreachable);
      final first = await h.meal();
      final second = await h.meal(photo: 'meal_2.jpg');
      await h.queued(first);
      await h.queued(second, at: h.now.add(const Duration(seconds: 1)));
      await h.start();

      await h.queue.drain();

      expect(h.requests, hasLength(1));
      final row = await h.row(first);
      expect((row.status, row.attempts), (MealAnalysisStatus.queued, 0));
    });

    test('any other failure fails the row with its kind', () async {
      h.respond = () =>
          throw const AnalysisFailure(kind: AnalysisFailureKind.serverError);
      final mealId = await h.meal();
      await h.queued(mealId);
      await h.start();

      await h.queue.drain();

      expect(await statusOf(mealId), (
        MealAnalysisStatus.failed,
        'serverError',
      ));
    });
  });

  group('acceptance 4: a sent photo', () {
    test(
      'the model gets the wire photo and the row stores the answer',
      () async {
        final mealId = await h.meal();
        await h.queued(mealId);
        await h.start();

        await h.queue.drain();

        final wire = prepareWirePhoto(leakyPhoto());
        final request = h.requests.single;
        final content = request.userContent as AiImageContent;
        expect(content.base64Jpeg, base64Encode(wire.bytes));
        expect(request.schemaName, aiMealSchemaName);
        final row = await h.row(mealId);
        expect(row.status, MealAnalysisStatus.done);
        expect(row.attempts, 1);
        expect(row.sent, (
          sha256: wire.sha256,
          width: wire.width,
          height: wire.height,
          bytes: wire.bytes.length,
        ));
        expect(row.confidence, MealPhotoConfidence.medium);
        expect(row.suggestion?.kind, MealPhotoKind.main);
        final stored = await h.db.select(h.db.mealAnalyses).getSingle();
        expect((stored.promptTokens, stored.completionTokens), (300, 20));
        expect(h.markers.monthSum, 320);
        expect(h.markers.month, aiMonthKey(h.now));
      },
    );

    test('a not food answer is stored as not_food', () async {
      h.respond = () => completed(mealAnswer(isFood: 'no'));
      final mealId = await h.meal();
      await h.queued(mealId);
      await h.start();

      await h.queue.drain();

      expect((await h.row(mealId)).status, MealAnalysisStatus.notFood);
    });

    test('with the monthly cap reached nothing is sent and rows stay '
        'queued', () async {
      h.configStore.config = testedConfig.copyWith(monthlyTokenCap: 1000);
      h.markers
        ..month = aiMonthKey(h.now)
        ..monthSum = 1000;
      final mealId = await h.meal();
      await h.queued(mealId);
      await h.start();

      await h.queue.drain();

      expect(h.requests, isEmpty);
      expect(await statusOf(mealId), (MealAnalysisStatus.queued, null));
      expect(h.container.read(mealAnalysisQueueProvider).capReached, isTrue);
    });
  });

  group('acceptance 5: enqueue outcomes that write no row', () {
    Future<EnqueueOutcome> enqueue() async {
      final mealId = await h.meal();
      await h.start();
      return await h.queue.enqueue(mealId);
    }

    void vision(AiVisionSupport support) =>
        h.configStore.profiles[aiCapabilityProfileKey(hostKey, photoModel)] =
            AiCapabilityProfile(vision: support);

    test('vision unknown returns visionUntested', () async {
      vision(AiVisionSupport.unknown);

      expect(await enqueue(), EnqueueOutcome.visionUntested);
      expect(await rowCount(h.db, 'meal_analyses'), 0);
    });

    test('no stored profile returns visionUntested', () async {
      h.configStore.profiles.clear();

      expect(await enqueue(), EnqueueOutcome.visionUntested);
      expect(await rowCount(h.db, 'meal_analyses'), 0);
    });

    test('vision no returns visionNo', () async {
      vision(AiVisionSupport.no);

      expect(await enqueue(), EnqueueOutcome.visionNo);
      expect(await rowCount(h.db, 'meal_analyses'), 0);
    });

    test('no photo consent returns noPhotoConsent', () async {
      h.configStore.mealPhotoConsent = null;

      expect(await enqueue(), EnqueueOutcome.noPhotoConsent);
      expect(await rowCount(h.db, 'meal_analyses'), 0);
    });

    test('an untested target returns unavailable', () async {
      h.configStore.config = testedConfig.copyWith(clearTested: true);

      expect(await enqueue(), EnqueueOutcome.unavailable);
      expect(await rowCount(h.db, 'meal_analyses'), 0);
    });

    test('a meal kept on phone returns keptOnPhone', () async {
      final mealId = await h.meal();
      await h.analyses.setKeepOnPhone(mealId, keep: true);
      await h.start();

      expect(await h.queue.enqueue(mealId), EnqueueOutcome.keptOnPhone);
      expect(await rowCount(h.db, 'meal_analyses'), 0);
    });
  });

  group('cancel', () {
    test('a queued row becomes skipped and leaves the daily count', () async {
      final mealId = await h.meal();
      final id = await h.queued(mealId);
      await h.start();

      await h.queue.cancel(id);

      expect(await statusOf(mealId), (MealAnalysisStatus.skipped, 'cancelled'));
      expect(await h.analyses.countQueuedSince(h.now), 0);
    });

    test('the row in flight aborts, fails as cancelled and counts', () async {
      final answer = Completer<AnalysisEvent>();
      h.respond = () => answer.future;
      final mealId = await h.meal();
      final id = await h.queued(mealId);
      await h.start();

      final pass = h.queue.drain();
      while (h.container.read(mealAnalysisQueueProvider).sendingId != id) {
        await Future<void>.delayed(Duration.zero);
      }
      await h.queue.cancel(id);
      await pass;

      expect(await statusOf(mealId), (MealAnalysisStatus.failed, 'cancelled'));
      expect(await h.analyses.countQueuedSince(h.now), 1);
    });
  });

  group('the send time checks', () {
    Future<(int, Future<void>)> encoding() async {
      h.encodeGate = Completer<void>();
      final mealId = await h.meal();
      await h.queued(mealId);
      await h.start();
      final pass = h.queue.drain();
      await pumpEventQueue();
      return (mealId, pass);
    }

    Future<void> expectRequeued(int mealId, Future<void> pass) async {
      h.encodeGate!.complete();
      await pass;
      expect(h.requests, isEmpty);
      final row = await h.row(mealId);
      expect((row.status, row.attempts), (MealAnalysisStatus.queued, 0));
    }

    test(
      'consent withdrawn during the encode requeues the row unsent',
      () async {
        final (mealId, pass) = await encoding();
        h.configStore.mealPhotoConsent = null;
        await expectRequeued(mealId, pass);
      },
    );

    test(
      'vision turned no during the encode requeues the row unsent',
      () async {
        final (mealId, pass) = await encoding();
        h.configStore.profiles[aiCapabilityProfileKey(hostKey, photoModel)] =
            const AiCapabilityProfile(vision: AiVisionSupport.no);
        await expectRequeued(mealId, pass);
      },
    );

    test('the background during the encode requeues the row unsent', () async {
      final (mealId, pass) = await encoding();
      h.queue.toBackground();
      await expectRequeued(mealId, pass);
    });

    test('keep on phone during the encode requeues the row unsent', () async {
      final (mealId, pass) = await encoding();
      await h.analyses.setKeepOnPhone(mealId, keep: true);
      await expectRequeued(mealId, pass);
    });

    test('Food off: enqueue is unavailable and a pass sends nothing', () async {
      h.modules = {ModuleId.ai};
      final mealId = await h.meal();
      await h.queued(mealId);
      await h.start();

      expect(await h.queue.enqueue(mealId), EnqueueOutcome.unavailable);
      await h.queue.drain();
      expect(h.requests, isEmpty);
    });

    test('a preset that needs a key and has none sends nothing', () async {
      h.secrets.values.clear();
      final mealId = await h.meal();
      await h.queued(mealId);
      await h.start();

      expect(await h.queue.enqueue(mealId), EnqueueOutcome.unavailable);
      await h.queue.drain();
      expect(h.requests, isEmpty);
    });

    for (final vision in [AiVisionSupport.unknown, AiVisionSupport.no]) {
      test('a pass with vision ${vision.name} sends nothing', () async {
        h.configStore.profiles[aiCapabilityProfileKey(hostKey, photoModel)] =
            AiCapabilityProfile(vision: vision);
        final mealId = await h.meal();
        await h.queued(mealId);
        await h.start();

        await h.queue.drain();

        expect(h.requests, isEmpty);
        expect(await statusOf(mealId), (MealAnalysisStatus.queued, null));
      });
    }

    test('a replaced photo skips the row as photo_missing', () async {
      final mealId = await h.meal();
      await h.queued(mealId);
      await h.photos.save('meal_new.jpg', leakyPhoto());
      await h.meals.attachPhoto(mealId, 'meal_new.jpg');
      await h.start();

      await h.queue.drain();

      expect(h.requests, isEmpty);
      expect(await statusOf(mealId), (
        MealAnalysisStatus.skipped,
        'photo_missing',
      ));
    });

    for (final (name, consent) in [
      (
        'another host',
        const AiMealPhotoConsent(
          consentedAtUtcMs: 1,
          policyEffectiveDate: aiCurrentPolicyEffectiveDate,
          hostKey: 'https://other.example:443',
        ),
      ),
      (
        'an older policy date',
        const AiMealPhotoConsent(
          consentedAtUtcMs: 1,
          policyEffectiveDate: '2026-01-01',
          hostKey: hostKey,
        ),
      ),
    ]) {
      test('consent for $name skips the row as no_consent', () async {
        h.configStore.mealPhotoConsent = consent;
        final mealId = await h.meal();
        await h.queued(mealId);
        await h.start();

        await h.queue.drain();

        expect(h.requests, isEmpty);
        expect(await statusOf(mealId), (
          MealAnalysisStatus.skipped,
          'no_consent',
        ));
      });
    }
  });

  group('one pass at a time', () {
    test('overlapping drains never overlap requests and the re-run picks up '
        'a row queued during the pass', () async {
      var calls = 0;
      final first = Completer<AnalysisEvent>();
      h.respond = () => ++calls == 1 ? first.future : completed();
      final a = await h.meal();
      await h.queued(a);
      await h.start();

      final pass = h.queue.drain();
      while (h.requests.isEmpty) {
        await pumpEventQueue(times: 1);
      }
      final b = await h.meal(photo: 'meal_2.jpg');
      await h.queued(b);
      final second = h.queue.drain();
      first.completeError(
        const AnalysisFailure(kind: AnalysisFailureKind.unreachable),
      );
      await Future.wait([pass, second]);

      expect(h.maxInFlight, 1);
      expect(h.requests, hasLength(3));
      expect((await h.row(b)).status, MealAnalysisStatus.done);
    });

    test('the background during a send lets it finish and sends no other '
        'row', () async {
      final answer = Completer<AnalysisEvent>();
      h.respond = () => answer.future;
      final a = await h.meal();
      final b = await h.meal(photo: 'meal_2.jpg');
      await h.queued(a);
      await h.queued(b, at: h.now.add(const Duration(seconds: 1)));
      await h.start();

      final pass = h.queue.drain();
      while (h.requests.isEmpty) {
        await pumpEventQueue(times: 1);
      }
      h.queue.toBackground();
      answer.complete(completed());
      await pass;

      expect(h.requests, hasLength(1));
      expect((await h.row(a)).status, MealAnalysisStatus.done);
      expect(await statusOf(b), (MealAnalysisStatus.queued, null));
    });

    test('a cancel while the row turns sending aborts it before any '
        'request', () async {
      h.analyses.markGate = Completer<void>();
      final mealId = await h.meal();
      final id = await h.queued(mealId);
      await h.start();

      final pass = h.queue.drain();
      while ((await h.row(mealId)).status != MealAnalysisStatus.sending) {
        await pumpEventQueue(times: 1);
      }
      await h.queue.cancel(id);
      h.analyses.markGate!.complete();
      await pass;

      expect(h.requests, isEmpty);
      expect(await statusOf(mealId), (MealAnalysisStatus.failed, 'cancelled'));
    });
  });
}
