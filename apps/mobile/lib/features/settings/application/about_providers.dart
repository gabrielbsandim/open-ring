import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/settings/domain/external_link_opener.dart';
import 'package:open_ring/features/settings/infrastructure/url_launcher_external_link_opener.dart';
import 'package:package_info_plus/package_info_plus.dart';

final appVersionProvider = FutureProvider<String>(
  (ref) async => (await PackageInfo.fromPlatform()).version,
);

final externalLinkOpenerProvider = Provider<ExternalLinkOpener>(
  (ref) => const UrlLauncherExternalLinkOpener(),
);
