import 'package:flutter/services.dart';
import 'package:open_ring/features/settings/domain/external_link_opener.dart';
import 'package:url_launcher/url_launcher.dart';

final class UrlLauncherExternalLinkOpener implements ExternalLinkOpener {
  const new();

  @override
  Future<void> open(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return;
    }
  }
}
