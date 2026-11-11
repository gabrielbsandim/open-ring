import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/database/app_database_provider.dart';
import 'package:open_ring/features/export/domain/data_exporter.dart';
import 'package:open_ring/features/export/infrastructure/drift_data_exporter.dart';

final dataExporterProvider = Provider<DataExporter>(
  (ref) => DriftDataExporter(
    database: ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
  ),
);
