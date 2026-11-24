import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';

final secretStoreProvider = Provider<SecretStore>(
  (ref) => throw UnimplementedError('Override secretStoreProvider.'),
);

final aiConfigStoreProvider = Provider<AiConfigStore>(
  (ref) => throw UnimplementedError('Override aiConfigStoreProvider.'),
);

final aiConfigProvider = AsyncNotifierProvider<AiConfigController, AiConfig>(
  AiConfigController.new,
);

/// Holds the config only: the API key stays in [SecretStore] and is never
/// kept in provider state.
class AiConfigController extends AsyncNotifier<AiConfig> {
  Future<void> _queue = Future.value();

  @override
  Future<AiConfig> build() => ref.watch(aiConfigStoreProvider).readConfig();

  /// A different scheme, host or port deletes the key and both consents
  /// before the new address is stored, so a key never follows an edit.
  Future<void> save(AiConfig next) => _serial(() => _write(next));

  /// Applies [change] to the config as stored when the write runs, so queued
  /// edits and a finished test are never overwritten by a stale copy.
  Future<void> edit(AiConfig Function(AiConfig current) change) =>
      _serial(() async => await _write(change(await future)));

  Future<void> _write(AiConfig next) async {
    final current = await future;
    final oldHost = current.hostKey;
    final moved = oldHost != null && oldHost != next.hostKey;
    final store = ref.read(aiConfigStoreProvider);
    final value = moved
        ? next.copyWith(clearKeyLastFour: true, clearTested: true)
        : next;
    if (moved) {
      await ref.read(secretStoreProvider).delete(aiApiKeySecretName);
      await store.clearConsent();
      await store.clearMealPhotoConsent();
      ref.invalidate(aiConsentProvider);
    }
    await store.writeConfig(value);
    state = AsyncData(value);
  }

  Future<void> setApiKey(String apiKey) => _serial(() async {
    final current = await future;
    final trimmed = apiKey.trim();
    final secrets = ref.read(secretStoreProvider);
    if (trimmed.isEmpty) {
      await secrets.delete(aiApiKeySecretName);
    } else {
      await secrets.write(aiApiKeySecretName, trimmed);
    }
    final value = current.copyWith(
      keyLastFour: AiConfig.lastFourOf(trimmed),
      clearKeyLastFour: trimmed.isEmpty,
      clearTested: true,
    );
    await ref.read(aiConfigStoreProvider).writeConfig(value);
    state = AsyncData(value);
  });

  /// Drops a result whose target changed while the test ran, so a stale
  /// pass never marks a new address or model as tested.
  Future<void> recordTest({
    required String hostKey,
    required String model,
    required AiCapabilityProfile profile,
    required DateTime at,
  }) => _serial(() async {
    final current = await future;
    if (current.hostKey != hostKey || current.trimmedModel != model) return;
    final store = ref.read(aiConfigStoreProvider);
    await store.writeCapabilityProfile(hostKey, model, profile);
    final value = current.copyWith(
      testedAtUtcMs: at.toUtc().millisecondsSinceEpoch,
      testedHostKey: hostKey,
      testedModel: model,
    );
    await store.writeConfig(value);
    state = AsyncData(value);
  });

  Future<void> recordConsent(AiConsent consent) => _serial(() async {
    await ref.read(aiConfigStoreProvider).writeConsent(consent);
    ref.invalidate(aiConsentProvider);
  });

  Future<void> withdrawConsent() => _serial(() async {
    await ref.read(aiConfigStoreProvider).clearConsent();
    ref.invalidate(aiConsentProvider);
  });

  Future<void> _serial(Future<void> Function() action) {
    final run = _queue.then((_) => action());
    _queue = run.catchError((Object _) {});
    return run;
  }
}

final aiConsentProvider = FutureProvider<AiConsent?>(
  (ref) => ref.watch(aiConfigStoreProvider).readConsent(),
);

/// A writer of the photo consent invalidates it, so the photo queue runs.
final aiMealPhotoConsentProvider = FutureProvider<AiMealPhotoConsent?>(
  (ref) => ref.watch(aiConfigStoreProvider).readMealPhotoConsent(),
);

final aiAvailabilityProvider = FutureProvider<AiAvailability>((ref) async {
  // Awaits the module list: a still loading list must not resolve to off.
  final modules = await ref.watch(enabledModulesProvider.future);
  if (!modules.contains(ModuleId.ai)) return AiAvailability.off;
  final config = await ref.watch(aiConfigProvider.future);
  final key = await ref.read(secretStoreProvider).read(aiApiKeySecretName);
  final consent = await ref.watch(aiConsentProvider.future);
  return resolveAiAvailability(
    moduleEnabled: true,
    config: config,
    hasStoredKey: key != null && key.isNotEmpty,
    consent: consent,
  );
});

/// The stored profile behind the tested caption, null while untested.
final aiTestedProfileProvider = FutureProvider<AiCapabilityProfile?>((
  ref,
) async {
  final config = await ref.watch(aiConfigProvider.future);
  final hostKey = config.hostKey;
  if (!config.isTestedForCurrentTarget || hostKey == null) return null;
  return await ref
      .read(aiConfigStoreProvider)
      .readCapabilityProfile(hostKey, config.trimmedModel);
});
