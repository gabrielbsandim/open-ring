# Releasing OpenRing for Android

How to sign, build and publish the Android app. iOS is deferred until a Mac is
available (see the decisions log in [`plan.md`](plan.md)).

## Version

The version comes from `apps/mobile/pubspec.yaml`:

```yaml
version: 0.1.0+1
```

`0.1.0` becomes `versionName` and `1` becomes `versionCode`. The Release workflow
moves both, from the Conventional Commits since the last `v*` tag: `feat` is a
minor, anything else a patch.

## Release flow

Work lands on `develop`. `main` only changes through the release pull request.

1. Rewrite the 11 files in `apps/mobile/distribution/whatsnew` on `develop`, at
   most 500 characters each. Play shows them as this version's notes.
2. `gh workflow run release.yml --ref develop`, optionally `-f bump=minor`. It
   bumps the version on `develop`, opens or refreshes the pull request into
   `main` and starts the gates. Its own check stays red until step 1 is done.
3. Merge with **Create a merge commit**, not squash.

The merge reuses the gates when the tree is unchanged, tags `vX.Y.Z`, publishes
the GitHub release with notes from the commits, runs a Shorebird release, attaches
the APK to the GitHub release and, once `PLAY_SERVICE_ACCOUNT` is set, sends the
bundle to the Play internal track. The first upload to Play has to be by hand.

A Dart-only fix for a released version goes over the air, from a ref whose
`pubspec.yaml` still names that version:

```sh
gh workflow run patch.yml --ref hotfix/<slug>   # add -f track=stable to skip staging
```

A change to `android/` or to a plugin cannot be patched and needs a release.

Repository secrets:

