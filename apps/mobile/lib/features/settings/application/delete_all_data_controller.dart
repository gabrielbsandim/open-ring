import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/theme_mode_controller.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/domain/sync_interval.dart';
import 'package:open_ring/features/settings/application/app_language_controller.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/app_language.dart';
import 'package:open_ring/features/widgets/application/widget_providers.dart';

// Health Connect and HealthKit records are never touched: the port only owns
// what lives on this phone inside OpenRing.
abstract interface class LocalDataEraser {
  Future<void> eraseAll();
}

final localDataEraserProvider = Provider<LocalDataEraser>(
  (ref) => throw UnimplementedError('Override localDataEraserProvider.'),
);

enum DeletionStatus { idle, deleting, failed }

final NotifierProvider<DeleteAllDataController, DeletionStatus>
deleteAllDataProvider = NotifierProvider.autoDispose(
  DeleteAllDataController.new,
);

class DeleteAllDataController extends Notifier<DeletionStatus> {
  @override
  DeletionStatus build() => DeletionStatus.idle;

  Future<bool> delete() async {
    if (state == DeletionStatus.deleting) return false;
    state = DeletionStatus.deleting;
    final alive = ref.keepAlive();
    try {
      await ref.read(localDataEraserProvider).eraseAll();
      await _resetInMemoryState();
      state = DeletionStatus.idle;
      return true;
    } on Exception {
      state = DeletionStatus.failed;
      return false;
    } finally {
      alive.close();
    }
  }

  Future<void> _resetInMemoryState() async {
    await ref.read(themeModeProvider.notifier).select(ThemeMode.system);
    await ref.read(appLanguageProvider.notifier).select(AppLanguage.system);
    await ref.read(syncIntervalProvider.notifier).select(SyncInterval.fallback);
    await ref.read(onboardingProvider.notifier).reset();
    await ref.read(todayWidgetConfigProvider.notifier).reset();
    ref
      ..invalidate(unitSystemProvider)
      ..invalidate(userProfileProvider)
      ..invalidate(ringSyncProvider);
    ref.read(dataRevisionProvider.notifier).bump();
  }
}
