import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/settings/application/about_providers.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test('the version comes from the build info', () async {
    PackageInfo.setMockInitialValues(
      appName: 'OpenRing',
      packageName: 'gbs.openring.app',
      version: '3.2.1',
      buildNumber: '45',
      buildSignature: '',
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(await container.read(appVersionProvider.future), '3.2.1');
  });
}