| Secret | What |
| :--- | :--- |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` | The upload key, `alias upload`, one password for store and key |
| `SHOREBIRD_TOKEN` | API key of the `open-ring-ci` service account (role `developer`), expires 2027-11-11. Issue a new one in the Shorebird console. Without it the release is a plain signed build that cannot take patches |
| `PLAY_SERVICE_ACCOUNT` | Optional, JSON of a Play service account |

## Signing

The release build reads its key from `apps/mobile/android/key.properties`. The
file and every `*.jks` or `*.keystore` are ignored by git anywhere in the
repository (root `.gitignore`). Never commit them, never paste their contents
into an issue or a log.

1. Create an upload key once, on your own machine, and keep it outside the
   repository (a password manager or an encrypted drive, plus an offline
   backup):

   ```sh
   keytool -genkeypair -v -keystore ~/keys/openring-upload.jks \
     -keyalg RSA -keysize 4096 -validity 10000 -alias upload
   ```

2. Create `apps/mobile/android/key.properties`:

   ```properties
   storeFile=/home/you/keys/openring-upload.jks
   storePassword=...
   keyAlias=upload
   keyPassword=...
   ```

   `storeFile` may be absolute or relative to `apps/mobile/android`. A missing
   or blank entry fails the build with the name of the entry.

3. Enrol in Play App Signing when you create the app in Play Console. Google
   keeps the app signing key; the key above is only the upload key, and Google
   can reset it if it is lost.

Without `key.properties` the release build falls back to the debug key and
Gradle prints:

```
WARNING: .../apps/mobile/android/key.properties not found. The release build is signed with the debug key and cannot be uploaded to a store. See docs/release.md.
```

That build installs and runs, but Play rejects it and it cannot update a build
signed with the real key.

## Building

From `apps/mobile`:

```sh
flutter build appbundle --release   # Play upload: build/app/outputs/bundle/release/app-release.aab
flutter build apk --release         # sideload and GitHub releases: build/app/outputs/flutter-apk/app-release.apk
flutter build apk --release --split-per-abi   # one smaller APK per CPU architecture
```

Release builds run R8 with code minification and resource shrinking
(`android/app/build.gradle.kts`). Keep rules live in
`android/app/proguard-rules.pro`:

- `home_widget` loads the widget receivers with `Class.forName`, from names
  that Dart passes and that its scheduler stores.
- WorkManager instantiates the `workmanager` worker by class name from its
  database.
- `flutter_blue_plus`, `health`, the Health Connect record classes and
  `geolocator` are kept whole until a minified build has gone through pairing,
  sync, Health Connect writes and a GPS workout on the R09. Narrow them after
  that check.
- `res/raw/keep.xml` keeps `ic_notification`, a monochrome status bar icon that
  is only looked up by name.

Each build writes `build/app/outputs/mapping/release/mapping.txt`. Upload it
with the bundle in Play Console (App bundle explorer, Downloads, ReTrace
mapping file) so crash stack traces in Android vitals can be read, and keep a
copy with the release tag.

Before uploading, check what was built:

```sh
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk
```

Both tools are in `<Android SDK>/build-tools/<version>/`. The certificate must
be the upload key, not `CN=Android Debug`. `android.permission.INTERNET` is there
for the Shorebird updater and for nothing else.

CI builds the same APK with no secrets, so it carries the debug key and is only
a build check.

## Play Console

### Store listing

`apps/mobile/fastlane/metadata/android/` follows the fastlane `supply` layout:
one folder per locale with `title.txt`, `short_description.txt`,
`full_description.txt`, plus `en-US/images/icon.png` (512 x 512).
`flutter test test/release/store_listing_test.dart` checks the limits (title 30,
short description 80, full description 4000 characters) and the dash rule.

Still to add by hand: a 1024 x 500 feature graphic and phone screenshots from a
real device. Upload with `fastlane supply --aab ... --track internal` or paste
the text into Play Console.

The copy promises nothing medical. Keep it that way: Play treats claims of
diagnosis or treatment as a medical device app, which needs regulatory proof.

### Privacy policy

Use the public URL of [`privacy-policy.md`](privacy-policy.md) on GitHub. Play,
Health Connect and the in-app rationale screen all need it. Change it before a
release that changes what the app touches.

### Data safety

Answers derived from the privacy policy. Under Play's definitions, data is
"collected" only when it is sent off the device by the app, and a transfer the
user starts (sharing an export) is not "sharing". Recheck these against the
form's current wording before each submission.

| Question | Answer | Reason |
| :--- | :--- | :--- |
| Does your app collect or share any of the required user data types? | Yes, collected, not shared | Only the Shorebird update check. Everything else stays on the device. |
| Device or other IDs | Collected, required, purpose App functionality | The random install identifier Shorebird creates and sends with each update check. Not linked to a person, no account exists. |
| App info and performance | Not collected | The update check sends the version, patch number, platform and architecture, which Play does not list as a data type. Recheck against the form's wording. |
| Data written to Health Connect | Not collection | Health Connect is on the device; the user grants each type and manages it there. |
| CSV, JSON and GPX export | Not sharing | User initiated, through the Android share sheet. |
| Location | Not collected | Used on the device during a workout only, stored locally, written to Health Connect only as the exercise route if the user allows it. |
| Is all user data encrypted in transit? | Yes | The update check is the only transfer, and it uses HTTPS. |
| Can users request that data be deleted? | Clear storage or uninstall deletes everything on the device, the install identifier included; Health Connect data is deleted in Health Connect. | |

Other App content answers: no ads, no account (so no account deletion URL),
not directed at children, content rating questionnaire with no objectionable
content, category Health and Fitness.

### Health apps declaration

Declare the app as a health and fitness app that reads data from a wearable.
State that it is not a medical device and does not offer diagnosis or
treatment.

### Health Connect declaration

Play Console, App content, Health Connect. Declare every permission the
manifest requests and give a use for each:

| Permission | Use to declare |
| :--- | :--- |
| Write steps, active calories burned, distance | Daily activity measured by the user's ring |
| Write heart rate, heart rate variability, oxygen saturation | Samples the ring measured |
| Write sleep | Nights the ring recorded, as one session with its stages |
| Write exercise, exercise route | Workouts the user records in the app, with the GPS route of outdoor ones |
| Read sleep | Opt-in: show nights recorded by another device, off by default |
| Read exercise | Opt-in: show workouts recorded by another app, off by default |

Requirements Google checks during review:

- The rationale activity: `MainActivity` handles
  `androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE`, and the
  `ViewPermissionUsageActivity` alias handles `VIEW_PERMISSION_USAGE` on
  Android 14 and later. Both open the in-app privacy screen
  (`openring://app/privacy`, set in `MainActivity`), whose text comes from
  `docs/privacy-policy.md`. The route is covered by tests but has not been
  opened from Health Connect on a real phone; check that before submitting.
- Request only what is declared. A permission added to the manifest needs a
  new declaration before the build that ships it.
- No background read (`READ_HEALTH_DATA_IN_BACKGROUND`) is requested, so none
  is declared.

### Foreground service and location

- Foreground service type `location` (geolocator's service, during a workout
  only). Play asks for a short video showing a workout started by the user,
  the ongoing notification and the route.
- Location is foreground only; no `ACCESS_BACKGROUND_LOCATION`, so no
  background location declaration.
