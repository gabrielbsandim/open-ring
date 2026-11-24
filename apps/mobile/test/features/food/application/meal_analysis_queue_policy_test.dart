import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/openai_wire_codec.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/food/application/meal_analysis_failure_policy.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';

import 'meal_analysis_harness.dart';

AnalysisFailure http(int status, {String message = '', String? retryAfter}) =>
    OpenAiWireCodec.classifyHttpError(
      statusCode: status,
      body: jsonEncode({
        'error': {'message': message},
      }),
      headers: {'retry-after': ?retryAfter},
    );

void main() {
  late MealQueueHarness h;

  setUp(() => h = MealQueueHarness());

  /// Each request takes the next reply; the last one repeats.
  void replies(List<Object> answers) {
    var i = 0;
    h.respond = () {
      final answer = answers[i < answers.length ? i++ : answers.length - 1];
      if (answer is AnalysisFailure) throw answer;
      return answer as AnalysisEvent;
    };
  }

  Future<List<int>> threeQueued() async {
    final meals = <int>[];
    for (var i = 0; i < 3; i++) {
      final id = await h.meal(photo: 'meal_$i.jpg');
      await h.queued(id, at: h.now.add(Duration(seconds: i)));
      meals.add(id);
    }
    return meals;
  }

  Future<void> expectAllQueued(List<int> meals) async {
    for (final id in meals) {
      final row = await h.row(id);
      expect((row.status, row.attempts), (MealAnalysisStatus.queued, 0));
    }
  }

  AiPhotoQueuePause? pause() =>
      h.container.read(mealAnalysisQueueProvider).pause;

  /// Runs [body] in fake time, with the clock following it.
  void timed(void Function(FakeAsync async, void Function(Future<void>)) body) {
    fakeAsync((async) {
      h.elapsed = () => async.elapsed;
      h.clock = () => h.now.add(async.elapsed);
      void settle(Future<void> f) {
        var done = false;
        unawaited(f.then((_) => done = true));
        for (var i = 0; i < 4000 && !done; i++) {
          async.elapse(const Duration(seconds: 1));
        }
        expect(done, isTrue);
      }

      body(async, settle);
    });
  }

  group('acceptance 1: 401 pauses the queue', () {
    test('401 on the first of 3 rows sends 1 request and keeps all 3 '
        'queued', () async {
      replies([http(401)]);
      final meals = await threeQueued();
      await h.start();

      await h.queue.drain();

      expect(h.requests, hasLength(1));
      await expectAllQueued(meals);
      expect(pause()?.reason, AiPhotoQueuePauseReason.unauthorized);
      expect(h.configStore.photoQueuePause, pause());
      expect(
        (pause()?.hostKey, pause()?.model, pause()?.atUtcMs),
        (hostKey, photoModel, h.now.toUtc().millisecondsSinceEpoch),
      );
    });

    test('the pause survives a new container', () async {
      replies([http(401)]);
      final meals = await threeQueued();
      await h.start();
      await h.queue.drain();
      replies([completed()]);

      final restarted = ProviderContainer(
        overrides: [
          moduleStoreProvider.overrideWithValue(h.moduleStore),
          ...h.overrides,
        ],
      );
      addTearDown(restarted.dispose);
      await restarted.read(enabledModulesProvider.future);
      await restarted.read(mealAnalysisQueueProvider.notifier).drain();

      expect(h.requests, hasLength(1));
      await expectAllQueued(meals);
      expect(
        restarted.read(mealAnalysisQueueProvider).pause?.reason,
        AiPhotoQueuePauseReason.unauthorized,
      );
    });

    test('resume sends the 3 rows 1 s apart', () {
      timed((async, settle) {
        late List<int> meals;
        replies([http(401), completed()]);
        settle(() async {
          meals = await threeQueued();
          await h.start();
          await h.queue.drain();
        }());
        final start = async.elapsed;

        settle(h.queue.resume());

        expect(h.sentAt.skip(1).map((t) => t - start), [
          Duration.zero,
          aiPhotoSendSpacing,
          aiPhotoSendSpacing * 2,
        ]);
        expect(h.configStore.photoQueuePause, isNull);
        expect(pause(), isNull);
        settle(() async {
          for (final id in meals) {
            expect((await h.row(id)).status, MealAnalysisStatus.done);
          }
        }());
      });
    });

    test('a new key lifts the pause without resume', () async {
      replies([http(401)]);
      final meals = await threeQueued();
      await h.start();
      await h.queue.drain();
      replies([completed()]);

      h.secrets.values[aiApiKeySecretName] = 'sk-new-5678';
      h.configStore.config = testedConfig.copyWith(keyLastFour: '5678');
      h.container.invalidate(aiConfigProvider);
      await h.queue.drain();

      expect(h.requests, hasLength(4));
      expect(pause(), isNull);
      expect((await h.row(meals.last)).status, MealAnalysisStatus.done);
    });
  });

  group('acceptance 2: other pauses', () {
    for (final (status, reason) in [
      (402, AiPhotoQueuePauseReason.noCredit),
      (403, AiPhotoQueuePauseReason.forbidden),
    ]) {
      test('$status pauses as ${reason.name} after 1 request', () async {
        replies([http(status)]);
        final meals = await threeQueued();
        await h.start();

        await h.queue.drain();

        expect(h.requests, hasLength(1));
        await expectAllQueued(meals);
        expect(h.configStore.photoQueuePause?.reason, reason);
      });
    }

    test('a 400 naming image_url sends 1 request, stores vision no and '
        'pauses noVision', () async {
      replies([http(400, message: 'Unsupported content type image_url')]);
      final meals = await threeQueued();
      await h.start();

      await h.queue.drain();

      expect(h.requests, hasLength(1));
      await expectAllQueued(meals);
      final profile =
          h.configStore.profiles[aiCapabilityProfileKey(hostKey, photoModel)];
      expect(profile?.vision, AiVisionSupport.no);
      expect(pause()?.reason, AiPhotoQueuePauseReason.noVision);
    });

    test('a pause for another model does not hold', () async {
      h.configStore.photoQueuePause = const AiPhotoQueuePause(
        reason: AiPhotoQueuePauseReason.unauthorized,
        hostKey: hostKey,
        model: 'old-m',
        keyLastFour: null,
        atUtcMs: 1,
      );
      final mealId = await h.meal();
      await h.queued(mealId);
      await h.start();

      await h.queue.drain();

      expect(h.requests, hasLength(1));
      expect(pause(), isNull);
    });
  });

  group('acceptance 3: automatic resend', () {
    test('a malformed answer then a valid one makes 2 requests and gives '
        'done', () async {
      replies([completed('not json'), completed()]);
      final mealId = await h.meal();
      await h.queued(mealId);
      await h.start();

      await h.queue.drain();

      expect(h.requests, hasLength(2));
      final row = await h.row(mealId);
      expect((row.status, row.attempts), (MealAnalysisStatus.done, 2));
      expect(h.markers.monthSum, 640);
    });

    test('two malformed answers give rejected with attempts 2 and no third '
        'request', () async {
      replies([completed('not json')]);
      final mealId = await h.meal();
      await h.queued(mealId);
      await h.start();

      await h.queue.drain();

      expect(h.requests, hasLength(2));
      final row = await h.row(mealId);
      expect((row.status, row.attempts), (MealAnalysisStatus.rejected, 2));
    });

    test('a 429 with retry-after 18 is resent once after 18 s', () {
      timed((async, settle) {
        late int mealId;
        replies([http(429, retryAfter: '18'), completed()]);
        settle(() async {
          mealId = await h.meal();
          await h.queued(mealId);
          await h.start();
        }());
        final start = async.elapsed;

        settle(h.queue.drain());

        expect(h.requests, hasLength(2));
        expect(async.elapsed - start, greaterThanOrEqualTo(seconds(18)));
        settle(() async {
          final row = await h.row(mealId);
          expect((row.status, row.attempts), (MealAnalysisStatus.done, 2));
        }());
      });
    });

    test('two 429s within 20 s stop at 2 requests as rateLimited', () {
      timed((async, settle) {
        late int mealId;
        replies([http(429, retryAfter: '5')]);
        settle(() async {
          mealId = await h.meal();
          await h.queued(mealId);
          await h.start();
          await h.queue.drain();
        }());

        expect(h.requests, hasLength(2));
        settle(() async {
          final row = await h.row(mealId);
          expect(
            (row.status, row.errorKind),
            (MealAnalysisStatus.failed, 'rateLimited'),
          );
        }());
      });
    });

    test('a 429 with retry-after 45 fails as rateLimited at once', () async {
      replies([http(429, retryAfter: '45')]);
      final mealId = await h.meal();
      await h.queued(mealId);
      await h.start();

      await h.queue.drain();

      expect(h.requests, hasLength(1));
      final row = await h.row(mealId);
      expect(
        (row.status, row.errorKind, row.attempts),
        (MealAnalysisStatus.failed, 'rateLimited', 1),
      );
    });

    test('a malformed answer during the background is not resent', () async {
      final answer = Completer<AnalysisEvent>();
      h.respond = () => answer.future;
      final mealId = await h.meal();
      await h.queued(mealId);
      await h.start();

      final pass = h.queue.drain();
      while (h.requests.isEmpty) {
        await pumpEventQueue(times: 1);
      }
      h.queue.toBackground();
      answer.complete(completed('not json'));
      await pass;

      expect(h.requests, hasLength(1));
      expect((await h.row(mealId)).status, MealAnalysisStatus.rejected);
    });
  });

  group('acceptance 4: backoff', () {
    Future<List<int>> queuedRows(int count) async {
      final meals = <int>[];
      for (var i = 0; i < count; i++) {
        final id = await h.meal(photo: 'meal_$i.jpg');
        await h.queued(id, at: h.now.add(Duration(seconds: i)));
        meals.add(id);
      }
      return meals;
    }

    List<Duration> gaps() => [
      for (var i = 1; i < h.sentAt.length; i++) h.sentAt[i] - h.sentAt[i - 1],
    ];

    test('5xx in a row are spaced 1, 5, then 30 minutes', () {
      timed((async, settle) {
        replies([http(500), http(502), http(503), http(500)]);
        settle(() async {
          await queuedRows(4);
          await h.start();
        }());

        settle(h.queue.drain());

        expect(gaps(), [minutes(1), minutes(5), minutes(30)]);
      });
    });

    test('a timeout backs off too, and a success resets the spacing', () {
      timed((async, settle) {
        replies([
          const AnalysisFailure(kind: AnalysisFailureKind.timeout),
          completed(),
          http(500),
          completed(),
        ]);
        settle(() async {
          await queuedRows(4);
          await h.start();
        }());

        settle(h.queue.drain());

        expect(gaps(), [minutes(1), aiPhotoSendSpacing, minutes(1)]);
      });
    });

    test('the backoff steps', () {
      expect(
        [for (var i = 1; i <= 4; i++) aiPhotoBackoffAfter(i)],
        [minutes(1), minutes(5), minutes(30), minutes(30)],
      );
    });
  });

  group('acceptance 5: recovery and retry', () {
    test(
      'a row left sending fails as interrupted and is never resent',
      () async {
        final mealId = await h.meal();
        final id = await h.queued(mealId);
        await h.analyses.markSending(id, now: h.now);
        await h.start();

        await h.queue.drain();

        expect(h.requests, isEmpty);
        final row = await h.row(mealId);
        expect(
          (row.status, row.errorKind),
          (MealAnalysisStatus.failed, 'interrupted'),
        );
      },
    );

    test('retry sends a failed row again, after the backoff, without a new '
        'daily use', () {
      timed((async, settle) {
        late int mealId;
        replies([http(500), completed()]);
        settle(() async {
          await h.start();
          mealId = await h.meal();
          expect(await h.queue.enqueue(mealId), EnqueueOutcome.queued);
          await h.queue.idle;
          expect((await h.row(mealId)).status, MealAnalysisStatus.failed);
        }());

        settle(() async {
          expect(await h.queue.retry((await h.row(mealId)).id), isTrue);
          await h.queue.idle;
        }());

        expect(h.requests, hasLength(2));
        expect(h.sentAt.last - h.sentAt.first, minutes(1));
        settle(() async {
          final row = await h.row(mealId);
          expect((row.status, row.errorKind), (MealAnalysisStatus.done, null));
          expect(await h.markers.photoUses(aiPhotoDayKey(h.now)), 1);
        }());
      });
    });

    test('retry of a rejected row is allowed, of a done row is not', () async {
      replies([completed('not json'), completed('not json'), completed()]);
      final mealId = await h.meal();
      final id = await h.queued(mealId);
      await h.start();
      await h.queue.drain();
      expect((await h.row(mealId)).status, MealAnalysisStatus.rejected);

      expect(await h.queue.retry(id), isTrue);
      await h.queue.idle;

      expect((await h.row(mealId)).status, MealAnalysisStatus.done);
      expect(await h.queue.retry(id), isFalse);
    });
  });
}

Duration seconds(int s) => Duration(seconds: s);

Duration minutes(int m) => Duration(minutes: m);
