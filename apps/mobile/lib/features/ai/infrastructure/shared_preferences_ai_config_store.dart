import 'dart:convert';

import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesAiConfigStore implements AiConfigStore {
  new([SharedPreferencesAsync? preferences]) : _preferences = preferences;

  static const configKey = 'ai_config';
  static const consentKey = 'ai_consent';
  static const mealPhotoConsentKey = 'ai_meal_photo_consent';
  static const profilesKey = 'ai_capability_profiles';
  static const photoQueuePauseKey = 'ai_photo_queue_pause';
  static const Set<String> keys = {
    configKey,
    consentKey,
    mealPhotoConsentKey,
    profilesKey,
    photoQueuePauseKey,
  };
  static const int maxProfiles = 8;

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<AiConfig> readConfig() async {
    final map = await _readMap(configKey);
    return map == null ? AiConfig.defaults : AiConfig.fromJson(map);
  }

  @override
  Future<void> writeConfig(AiConfig config) =>
      _store.setString(configKey, jsonEncode(config.toJson()));

  @override
  Future<AiConsent?> readConsent() async {
    final map = await _readMap(consentKey);
    return map == null ? null : AiConsent.tryFromJson(map);
  }

  @override
  Future<void> writeConsent(AiConsent consent) =>
      _store.setString(consentKey, jsonEncode(consent.toJson()));

  @override
  Future<void> clearConsent() => _store.remove(consentKey);

  @override
  Future<AiMealPhotoConsent?> readMealPhotoConsent() async {
    final map = await _readMap(mealPhotoConsentKey);
    return map == null ? null : AiMealPhotoConsent.tryFromJson(map);
  }

  @override
  Future<void> writeMealPhotoConsent(AiMealPhotoConsent consent) =>
      _store.setString(mealPhotoConsentKey, jsonEncode(consent.toJson()));

  @override
  Future<void> clearMealPhotoConsent() => _store.remove(mealPhotoConsentKey);

  @override
  Future<AiPhotoQueuePause?> readPhotoQueuePause() async {
    final map = await _readMap(photoQueuePauseKey);
    return map == null ? null : AiPhotoQueuePause.tryFromJson(map);
  }

  @override
  Future<void> writePhotoQueuePause(AiPhotoQueuePause pause) =>
      _store.setString(photoQueuePauseKey, jsonEncode(pause.toJson()));

  @override
  Future<void> clearPhotoQueuePause() => _store.remove(photoQueuePauseKey);

  @override
  Future<AiCapabilityProfile?> readCapabilityProfile(
    String hostKey,
    String model,
  ) async {
    final profiles = await _readMap(profilesKey);
    final entry = profiles?[aiCapabilityProfileKey(hostKey, model)];
    if (entry is! Map<String, Object?>) return null;
    return AiCapabilityProfile.fromJson(entry);
  }

  // Insertion order is recency: a rewrite moves the entry to the end and the
  // oldest entries fall off past maxProfiles.
  @override
  Future<void> writeCapabilityProfile(
    String hostKey,
    String model,
    AiCapabilityProfile profile,
  ) async {
    final current = await _readMap(profilesKey) ?? const {};
    final id = aiCapabilityProfileKey(hostKey, model);
    final next = <String, Object?>{
      for (final e in current.entries)
        if (e.key != id && e.value is Map<String, Object?>) e.key: e.value,
      id: profile.toJson(),
    };
    final drop = next.length > maxProfiles ? next.length - maxProfiles : 0;
    await _store.setString(
      profilesKey,
      jsonEncode(Map.fromEntries(next.entries.skip(drop))),
    );
  }

  @override
  Future<void> clearCapabilityProfiles() => _store.remove(profilesKey);

  @override
  Future<void> clearAll() => _store.clear(allowList: keys);

  Future<Map<String, Object?>?> _readMap(String key) async {
    final raw = await _store.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
