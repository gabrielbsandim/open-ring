import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/ai_report_providers.dart';
import 'package:open_ring/features/ai/application/health_context_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/health_context_assembly.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/presentation/ai_context_preview_screen.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/ble_fakes.dart';
import '../../../helpers/onboarding_app.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart';

const _live = BuiltAiPayload(
  contextMap: {'schema': 'health_context_v2'},
  canonicalContextJson: '{}',
  systemPrompt: 'live system',
  userMessage: 'live user message',
  facts: [],
  estimatedTokens: 5,
  contextTokens: 2,
  cacheKey: 'live',
  droppedCount: 0,
);

void main() {
  testWidgets('the app preview route shows the report passed as extra', (
    tester,
  ) async {
    final configs = InMemoryAiConfigStore()
      ..config = const AiConfig(baseUrl: 'https://api.example.com/v1');
    final container = await pumpOnboardingApp(
      tester,
      store: InMemoryOnboardingStore(completed: true),
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(),
        ...onboardingOverrides(),
        aiConfigStoreProvider.overrideWithValue(configs),
        aiEnabledProvider.overrideWith((ref) => true),
        aiReportStoreProvider.overrideWithValue(InMemoryAiReportStore()),
        aiPayloadProvider.overrideWith(
          (ref, kind) async => AiPayloadReady(_live, kind: kind),
        ),
      ],
    );
    final report = AiReport(
      createdAtUtc: DateTime.utc(2026, 11, 23),
      offsetMin: 0,
      kind: 'weekly_review',
      contextSchema: 'health_context_v2',
      contextSha256: 'sha',
      detailLevel: 'standard',
      promptVersion: 'v1',
      providerHost: 'https://api.example.com:443',
      model: 'm',
      status: AiReportStatus.done,
      payloadJson: '{"system":"stored system","user":"stored user"}',
    );
    container.read(appRouterProvider).go(AppTab.heart.path);
    await tester.pumpAndSettle();
    unawaited(
      container
          .read(appRouterProvider)
          .push(AppPaths.aiReadingsPreview, extra: report),
    );
    await tester.pumpAndSettle();

    final screen = tester.widget<AiContextPreviewScreen>(
      find.byType(AiContextPreviewScreen),
    );
    expect(screen.report, same(report));
    expect(find.text('stored user'), findsOneWidget);
    expect(find.text('live user message'), findsNothing);
  });
}
