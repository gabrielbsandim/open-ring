import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/ring/application/sync_alerts.dart';
import 'package:open_ring/features/ring/application/sync_paired_ring.dart';
import 'package:open_ring/features/ring/domain/ring_alerts.dart';
import 'package:open_ring/features/ring/infrastructure/drift_sync_store.dart';
import 'package:open_ring/features/settings/domain/app_language.dart';

Future<void> sendBackgroundSyncAlerts({
  required AppDatabase database,
  required SyncOutcome? outcome,
  required RingAlertPreferences preferences,
  required RingNotifier notifier,
  required Future<AppLanguage?> Function() language,
}) async {
  if (outcome == null) return;
  final chosen = await language();
  await SyncAlerts(
    store: DriftSyncStore(database),
    preferences: preferences,
    notifier: notifier,
    strings: ringAlertStrings(chosen?.locale),
  ).afterSync(outcome);
}