- Foreground service type `connectedDevice` (`RingSyncForegroundService`,
  during a background sync with the paired ring only). Use to declare: without
  it Android kills the idle process while the periodic job is talking to the
  ring over Bluetooth. Play asks for a video; show the ongoing sync
  notification in the shade while a sync runs with the app closed.

### Battery optimization exemption

`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` is reviewed by Play. Use to declare: the
core function is reading a Bluetooth ring on a schedule with the app closed,
the ring only keeps a limited history, and Android does not allow the
foreground service above to start from the background without the exemption.
The app asks once in onboarding through Android's own dialog, and works
without it, with syncs that may run late or stop midway.

## Before each release

1. `dart format --output=none --set-exit-if-changed .`, `flutter analyze` and
   every test suite green (see [`../CONTRIBUTING.md`](../CONTRIBUTING.md)).
2. Rewrite the 11 what's new files.
3. Install a release APK from the same commit on the R09 test phone and go
   through [Device checks](#device-checks). This is the only place a missing
   keep rule shows up.
4. Run the [release flow](#release-flow). Play takes the internal track first.

## Device checks

Inspecting the mapping file and the merged manifest shows that classes and
entries survive R8, not that they work. Each item needs a release build, not a
debug one:

- BLE: scan, pair and a foreground sync with the ring (`flutter_blue_plus`).
- Background sync: the periodic WorkManager job fires with the app closed,
  after a reboot and after an app update (`workmanager` and its
  `backgroundSyncDispatcher` entry point), and the sync notification shows for
  the length of the run (`RingSyncForegroundService`).
- Health Connect: grant permissions, write every type through `health` and
  `health_connect_writer`, and read back the opt-in sleep and exercise.
- Health Connect links: the privacy link in Health Connect's permission screen
  opens the app and leads to the policy.
- GPS workout: the ongoing notification, the route and its write to Health
  Connect (`geolocator`).
- External links open (`url_launcher`), exports reach the share sheet and every
  widget renders and updates.

## Release constraints

- `flutter_blue_plus` stays on 2.x under its nonprofit license, on the terms
  recorded in the decisions log of [`plan.md`](plan.md) (2026-11-10) and
  described under [F-Droid](#f-droid). The terms apply to every channel, not
  only F-Droid: read the current license text again before a release that
  changes how the app is sold or who distributes it.
- Its build-time license ping also runs on every local and CI build.

## F-Droid

F-Droid builds every app from source and only accepts free software, so two
dependencies and the updater block the main repository today.

- **flutter_blue_plus license.** Versions 2.x ship under the FlutterBluePlus
  License 1.6: free for personal, nonprofit and educational use, a paid license
  for any for-profit use, and relicensing forbidden. That is not a free
  software license, so F-Droid would list it as a non-free dependency.
  OpenRing uses it under the open use terms because the app is not sold
  (decisions log, 2026-11-10). The license also carries a build-time ping:
  `flutter_blue_plus_android/android/license_ping.gradle` posts the package
  name, app name, version, library version and date to a Google Apps Script
  URL before every build, failing open. F-Droid's scanner flags that. BLE is
  behind the `BleTransport` port, so the way out is an adapter over a BLE
  plugin with an OSI license; check the license of the candidate before
  writing it.
- **Google Play services.** `geolocator_android` depends on
  `com.google.android.gms:play-services-location`, which is proprietary. An
  F-Droid flavour would need geolocator's `LocationManager` path
  (`forceLocationManager: true`) and the dependency excluded, or a different
  location plugin.
- **Shorebird.** The updater inside the engine is a proprietary service
  dependency and needs `INTERNET`; an F-Droid flavour would build with plain
  Flutter and without `shorebird.yaml`.

Until all three are solved, the realistic channels are the GitHub release APK and a
self-hosted F-Droid repository or IzzyOnDroid, which list non-free parts as
anti-features.

Reproducible builds, needed for F-Droid to ship the developer's signature
instead of its own:

- Pin every input: the Flutter version (record the exact framework revision
  in the release notes; this machine uses Shorebird's Flutter fork, so an
  F-Droid recipe must name upstream Flutter stable at the same version), the
  JDK (17), the Gradle wrapper, AGP and Kotlin (`settings.gradle.kts`) and
  `pubspec.lock`, which is committed.
- Build from the same absolute path inside a container, since tool caches and
  paths can end up in build metadata.
- Do not add build timestamps or a git hash generated at build time.
- Compare the result with the developer APK using F-Droid's
  `apksigcopier` flow: copy the signature from the published APK onto the
  rebuilt one and check that it verifies.

Treat reproducibility as unproven until two clean builds on different machines
produce identical unsigned APKs.
