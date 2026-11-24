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
    Future<EnqueueOutcome> ninth({int stored = 8}) async {
      await h.start();
      h.queue.toBackground();
      for (var i = 0; i < stored; i++) {
        await h.queued(await h.meal(photo: 'meal_$i.jpg'));
      }
      return await h.queue.enqueue(await h.meal(photo: 'meal_last.jpg'));
    }

    test(
      'the 9th enqueue of the day returns dailyLimit and writes no row',
      () async {
        expect(await ninth(), EnqueueOutcome.dailyLimit);
        expect(await rowCount(h.db, 'meal_analyses'), 8);
      },
    );

    test('rows queued yesterday do not count', () async {
      await h.start();
      h.queue.toBackground();
      final yesterday = h.now.subtract(const Duration(hours: 13));
      for (var i = 0; i < 8; i++) {
        await h.queued(await h.meal(photo: 'meal_$i.jpg'), at: yesterday);
      }

      expect(
        await h.queue.enqueue(await h.meal(photo: 'meal_new.jpg')),
        EnqueueOutcome.queued,
      );
    });

    test('skipped rows do not count', () async {
      await h.start();
      h.queue.toBackground();
      for (var i = 0; i < 8; i++) {
        final id = await h.queued(await h.meal(photo: 'meal_$i.jpg'));
        await h.queue.cancel(id);
      }

      expect(
        await h.queue.enqueue(await h.meal(photo: 'meal_new.jpg')),
        EnqueueOutcome.queued,
      );
    });

    test('photoDailyLimit 3 caps at 3', () async {
      h.configStore.config = testedConfig.copyWith(photoDailyLimit: 3);

      expect(await ninth(stored: 3), EnqueueOutcome.dailyLimit);
    });

    test('an out of range stored limit falls back to 8', () async {
      h.configStore.config = AiConfig.fromJson({
        ...testedConfig.toJson(),
        'photoDailyLimit': 99,
      });

      expect(await ninth(stored: 7), EnqueueOutcome.queued);
      expect(
        await h.queue.enqueue(await h.meal(photo: 'meal_ninth.jpg')),
        EnqueueOutcome.dailyLimit,
      );
    });

    test('a cached answer comes back without meeting the limit', () async {
      await h.start();
      final mealId = await h.meal();
      final id = await h.queued(mealId);
      await h.queue.drain();
      for (var i = 0; i < 7; i++) {
        await h.queued(await h.meal(photo: 'extra_$i.jpg'));
      }
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
}
