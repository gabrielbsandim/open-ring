# OpenRing

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Flutter-3DDC84.svg?logo=android&logoColor=white)]()
[![Google Play](https://img.shields.io/badge/Google%20Play-OpenRing-414141.svg?logo=google-play&logoColor=white)](https://play.google.com/store/apps/details?id=gbs.openring.app)
[![Website](https://img.shields.io/badge/Website-gabrielbsandim.github.io%2Fopen--ring-brightgreen)](https://gabrielbsandim.github.io/open-ring/)

A free, privacy-first, open-source companion app for budget smart rings (COLMI R09 and compatible hardware). OpenRing keeps the ring synced autonomously, displays sleep stages, heart metrics, and activity on calm, readable screens, and stores 100% of your data locally on your device.

**No accounts. No cloud servers. No ads. No subscriptions.**

---

## Download & Install

- **Google Play:** [Install from Google Play Store](https://play.google.com/store/apps/details?id=gbs.openring.app)
- **Direct APK:** Download the signed APK from [GitHub Releases](https://github.com/gabrielbsandim/open-ring/releases). *(Note: Play Store and GitHub APKs use different signing keys; switching between them requires an uninstall, which wipes local app data).*

---

## Supported Rings

| Ring Model | Status | Notes |
| :--- | :--- | :--- |
| **COLMI R09** | **Fully Tested** | Hardware reference device. All BLE protocol commands are verified against it. |
| **COLMI R02, R03, R06, R10** | Compatible | Share the same underlying Realtek/Colmi protocol; expected to work. |
| **Other Brands** | In progress | Modular driver interface is ready; new drivers are added as hardware is verified. |

> **Important:** Smart rings talk to one client at a time. Disconnect and unpair the ring from official apps (e.g., QRing) before pairing with OpenRing.

---

## Features

- **Battery-Friendly Background Sync:** The ring logs data internally; the phone connects periodically on a custom schedule (default: 60 min, configurable from 15 to 120 min), pulls new deltas, and disconnects immediately.
- **Sleep Hypnogram:** Displays awake, REM, light, and deep sleep stages. Multi-segment nights with wake-ups are unified into a single coherent sleep record.
- **Biometrics & Heart Metrics:** Continuous heart rate, resting heart rate, Heart Rate Variability (HRV), blood oxygen (SpO2), and stress estimation.
- **Transparent Readiness & Sleep Scores:** Every score shows its exact weighted inputs. All formulas are openly documented in [`docs/metrics.md`](docs/metrics.md).
- **Workouts with GPS:** Phone-led tracking with live heart rate stream from the ring, outdoor GPS route mapping, splits, pace, and elevation.
- **Android Health Connect:** Seamless two-way integration. Writes sleep stages, heart rate, HRV, SpO2, steps, energy, and workouts with GPS routes.
- **Data Portability:** Export full raw history to CSV or JSON anytime. Export workout routes to GPX ([`docs/export-format.md`](docs/export-format.md)).
- **Home Screen Widgets:** Jetpack Glance widgets for Today summary, Ring battery/status, Readiness, and Quick Workout Start.
- **Accessibility & Internationalization:** 11 languages (English, Portuguese BR/PT, Spanish, French, German, Italian, Russian, Simplified Chinese, Japanese, Indonesian), high-contrast light and dark themes, dynamic font scaling up to 200%.

> *Disclaimer: Metrics are estimates from consumer hardware for wellness and trend-tracking. OpenRing is not a medical device.*

---

## Privacy by Design

- **Zero Cloud Architecture:** Data lives entirely in a local SQLite database on your device. There is no OpenRing backend or account system.
- **No Telemetry or Tracking:** Zero analytics SDKs, zero crash tracking, zero advertising identifiers.
- **Encrypted Local Storage:** Android cloud backup is disabled to prevent database leakage to external cloud backups.
- **OTA Updates:** Uses Shorebird exclusively for delta app binary updates; no user or health telemetry is ever transmitted.
- **You Control Export:** Health data only leaves your phone when you explicitly choose to export files or sync with Android Health Connect.

Full policy: [`docs/privacy-policy.md`](docs/privacy-policy.md).

---

## Project Structure & Architecture

OpenRing is structured as a Dart pub workspace:

```
open-ring/
├── apps/
│   └── mobile/                        # Flutter companion application
├── packages/
│   ├── ring_protocol/                 # Pure Dart: byte encoding & packet decoding
│   ├── ring_driver/                   # BLE connection state machine & abstraction
│   ├── metrics/                       # Sleep, heart, and readiness score formulas
│   ├── health_connect_writer/         # Android platform channel for Health Connect
│   └── ring_notifications/            # Foreground service & local ring alerts
├── tools/
│   └── trace_replay/                  # CLI tool to replay BLE packet captures
├── site/                              # Static multilingual landing page (GitHub Pages)
└── docs/                              # Architecture, protocol specs, and evals
```

---

## Building from Source

### Prerequisites

- Flutter stable (Dart SDK `^3.13.5`)
- JDK 17+
- Android SDK (API 34)

### Build Commands

```sh
# Fetch dependencies across the entire pub workspace
flutter pub get

# Run static analysis and lint checks
flutter analyze

# Run unit tests across pure Dart packages
dart test packages/ring_protocol/test
dart test packages/ring_driver/test
dart test packages/metrics/test

# Run Flutter widget and integration tests
flutter test apps/mobile/test

# Build signed release APK (debug signed if key.properties is omitted)
flutter build apk --release

# Build Android App Bundle for Google Play
flutter build appbundle --release
```

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for development guidelines and [`docs/release.md`](docs/release.md) for store signing instructions.

---

## Documentation Index

- [`docs/plan.md`](docs/plan.md): Master roadmap, active phase scope, and architectural decisions log.
- [`docs/metrics.md`](docs/metrics.md): Comprehensive scoring formulas and algorithms.
- [`docs/protocols/realsil-colmi.md`](docs/protocols/realsil-colmi.md): Realtek/COLMI BLE protocol specification.
- [`docs/health-platforms.md`](docs/health-platforms.md): Health Connect mapping and permissions.
- [`docs/export-format.md`](docs/export-format.md): Schema specifications for CSV, JSON, and GPX exports.
- [`docs/architecture.md`](docs/architecture.md): Flutter client architecture and Riverpod state machines.
- [`docs/privacy-policy.md`](docs/privacy-policy.md): Plain-language privacy commitments.

---

## License

This project is licensed under the [MIT License](LICENSE). Third-party dependencies retain their respective licenses (see [`docs/release.md`](docs/release.md) regarding `flutter_blue_plus`).
