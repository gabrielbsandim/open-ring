import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/application/vision_probe_controller.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/vision_probe.dart';
import 'package:open_ring/features/food/presentation/meal_photo_consent_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../../ai/wire_jpeg_fixture.dart';
import '../application/meal_analysis_harness.dart';

const _seed = 11;

AnalysisEvent _says(String text) => AnalysisCompleted(
  text: text,
  finishReason: 'stop',
  usage: const AiTokenUsage(promptTokens: 30, completionTokens: 5),
);

// The probe keeps one Random across runs, so a second run draws grid 2.
String _colours({bool right = true, int draw = 1}) {
  final random = Random(_seed);
  var grid = VisionProbeGrid.random(random);
  for (var i = 1; i < draw; i++) {
    grid = VisionProbeGrid.random(random);
  }
  return jsonEncode({
    for (final (i, c) in grid.cells.indexed)
      visionProbeCellNames[i]: right ? c.name : 'black',
  });
}

class _Open extends StatelessWidget {
  const new(this.open);

  final Future<void> Function(BuildContext context) open;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        key: const Key('open'),
        onPressed: () => unawaited(open(context)),
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late MealQueueHarness h;
  late int mealId;
  bool? granted;

  setUp(() {
    h = MealQueueHarness()
      ..extraOverrides = [
        visionProbeRandomProvider.overrideWith((_) => Random(_seed)),
      ];
    h.configStore
      ..mealPhotoConsent = null
      ..profiles.clear();
    h.respond = () => _says(_colours());
    granted = null;
  });

  Future<void> open(
    WidgetTester tester, {
    AiConfig config = testedConfig,
    bool consent = true,
    bool probe = true,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 2400);
    addTearDown(tester.view.reset);
    await h.start();
    mealId = await h.meal(save: false);
    await h.photos.save('meal_1.jpg', leakyPhoto(width: 768, height: 576));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: screenHost(
          _Open(
            (context) async => granted = await showMealPhotoConsentSheet(
              context,
              config: config,
              mealId: mealId,
              consent: consent,
              probe: probe,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  Future<void> agree(WidgetTester tester) async {
    await tester.tap(find.byKey(MealPhotoConsentKeys.tick));
    await tester.pump();
    await tester.tap(find.byKey(MealPhotoConsentKeys.proceed));
    await tester.pumpAndSettle();
  }

  testWidgets('the consent step starts unticked and shows the wire size', (
    tester,
  ) async {
    await open(tester);

    expect(find.text(l10n.foodAiConsentFirst), findsOneWidget);
    expect(find.text(l10n.aiConsentWhere('api.example.com')), findsOneWidget);
    final tick = tester.widget<CheckboxListTile>(
      find.byKey(MealPhotoConsentKeys.tick),
    );
    expect(tick.value, isFalse);
    final proceed = find.byKey(MealPhotoConsentKeys.proceed);
    expect(tester.widget<FilledButton>(proceed).onPressed, isNull);
    final how = find.descendant(
      of: find.byKey(MealPhotoConsentKeys.how),
      matching: find.textContaining('How it goes: 768 × 576 px, '),
    );
    expect(how, findsOneWidget);
    expect(find.byKey(MealPhotoConsentKeys.unencrypted), findsNothing);
  });

  testWidgets('the consent lines show before the wire encode lands', (
    tester,
  ) async {
    h.encodeGate = Completer<void>();
    await open(tester);

    expect(find.text(l10n.foodAiConsentWhat), findsOneWidget);
    expect(find.byKey(MealPhotoConsentKeys.how), findsNothing);
    h.encodeGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(MealPhotoConsentKeys.how), findsOneWidget);
  });

  testWidgets('a cleartext LAN host shows the unencrypted line', (
    tester,
  ) async {
    const lan = AiConfig(
      baseUrl: 'http://192.168.1.20:11434/v1',
      model: 'llava',
    );
    await open(tester, config: lan);

    expect(find.byKey(MealPhotoConsentKeys.unencrypted), findsOneWidget);
    expect(find.text(l10n.foodAiConsentUnencrypted), findsOneWidget);
  });

  testWidgets('without a probe, Continue stores the consent and grants', (
    tester,
  ) async {
    await open(tester, probe: false);
    await agree(tester);

    expect(granted, isTrue);
    expect((await h.configStore.readMealPhotoConsent())?.hostKey, hostKey);
    expect(h.requests, isEmpty);
  });

  testWidgets('a text only model shows its line and the photo settings link', (
    tester,
  ) async {
    h.respond = () => _says(_colours(right: false));
    await open(tester);
    await agree(tester);

    expect(find.text(l10n.foodAiProbeTextOnly(photoModel)), findsOneWidget);
    expect(find.byKey(MealPhotoConsentKeys.photos), findsOneWidget);
    expect(granted, isNull);
  });

  testWidgets('an unreadable answer offers Test again, and a pass grants', (
    tester,
  ) async {
    h.respond = () => _says('I see no image.');
    await open(tester, consent: false);

    expect(find.byKey(MealPhotoConsentKeys.tick), findsNothing);
    expect(find.text(l10n.aiPhotosVisionUnreadable), findsOneWidget);
    h.respond = () => _says(_colours(draw: 2));
    await tester.tap(find.byKey(MealPhotoConsentKeys.again));
    await tester.pumpAndSettle();

    expect(granted, isTrue);
    expect(h.requests, hasLength(2));
  });

  testWidgets('a failed probe shows the failure line', (tester) async {
    h.respond = () =>
        throw const AnalysisFailure(kind: AnalysisFailureKind.unauthorized);
    await open(tester, consent: false);

    final line = tester.widget<Text>(
      find.descendant(
        of: find.byKey(MealPhotoConsentKeys.probeLine),
        matching: find.byType(Text),
      ),
    );
    expect(line.data, isNot(l10n.aiPhotosVisionUnreadable));
    expect(find.byKey(MealPhotoConsentKeys.again), findsOneWidget);
  });
}
