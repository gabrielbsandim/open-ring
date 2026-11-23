import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/infrastructure/shared_preferences_ai_config_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const _consent = AiConsent(
  consentedAtUtcMs: 1,
  policyEffectiveDate: aiCurrentPolicyEffectiveDate,
  hostKey: 'https://api.example.com:443',
  detailLevel: AiDetailLevel.standard,
  contextSchemaVersion: 'v2',
);

void main() {
  late SharedPreferencesAiConfigStore store;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({'some_plugin_key': 'kept'});
    store = SharedPreferencesAiConfigStore();
  });

  test('config, consents and profiles round trip', () async {
    const config = AiConfig(baseUrl: 'https://api.example.com', model: 'm');
    const photo = AiMealPhotoConsent(
      consentedAtUtcMs: 2,
      policyEffectiveDate: aiCurrentPolicyEffectiveDate,
      hostKey: 'h',
    );
    const profile = AiCapabilityProfile(streamOk: false);
    await store.writeConfig(config);
    await store.writeConsent(_consent);
    await store.writeMealPhotoConsent(photo);
    await store.writeCapabilityProfile('h', 'm', profile);

    expect(await store.readConfig(), config);
    expect(await store.readConsent(), _consent);
    expect(await store.readMealPhotoConsent(), photo);
    expect(await store.readCapabilityProfile('h', 'm'), profile);
    expect(await store.readCapabilityProfile('h', 'other'), isNull);
  });

  test(
    'corrupt or wrongly typed values read as defaults, never throw',
    () async {
      final prefs = SharedPreferencesAsync();
      await prefs.setString(SharedPreferencesAiConfigStore.configKey, '{oops');
      await prefs.setString(SharedPreferencesAiConfigStore.consentKey, '[1]');
      await prefs.setString(
        SharedPreferencesAiConfigStore.profilesKey,
        '{"h|m": {"streamOk": "no", "streamUsageOk": 1}, "x|y": 3}',
      );

      expect(await store.readConfig(), AiConfig.defaults);
      expect(await store.readConsent(), isNull);
      expect(
        await store.readCapabilityProfile('h', 'm'),
        AiCapabilityProfile.defaults,
      );
      expect(await store.readCapabilityProfile('x', 'y'), isNull);
    },
  );

  test('profiles keep only the most recent maxProfiles entries', () async {
    const max = SharedPreferencesAiConfigStore.maxProfiles;
    for (var i = 0; i <= max; i++) {
      await store.writeCapabilityProfile(
        'h$i',
        'm',
        AiCapabilityProfile.defaults,
      );
    }
    await store.writeCapabilityProfile('h1', 'm', AiCapabilityProfile.defaults);
    await store.writeCapabilityProfile(
      'new',
      'm',
      AiCapabilityProfile.defaults,
    );

    expect(await store.readCapabilityProfile('h0', 'm'), isNull);
    expect(await store.readCapabilityProfile('h2', 'm'), isNull);
    expect(await store.readCapabilityProfile('h1', 'm'), isNotNull);
    expect(await store.readCapabilityProfile('new', 'm'), isNotNull);
  });

  test('every key it writes is in keys, and clearAll leaves others', () async {
    await store.writeConfig(AiConfig.defaults);
    await store.writeConsent(_consent);
    await store.writeMealPhotoConsent(
      const AiMealPhotoConsent(
        consentedAtUtcMs: 1,
        policyEffectiveDate: 'd',
        hostKey: 'h',
      ),
    );
    await store.writeCapabilityProfile('h', 'm', AiCapabilityProfile.defaults);
    final prefs = SharedPreferencesAsync();
    final written = (await prefs.getKeys()).difference({'some_plugin_key'});

    expect(written, SharedPreferencesAiConfigStore.keys);
    expect(written.every((k) => k.startsWith('ai_')), isTrue);
    await store.clearAll();
    expect(await prefs.getKeys(), {'some_plugin_key'});
  });

  test('clearConsent and clearCapabilityProfiles remove only theirs', () async {
    await store.writeConsent(_consent);
    await store.writeCapabilityProfile('h', 'm', AiCapabilityProfile.defaults);
    await store.clearConsent();
    expect(await store.readConsent(), isNull);
    expect(await store.readCapabilityProfile('h', 'm'), isNotNull);
    await store.clearCapabilityProfiles();
    expect(await store.readCapabilityProfile('h', 'm'), isNull);
  });
}
