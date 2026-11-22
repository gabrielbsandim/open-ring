import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';

final class InMemorySecretStore implements SecretStore {
  final Map<String, String> values = {};
  int deleteCalls = 0;

  @override
  Future<String?> read(String name) async => values[name];

  @override
  Future<void> write(String name, String value) async {
    values[name] = value;
  }

  @override
  Future<void> delete(String name) async {
    deleteCalls++;
    values.remove(name);
  }
}

final class FailingSecretStore implements SecretStore {
  new({
    this.failRead = false,
    this.failWrite = false,
    this.failDelete = false,
    Object? error,
  }) : _error = error ?? StateError('keystore failure');

  final bool failRead;
  final bool failWrite;
  final bool failDelete;
  final Object _error;
  final Map<String, String> values = {};
  int deleteCalls = 0;

  @override
  Future<String?> read(String name) async {
    if (failRead) Error.throwWithStackTrace(_error, StackTrace.current);
    return values[name];
  }

  @override
  Future<void> write(String name, String value) async {
    if (failWrite) Error.throwWithStackTrace(_error, StackTrace.current);
    values[name] = value;
  }

  @override
  Future<void> delete(String name) async {
    deleteCalls++;
    if (failDelete) Error.throwWithStackTrace(_error, StackTrace.current);
    values.remove(name);
  }
}

final class InMemoryAiConfigStore implements AiConfigStore {
  AiConfig config = AiConfig.defaults;
  AiConsent? consent;
  AiMealPhotoConsent? mealPhotoConsent;
  final Map<String, AiCapabilityProfile> profiles = {};

  @override
  Future<AiConfig> readConfig() async => config;

  @override
  Future<void> writeConfig(AiConfig config) async {
    this.config = config;
  }

  @override
  Future<AiConsent?> readConsent() async => consent;

  @override
  Future<void> writeConsent(AiConsent consent) async {
    this.consent = consent;
  }

  @override
  Future<void> clearConsent() async {
    consent = null;
  }

  @override
  Future<AiMealPhotoConsent?> readMealPhotoConsent() async => mealPhotoConsent;

  @override
  Future<void> writeMealPhotoConsent(AiMealPhotoConsent consent) async {
    mealPhotoConsent = consent;
  }

  @override
  Future<void> clearMealPhotoConsent() async {
    mealPhotoConsent = null;
  }

  @override
  Future<AiCapabilityProfile?> readCapabilityProfile(
    String hostKey,
    String model,
  ) async => profiles[aiCapabilityProfileKey(hostKey, model)];

  @override
  Future<void> writeCapabilityProfile(
    String hostKey,
    String model,
    AiCapabilityProfile profile,
  ) async {
    profiles[aiCapabilityProfileKey(hostKey, model)] = profile;
  }

  @override
  Future<void> clearCapabilityProfiles() async {
    profiles.clear();
  }

  @override
  Future<void> clearAll() async {
    config = AiConfig.defaults;
    consent = null;
    mealPhotoConsent = null;
    profiles.clear();
  }
}
