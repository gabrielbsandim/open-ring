import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/database/app_database.dart';

final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('Override appDatabaseProvider.'),
);
