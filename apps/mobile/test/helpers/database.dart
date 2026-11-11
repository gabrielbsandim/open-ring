import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/ring/infrastructure/ring_devices_dao.dart';
import 'package:ring_driver/ring_driver.dart';

const ringId = 'R09_C0FE';

const ringIdentity = RingIdentity(
  deviceId: ringId,
  name: 'R09_C0FE',
  model: 'R09',
);

AppDatabase memoryDatabase() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  addTearDown(db.close);
  return db;
}

Future<AppDatabase> pairedDatabase({DateTime? pairedAt}) async {
  final db = memoryDatabase();
  await RingDevicesDao(db)
      .pair(ringIdentity, at: pairedAt ?? DateTime(2026, 11));
  return db;
}

Future<int> rowCount(AppDatabase db, String table) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM $table')
      .getSingle();
  return row.read<int>('c');
}
