import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

// Product names stay untranslated; an unknown app shows its package name.
const Map<String, String> knownSourceApps = {
  'com.google.android.apps.fitness': 'Google Fit',
  'com.google.android.apps.healthdata': 'Health Connect',
  'com.sec.android.app.shealth': 'Samsung Health',
  'com.garmin.android.apps.connectmobile': 'Garmin Connect',
  'com.fitbit.FitbitMobile': 'Fitbit',
  'com.ouraring.oura': 'Oura',
  'com.withings.wiscale2': 'Withings',
  'com.xiaomi.wearable': 'Mi Fitness',
  'com.mi.health': 'Mi Fitness',
  'com.huawei.health': 'Huawei Health',
  'com.urbandroid.sleep': 'Sleep as Android',
  'fi.polar.polarflow': 'Polar Flow',
  'com.suunto.android': 'Suunto',
  'com.whoop.android': 'WHOOP',
  'com.zepp.app': 'Zepp',
};

String sourceName(String source, AppLocalizations l10n) {
  if (source == ringSource) return l10n.sourcesFromRing;
  return knownSourceApps[source] ?? source;
}
