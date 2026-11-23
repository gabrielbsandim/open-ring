import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';

import '../../../helpers/ai_fakes.dart';

const _url = 'https://api.example.com/v1';

AiConsent _consentFor(String hostKey) => AiConsent(
  consentedAtUtcMs: 1,
  policyEffectiveDate: aiCurrentPolicyEffectiveDate,
  hostKey: hostKey,
  detailLevel: AiDetailLevel.standard,
  contextSchemaVersion: aiContextSchemaVersion,
);

void main() {
  late InMemoryAiConfigStore store;
  late SecretStore secrets;
  late InMemoryModuleStore modules;

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        aiConfigStoreProvider.overrideWithValue(store),
        secretStoreProvider.overrideWithValue(secrets),
        moduleStoreProvider.overrideWithValue(modules),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() async {
    store = InMemoryAiConfigStore()
      ..config = const AiConfig(baseUrl: _url, model: 'm', keyLastFour: 'abcd');
    secrets = InMemorySecretStore();
    await secrets.write(aiApiKeySecretName, 'sk-secret-abcd');
    modules = InMemoryModuleStore();
    await modules.write({ModuleId.ai});
  });

  Future<void> grant(String hostKey) async {
    store
      ..consent = _consentFor(hostKey)
      ..mealPhotoConsent = AiMealPhotoConsent(
        consentedAtUtcMs: 1,
        policyEffectiveDate: aiCurrentPolicyEffectiveDate,
        hostKey: hostKey,
      );
  }

  group('save', () {
    test('a new host deletes the key and both consents first', () async {
      final host = store.config.hostKey!;
      await grant(host);
      final c = container();
      await c.read(aiConfigProvider.future);

      await c
          .read(aiConfigProvider.notifier)
          .save(store.config.copyWith(baseUrl: 'https://other.example.com'));

      expect(await secrets.read(aiApiKeySecretName), isNull);
      expect(store.consent, isNull);
      expect(store.mealPhotoConsent, isNull);
      expect(store.config.baseUrl, 'https://other.example.com');
      expect(store.config.keyLastFour, isNull);
      expect(c.read(aiConfigProvider).value, store.config);
    });

    test('a port change counts as a new host', () async {
      final c = container();
      await c.read(aiConfigProvider.future);
      await c
          .read(aiConfigProvider.notifier)
          .save(
            store.config.copyWith(baseUrl: 'https://api.example.com:8443/v1'),
          );
      expect(await secrets.read(aiApiKeySecretName), isNull);
    });

    test(
      'a path or model edit on the same host keeps key and consent',
      () async {
        await grant(store.config.hostKey!);
        final c = container();
        await c.read(aiConfigProvider.future);
        await c
            .read(aiConfigProvider.notifier)
            .save(
              store.config.copyWith(
                baseUrl: 'https://api.example.com/v2',
                model: 'n',
              ),
            );
        expect(await secrets.read(aiApiKeySecretName), 'sk-secret-abcd');
        expect(store.consent, isNotNull);
        expect(store.config.keyLastFour, 'abcd');
      },
    );

    test('a first address with no earlier host keeps a typed key', () async {
      store.config = const AiConfig(keyLastFour: 'abcd');
      final c = container();
      await c.read(aiConfigProvider.future);
      await c
          .read(aiConfigProvider.notifier)
          .save(store.config.copyWith(baseUrl: _url));
      expect(await secrets.read(aiApiKeySecretName), 'sk-secret-abcd');
    });

    test('a failed key delete never stores the new host', () async {
      secrets = FailingSecretStore(
        failDelete: true,
        error: PlatformException(code: 'keystore'),
      );
      final c = container();
      await c.read(aiConfigProvider.future);
      final notifier = c.read(aiConfigProvider.notifier);

      await expectLater(
        notifier.save(store.config.copyWith(baseUrl: 'https://evil.example')),
        throwsA(isA<PlatformException>()),
      );
      expect(store.config.baseUrl, _url);
      await notifier.save(store.config.copyWith(model: 'next'));
      expect(store.config.model, 'next');
    });
  });

  group('setApiKey', () {
    test(
      'stores the key outside the config, keeps only the last four',
      () async {
        final c = container();
        await c.read(aiConfigProvider.future);
        await c.read(aiConfigProvider.notifier).setApiKey('  sk-new-key-wxyz ');

        expect(await secrets.read(aiApiKeySecretName), 'sk-new-key-wxyz');
        expect(store.config.keyLastFour, 'wxyz');
        expect(store.config.toJson().toString(), isNot(contains('sk-new')));
        expect(
          c.read(aiConfigProvider).value.toString(),
          isNot(contains('sk-')),
        );
      },
    );

    test('an empty key deletes the stored one', () async {
      final c = container();
      await c.read(aiConfigProvider.future);
      await c.read(aiConfigProvider.notifier).setApiKey(' ');
      expect(await secrets.read(aiApiKeySecretName), isNull);
      expect(store.config.keyLastFour, isNull);
    });
  });

  group('aiAvailabilityProvider', () {
    test('is off while the module is off', () async {
      await modules.write({});
      expect(
        await container().read(aiAvailabilityProvider.future),
        AiAvailability.off,
      );
    });

    test('needs consent after a test, then is ready once recorded', () async {
      store.config = store.config.copyWith(
        testedAtUtcMs: 1,
        testedHostKey: store.config.hostKey,
        testedModel: 'm',
      );
      final c = container();
      expect(
        await c.read(aiAvailabilityProvider.future),
        AiAvailability.consentNeeded,
      );
      await c
          .read(aiConfigProvider.notifier)
          .recordConsent(_consentFor(store.config.hostKey!));
      expect(await c.read(aiAvailabilityProvider.future), AiAvailability.ready);
    });

    test('a missing key reads as not configured', () async {
      await secrets.delete(aiApiKeySecretName);
      expect(
        await container().read(aiAvailabilityProvider.future),
        AiAvailability.notConfigured,
      );
    });
  });
}
