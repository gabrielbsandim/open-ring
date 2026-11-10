import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/router/app_router.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class OpenRingApp extends ConsumerWidget {
  const new({super.key});

  static Locale resolveLocale(Locale? device, Iterable<Locale> _) =>
      device?.languageCode == 'pt' ? const Locale('pt') : const Locale('en');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: AppTheme.dark,
      localeResolutionCallback: resolveLocale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: ref.watch(appRouterProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
