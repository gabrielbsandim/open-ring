# OpenRing

A free, open-source companion app for the COLMI R09 smart ring. It keeps the
ring synced on its own, shows sleep, heart and activity on calm, readable
screens, and keeps your data on your phone.

No account, no cloud, no ads, no subscription. MIT licensed.

## Supported rings

| Ring | Status | What that means |
| :--- | :--- | :--- |
| COLMI R09 | Tested | The only ring on the desk. Every protocol check is made on it. |
| COLMI R02, R03, R06, R10 | May work | Same protocol, not tested yet. |
| Other brands | Need hardware | The driver interface is ready; a driver lands when a ring is on the desk. |

The ring talks to one app at a time: disconnect it from QRing before pairing it
with OpenRing.

## Features

- Background sync: the ring stores its history, the phone connects on a
  schedule (every 60 minutes by default, 15 to 120 to choose from), pulls what
  is new and disconnects. No always-on connection.
- Sleep as a hypnogram (light, deep, REM, awake), with a night split by a wake
  up still counted as one night.
- Heart rate through the day, resting heart rate, HRV, SpO2 and stress.
- Steps, distance and active energy.
- Readiness and sleep scores that show their inputs. Every formula is published
  in [`docs/metrics.md`](docs/metrics.md).
- Phone-led workouts with live heart rate from the ring and, outdoors, a GPS
  route with distance, pace and splits.
- Health Connect: writes steps, active energy, heart rate, SpO2, HRV, sleep
  stages and workouts with their route. Reading sleep that other apps wrote is
  opt-in.
- Export to CSV and JSON, and any workout route to GPX
  ([`docs/export-format.md`](docs/export-format.md)).
- Home screen widgets (Jetpack Glance): Readiness, Today, Ring, Start workout.
- 11 languages (English, Portuguese for Brazil and Portugal, Spanish, French,
  German, Italian, Russian, Simplified Chinese, Japanese, Indonesian), light and
  dark themes, text scaling up to 200%.

Every number is an estimate from a consumer ring, meant for following trends.
OpenRing is not a medical device and does not diagnose anything.

## Privacy

- No account, no sign-up, no login.
- Data lives in a local SQLite database on the phone. There is no OpenRing
  server.
- The only network use is the Shorebird updater, which checks for and downloads
  app updates and sends no health data: no analytics, no crash reporting, no
  telemetry. See the [privacy policy](docs/privacy-policy.md).
- Android cloud backup is off, so the database is not copied to a Google
  account.
- Health data leaves the phone only when you choose: to Health Connect, or in a file
  you export and share.

Full text: [`docs/privacy-policy.md`](docs/privacy-policy.md).

## Platforms

- **Android** 9 (API 28) or newer, with Health Connect. This is the platform
  that ships first.
- **iOS** is deferred until a Mac is available. The Dart side of HealthKit and
  WidgetKit exists behind platform checks but is not built or tested.

## Building

A Dart pub workspace: `apps/mobile` (the Flutter app) plus the pure Dart
packages `packages/ring_protocol`, `packages/ring_driver`, `packages/metrics`,
the Android-only Flutter plugins `packages/health_connect_writer` (Health
Connect channels for every engine) and `packages/ring_notifications` (ring
alerts for every engine), and the `tools/trace_replay` CLI. Requires Flutter stable with Dart 3.13.5 or
newer and a JDK 17.

```sh
flutter pub get                                   # whole workspace, from the repo root
flutter run                                       # from apps/mobile, with a phone attached
flutter build apk --release                       # from apps/mobile
flutter build appbundle --release                 # from apps/mobile
```

Without `apps/mobile/android/key.properties` the release build is signed with
the debug key and Gradle prints a warning. Signing, store upload and F-Droid
notes are in [`docs/release.md`](docs/release.md).

Tests and project rules: [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Documentation

- [`docs/plan.md`](docs/plan.md): current plan, scope, architecture, phases and
  the decisions log. Wins over any older document.
- [`docs/design-tokens.md`](docs/design-tokens.md): colours, themes and text
  scaling rules.
- [`docs/metrics.md`](docs/metrics.md): every derived score and its formula.
- [`docs/health-platforms.md`](docs/health-platforms.md): what is written to
  Health Connect and HealthKit, and the known gaps.
- [`docs/export-format.md`](docs/export-format.md): CSV, JSON and GPX formats.
- [`docs/protocols/realsil-colmi.md`](docs/protocols/realsil-colmi.md): the
  Colmi BLE protocol, with each command marked verified or not.
- [`docs/architecture.md`](docs/architecture.md),
  [`docs/product-vision.md`](docs/product-vision.md),
  [`docs/features-benchmark.md`](docs/features-benchmark.md),
  [`docs/market-analysis.md`](docs/market-analysis.md): discovery material.
- [`docs/privacy-policy.md`](docs/privacy-policy.md) and
  [`docs/release.md`](docs/release.md): release documents.

## License

[MIT](LICENSE). Third-party packages keep their own licenses; note that
`flutter_blue_plus` is free for personal, nonprofit and educational use only,
see [`docs/release.md`](docs/release.md).
