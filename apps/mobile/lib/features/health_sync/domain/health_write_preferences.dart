import 'package:open_ring/core/records/health_record_kind.dart';

abstract interface class HealthWritePreferences {
  Future<Set<HealthRecordKind>> disabled();

  Future<void> setEnabled(HealthRecordKind kind, {required bool enabled});
}

final class AllHealthWritesEnabled implements HealthWritePreferences {
  const new();

  @override
  Future<Set<HealthRecordKind>> disabled() async => const {};

  @override
  Future<void> setEnabled(
    HealthRecordKind kind, {
    required bool enabled,
  }) async {}
}

final class InMemoryHealthWritePreferences implements HealthWritePreferences {
  new([Set<HealthRecordKind>? off]) : off = off ?? {};

  final Set<HealthRecordKind> off;

  @override
  Future<Set<HealthRecordKind>> disabled() async => {...off};

  @override
  Future<void> setEnabled(
    HealthRecordKind kind, {
    required bool enabled,
  }) async {
    if (enabled) {
      off.remove(kind);
      return;
    }
    off.add(kind);
  }
}
