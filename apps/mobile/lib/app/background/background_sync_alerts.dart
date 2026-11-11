import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/ring/application/sync_alerts.dart';
import 'package:open_ring/features/ring/application/sync_paired_ring.dart';
import 'package:open_ring/features/ring/domain/ring_alerts.dart';
import 'package:open_ring/features/ring/infrastructure/drift_sync_store.dart';

Future<void> sendBackgroundSyncAlerts({
  required AppDatabase database,
  required SyncOutcome? outcome,
  required RingAlertPreferences preferences,
  required RingNotifier notifier,
}) async {
  if (outcome == null) return;
  await SyncAlerts(
    store: DriftSyncStore(database),
    preferences: preferences,
    notifier: notifier,
    strings: ringAlertStrings(),
  ).afterSync(outcome);
}
