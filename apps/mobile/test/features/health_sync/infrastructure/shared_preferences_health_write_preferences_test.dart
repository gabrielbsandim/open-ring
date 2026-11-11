import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/infrastructure/shared_preferences_health_write_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('every type is written by default', () async {
    expect(await SharedPreferencesHealthWritePreferences().disabled(), isEmpty);
  });

  test('a disabled type survives a new instance and can return', () async {
    await SharedPreferencesHealthWritePreferences().setEnabled(
      HealthRecordKind.sleep,
      enabled: false,
    );
    expect(await SharedPreferencesHealthWritePreferences().disabled(), {
      HealthRecordKind.sleep,
    });

    await SharedPreferencesHealthWritePreferences().setEnabled(
      HealthRecordKind.sleep,
      enabled: true,
    );
    expect(await SharedPreferencesHealthWritePreferences().disabled(), isEmpty);
  });

  test('an unknown stored name is ignored', () async {
    SharedPreferencesAsyncPlatform
        .instance = InMemorySharedPreferencesAsync.withData({
      SharedPreferencesHealthWritePreferences.key: <String>['sleep', 'unknown'],
    });

    expect(await SharedPreferencesHealthWritePreferences().disabled(), {
      HealthRecordKind.sleep,
    });
  });
}
