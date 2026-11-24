import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_provider_preset.dart';
import 'package:open_ring/features/ai/presentation/ai_connection_screen.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/layout_harness.dart';

void main() {
  group('AiConnectionScreen layout matrix', () {
    for (final c in layoutMatrix()) {
      testWidgets('AiConnectionScreen fits without overflow at $c', (
        tester,
      ) async {
        final store = InMemoryAiConfigStore()
          ..config = const AiConfig(
            preset: AiProviderPreset.ollama,
            baseUrl: 'http://192.168.1.10:11434/v1',
            model: 'gemma3:12b',
            keyLastFour: 'ab3X',
          );
        await pumpScaled(
          tester,
          screenHost(const AiConnectionScreen()),
          textScaler: c.textScaler,
          brightness: c.brightness,
          locale: c.locale,
          overrides: [
            aiConfigStoreProvider.overrideWithValue(store),
            secretStoreProvider.overrideWithValue(InMemorySecretStore()),
          ],
        );

        await expectNoLayoutOverflow(() async {
          final scrollable = find.byType(Scrollable).first;
          for (final key in const [
            AiConnectionKeys.notEncrypted,
            AiConnectionKeys.keySaved,
            AiConnectionKeys.save,
          ]) {
            await tester.scrollUntilVisible(
              find.byKey(key),
              200,
              scrollable: scrollable,
            );
            await tester.pumpAndSettle();
          }
          await tester.scrollUntilVisible(
            find.byKey(AiConnectionKeys.address),
            -200,
            scrollable: scrollable,
          );
          await tester.enterText(
            find.byKey(AiConnectionKeys.address),
            'http://api.example.com/v1',
          );
          await tester.pumpAndSettle();
        });
      });
    }
  });
}
