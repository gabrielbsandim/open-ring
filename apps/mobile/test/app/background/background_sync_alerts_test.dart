import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/background/background_sync_alerts.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/application/sync_paired_ring.dart';
import 'package:open_ring/features/ring/application/sync_ring.dart';
import 'package:open_ring/features/ring/domain/ring_alerts.dart';
import 'package:open_ring/features/ring/domain/sync_run.dart';
import 'package:open_ring/features/ring/infrastructure/drift_sync_store.dart';
import 'package:open_ring/features/settings/domain/app_language.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../helpers/database.dart';

final _failure = SyncFailed(
  SyncAbortedException(SyncStep.connecting, Exception('out of range')),
);
final _at = DateTime.utc(2026, 11, 10, 9);

Future<void> _logFailures(AppDatabase db, int count) async {
  for (var i = 0; i < count; i++) {
    await DriftSyncStore(db).recordRun(
      ringId,
      SyncRun(
        at: _at.add(Duration(minutes: i)),
        outcome: SyncRunOutcome.unreachable,
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late InMemoryRingNotifier notifier;

  setUp(() async {
    db = await pairedDatabase();
    notifier = InMemoryRingNotifier();
  });

  Future<void> send(
    SyncOutcome? outcome, {
    AppLanguage? language,
    RingAlertPreferences? preferences,
  }) => sendBackgroundSyncAlerts(
    database: db,
    outcome: outcome,
    preferences: preferences ?? InMemoryRingAlertPreferences(),
    notifier: notifier,
    language: () async => language,
  );

  test('the third logged failure alerts in the stored language', () async {
    await _logFailures(db, 3);

    await send(_failure, language: AppLanguage.japanese);

    expect(
      notifier.shown.single.title,
      lookupAppLocalizations(const Locale('ja')).ringAlertSyncFailedTitle,
    );
  });

  test('a fourth logged failure stays silent', () async {
    await _logFailures(db, 4);

    await send(_failure);

    expect(notifier.shown, isEmpty);
  });

  test('the worker toggle store is honored', () async {
    await _logFailures(db, 3);

    await send(
      _failure,
      preferences: InMemoryRingAlertPreferences(
        enabled: {RingAlert.lowBattery},
      ),
    );

    expect(notifier.shown, isEmpty);
  });

  test('a run that never produced an outcome sends nothing', () async {
    await _logFailures(db, 3);

    await send(null);

    expect(notifier.shown, isEmpty);
  });
}
