# home_widget resolves widget receivers with Class.forName, from the names Dart
# passes (widget_gateway.dart) and from the names its update scheduler stores.
-keep class gbs.openring.app.widget.*Receiver { <init>(); }
-keep class es.antonborri.home_widget.** { *; }

# WorkManager stores the worker class name in its database and instantiates it
# by reflection when the periodic sync fires, possibly after an app update.
-keep class dev.fluttercommunity.workmanager.** { *; }

# Kept whole until a minified build has run pairing, sync, Health Connect writes
# and a GPS workout on the R09; narrow these after that check.
-keep class com.jmx.flutter_blue_plus.** { *; }
-keep class cachet.plugins.health.** { *; }
-keep class androidx.health.connect.client.records.** { *; }
-keep class com.baseflow.geolocator.** { *; }
