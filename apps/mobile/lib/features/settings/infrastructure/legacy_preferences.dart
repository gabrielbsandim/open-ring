import 'package:shared_preferences/shared_preferences.dart';

// Settings that no longer exist; an old stored value must not linger.
const Set<String> legacyPreferenceKeys = {'app_language'};

Future<void> clearLegacyPreferences([SharedPreferencesAsync? preferences]) =>
    (preferences ?? SharedPreferencesAsync()).clear(
      allowList: legacyPreferenceKeys,
    );
