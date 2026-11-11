import 'package:drift_flutter/drift_flutter.dart';
import 'package:open_ring/core/database/app_database.dart';

AppDatabase openAppDatabase() => AppDatabase(
  driftDatabase(
    name: 'open_ring',
    native: const DriftNativeOptions(shareAcrossIsolates: true),
  ),
);
