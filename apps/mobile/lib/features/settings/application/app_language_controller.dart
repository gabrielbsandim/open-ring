import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/settings/domain/app_language.dart';

final appLanguageStoreProvider = Provider<AppLanguageStore>(
  (ref) => InMemoryAppLanguageStore(),
);

final appLanguageProvider =
    NotifierProvider<AppLanguageController, AppLanguage>(
      AppLanguageController.new,
    );

class AppLanguageController extends Notifier<AppLanguage> {
  @override
  AppLanguage build() =>
      ref.watch(appLanguageStoreProvider).read() ?? AppLanguage.system;

  Future<void> select(AppLanguage language) async {
    state = language;
    await ref.read(appLanguageStoreProvider).write(language);
  }
}
