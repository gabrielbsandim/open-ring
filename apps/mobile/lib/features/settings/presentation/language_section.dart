import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/settings/application/app_language_controller.dart';
import 'package:open_ring/features/settings/domain/app_language.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class LanguageSection extends ConsumerWidget {
  const new({super.key});

  static Key optionKey(AppLanguage language) =>
      Key('settings_language_${language.name}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final system = AppLanguage.of(
      AppLocales.resolve(
        View.of(context).platformDispatcher.locales,
        AppLocales.supported,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(l10n.settingsLanguage),
        TileGroup(
          children: [
            RadioGroup<AppLanguage>(
              groupValue: ref.watch(appLanguageProvider),
              onChanged: (language) => _select(ref, language),
              child: Column(
                children: [
                  for (final language in AppLanguage.values)
                    RadioListTile<AppLanguage>(
                      key: optionKey(language),
                      value: language,
                      contentPadding: EdgeInsets.zero,
                      title: _title(l10n, language),
                      subtitle: language == AppLanguage.system
                          ? Text(l10n.settingsLanguageSystemNow(system.endonym))
                          : null,
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        CaptionText(l10n.settingsLanguageFallbackNote),
      ],
    );
  }

  Widget _title(AppLocalizations l10n, AppLanguage language) {
    if (language == AppLanguage.system) {
      return Text(l10n.settingsLanguageSystem);
    }
    return Text(language.endonym, locale: language.locale);
  }

  void _select(WidgetRef ref, AppLanguage? language) {
    if (language == null) return;
    unawaited(ref.read(appLanguageProvider.notifier).select(language));
  }
}

extension AppLanguageName on AppLanguage {
  String get endonym => switch (this) {
    AppLanguage.system || AppLanguage.english => 'English',
    AppLanguage.portugueseBrazil => 'Português (Brasil)',
    AppLanguage.portuguesePortugal => 'Português (Portugal)',
    AppLanguage.spanish => 'Español',
    AppLanguage.french => 'Français',
    AppLanguage.german => 'Deutsch',
    AppLanguage.italian => 'Italiano',
    AppLanguage.russian => 'Русский',
    AppLanguage.chineseSimplified => '简体中文',
    AppLanguage.japanese => '日本語',
    AppLanguage.indonesian => 'Bahasa Indonesia',
  };
}
