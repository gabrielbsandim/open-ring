# OpenRing Plan (v2)

Revised plan written on 2026-11-10 after auditing every document in `docs/`.
Where this file disagrees with an older document, this file wins.

## 1. Audit of the discovery material

What holds up:

- The problem is real and well described: budget rings have good hardware and a
  weak companion app, and the main gaps are sync reliability, Health Connect and
  HealthKit export (workouts above all), REM and split sleep, and data export.
- The screenshot catalogue is a faithful map of QRing's surface area.
- Feature-first layering with Riverpod 3, `go_router`, ARB i18n and
  `very_good_analysis` matches Kapi and is the right base.

What does not hold up, and what changes:

| Finding | Evidence | Decision |
| :--- | :--- | :--- |
| The Colmi protocol doc is wrong. UUIDs `fee7/fea1/fea2`, the `0xAB/0xAA` header, `0x07` daily summary, `0x09` live HR, `0x11` SpO2 and `0x14` temperature do not appear in any open implementation. | Gadgetbridge `ColmiR0xConstants.java`, `tahnok/colmi_r02_client`, `colmi.puxtril.com` | `protocols/realsil-colmi.md` rewritten from those sources. Every command is marked verified or unverified until the spike confirms it on the real ring. |
| The ring is not a Realtek-only story. Colmi rings speak a Nordic-UART-like service plus a second "big data" service. | Same sources | Driver is named `ColmiDriver`, not `RealsilColmiDriver`. Chipset is not the abstraction boundary; protocol is. |
| Five driver families planned (Realsil, Da Fit, JieLi, Nordic, SIG) with only one ring in hand. The Nordic row lists "Oura Gen 2 clones" with no source. | `multi-ring-architecture.md` | v1 ships one driver. The interface stays, with a capability set, so a second driver can land when a second ring is on the desk. A generic Bluetooth SIG Heart Rate driver is the cheapest second driver and is the only other one on the roadmap. |
| The "hybrid ingestion" model (also read watches through Health Connect) contradicts the core flow, which writes ring data to Health Connect. Reading and writing the same store creates feedback loops and duplicates. | `architecture.md` section 1 | In v1, read side is opt-in and origin-filtered: OpenRing reads sleep and workouts other apps wrote, never reads back records whose data origin is its own package, and resolves overlapping periods by a per-type source priority instead of summing. |
| Isar or Drift left open. Isar is no longer maintained upstream. | `architecture.md` section 4 | Drift (SQLite). Time series fit SQL well and migrations are explicit. |
| A persistent foreground service keeping the GATT link open all day. This is the same strategy that fails for QRing and drains both batteries. | `architecture.md` section 2 | Sync, do not stream. The ring stores history; the phone reconnects on a schedule, pulls, disconnects. A foreground service runs only during a live workout. |
| Workouts are started "on the ring". No ring workout command is documented in any source. | `multi-ring-architecture.md` interface | Workouts are phone-led: the phone owns the session clock, the ring streams real-time HR. Ring sport mode is a later spike. |
| Claims about QRing's cloud traffic ("unencrypted APIs in China") and Health Connect write set are not backed by a captured trace. | `module-specifications.md` section 9, `features-benchmark.md` | Kept as hypotheses, not stated in public copy until a network capture or decompiled call site is attached. |
| Custom MethodChannels for Health Connect and HealthKit from day one. | `architecture.md`, `reusable-assets-kapi.md` | Start with the `health` plugin (Kapi already uses it). Drop to a native channel only for a record type the plugin cannot write, with the gap written down first. |
| Readiness, sleep score and stress shown as if medically grounded. | `features-benchmark.md` section 3 | Every derived score has a published formula in `docs/metrics.md`, shows its inputs, and is labelled not medical. |
| Kapi XP named as the integration goal. | `roadmap.md` Phase 3 | Kapi stays a test consumer. The goal is a correct `ExerciseSessionRecord` / `HKWorkout`; any app benefits. |

## 2. Product scope

One sentence: a local-first companion for Colmi rings that syncs reliably,
shows honest metrics, and hands every sample to Health Connect and Apple Health.

### v1 (MVP) does

1. Pair a COLMI R09 and keep it synced without user action. The R09 is the only
   ring on the desk, so it is the only model v1 claims. Other Colmi models that
   share the protocol (R02, R03, R06, R10) are listed as "may work, untested".
2. Pull and store: steps and activity, heart rate log, SpO2, stress, HRV, sleep stages, battery.
3. Show: Today, Sleep, Heart, Activity, Ring, plus home and lock screen widgets on Android and iOS.
4. Record a phone-led workout with live HR from the ring and, for outdoor types, a GPS route with distance, pace and splits.
5. Write steps, active energy, heart rate series, sleep stages, SpO2, HRV and workouts with their GPS route to Health Connect and HealthKit.
6. Export everything to CSV and JSON.
7. Localized in English, Portuguese (Brazil and Portugal), Spanish, French, German, Italian, Russian, Chinese (Simplified), Japanese and Indonesian. English is the fallback for any other locale. Each locale gets a native-speaker review before release.
8. Read, opt-in, sleep and workouts that other devices wrote to Health Connect or HealthKit, with a per-type source priority.
9. Export workouts as GPX.

### Out of scope by design

Gestures, camera shutter, games, AI chat, couple vibration, prayer times and
cloud accounts. They are the bloat OpenRing exists to remove, not a backlog.

Other ring brands are blocked on hardware, not on scope: the driver interface
is ready, and a driver lands the day a second ring is on the desk.

## 3. Architecture

### Repository layout

```
open-ring/
  apps/mobile/                 Flutter app (Android + iOS)
    lib/
      app/                     bootstrap, router, theme
      core/                    logging, clock, result types, shared widgets
      features/
        ring/                  pairing, connection, sync orchestration
        today/                 home dashboard
        sleep/
        heart/                 HR, HRV, SpO2, stress
        activity/
        workout/               phone-led workout recorder
        health_sync/           Health Connect / HealthKit writers
        export/
        settings/
      l10n/                    app_en.arb, app_pt.arb
  packages/
    ring_protocol/             pure Dart: framing, checksum, commands, parsers
    ring_driver/               SmartRingDriver interface + ColmiDriver over a BleTransport port
    metrics/                   pure Dart: RHR, HRV baseline, sleep stitching, readiness
  tools/
    trace_replay/              Dart CLI that replays captured byte traces through the parsers
  docs/
```

Why packages: protocol parsing and metrics are pure functions over bytes and
samples. Keeping them out of Flutter makes them testable with `dart test` in
milliseconds and reusable by the trace CLI. Dart pub workspaces tie them together.

### Layers inside a feature

`domain` (entities, value objects, pure rules) then `application` (Riverpod
notifiers, use cases) then `infrastructure` (drift DAOs, BLE, platform) then
`presentation`. Domain imports nothing from Flutter.

### Driver contract (revised)

```dart
abstract interface class SmartRingDriver {
  RingIdentity get identity;
  Set<RingCapability> get capabilities;
  Stream<RingLinkState> get linkState;

  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<void> syncTime(DateTime now);
  Future<BatteryStatus> readBattery();

  Future<List<ActivityBucket>> pullActivity(DateTime since);
  Future<List<HeartRateSample>> pullHeartRate(DateTime since);
  Future<List<Spo2Sample>> pullSpo2(DateTime since);
  Future<List<StressSample>> pullStress(DateTime since);
  Future<List<HrvSample>> pullHrv(DateTime since);
  Future<List<SleepSegment>> pullSleep(DateTime since);

  Stream<LiveReading> startLive(LiveKind kind);
  Future<void> stopLive();
}
```

Changes from the old draft: pulls take `since` instead of a single date so a
reconnect after days offline backfills in one call; capabilities replace
assumptions; ring-side workouts are gone; `BleTransport` is a port with a
`flutter_blue_plus` adapter and an in-memory fake that replays traces.

### Sync model

- Triggers: app foreground, Android WorkManager periodic job (15 min floor,
  default 60 min), iOS `bluetooth-central` state restoration plus
  `BGAppRefreshTask`, and a manual pull-to-refresh.
- Each sync: connect, set time, read battery, pull every capability since the
  last cursor, write to drift in one transaction, advance cursors, disconnect.
- Health platform writes run after the local commit, from an outbox table, so a
  denied permission or a crash never loses data and never double-writes.
  Each record carries a stable client id for idempotent upserts.

### Storage (drift)

`ring_devices`, `sync_cursors`, `activity_buckets`, `hr_samples`, `spo2_samples`,
`stress_samples`, `hrv_samples`, `sleep_sessions`, `sleep_segments`,
`workouts`, `workout_hr_samples`, `workout_route_points`, `health_outbox`,
`source_priorities`, `user_profile`.
All timestamps in UTC epoch milliseconds plus the device offset at capture.

### Stack

Flutter stable (Dart 3.13), `flutter_riverpod` 3, `go_router`, `drift` +
`sqlite3_flutter_libs`, `flutter_blue_plus`, `health`, `workmanager`,
`fl_chart` plus custom painters for the hypnogram, `geolocator` for routes,
`home_widget` bridging to native widgets (Jetpack Glance on Android, WidgetKit
on iOS), `intl`, `very_good_analysis`.

## 4. Design direction

Dark first, calm, data before decoration. No photo backgrounds (QRing's
mountains and night skies make numbers hard to read). One accent per metric
family so a colour means the same thing on every screen: sleep violet, heart
coral, activity green, oxygen cyan, stress amber. Every score is tappable and
shows its inputs. Empty states say what to do, not "No Data Yet".

The prototype covers every v1 screen: onboarding and pairing, the daily tabs
and their detail screens, the workout flow with GPS route, ring, settings, data
sources, Health Connect and export, widgets, and every empty and error state.
Link: https://claude.ai/artifact/T1qhCioVXT7KAJFzwdz5Ht (private until shared).

## 5. Phases

| Phase | Goal | Exit check |
| :--- | :--- | :--- |
| 0. Foundation | Monorepo, CI, lint, empty app that runs on both platforms, design prototype | `flutter analyze` clean, `dart test` and `flutter test` green in CI, app launches on an Android device |
| 1. Protocol spike | Talk to the real ring. Debug screen that logs every frame. Capture traces of each command into `packages/ring_protocol/test/fixtures` | Each command in `realsil-colmi.md` marked verified or dropped; checksum rule settled by a captured frame |
| 2. Sync core | `ColmiDriver`, drift schema, sync orchestrator, background triggers | Ring left alone for 24 h: zero gaps in HR log compared with QRing for the same day |
| 3. Screens | Every prototype screen from real data, widgets, GPS workout | Every screen in every shipped locale, every empty and error state built |
| 4. Health platforms | Outbox and writers for Health Connect and HealthKit, route writer, opt-in readers with source priority | A workout recorded in OpenRing appears in Google Fit / Apple Health with HR series; sleep stages appear with REM |
| 5. Metrics | RHR, HRV baseline, sleep stitching, readiness, `docs/metrics.md` | Unit tests over recorded nights; formulas published |
| 6. Release | Export, onboarding, store assets, open-source release | Signed APK and TestFlight build |

## 6. Decisions log

| Date | Decision |
| :--- | :--- |
| 2026-11-10 | Repository is public. Screenshots and the module audit were reviewed before publishing. |
| 2026-11-10 | App id `gbs.openring.app` on Android and iOS. Dart package stays `open_ring`. |
| 2026-11-10 | Only a COLMI R09 is available. Every protocol check and every v1 support claim is about the R09. |
| 2026-11-10 | Widgets, GPS routes, GPX export and opt-in reading of other sources move into v1. Nothing is deferred past v1 except features removed by design. |
| 2026-11-10 | Locales: en, pt (Brazil), pt-PT, es, fr, de, it, ru, zh (Simplified), ja, id. English is the fallback for every other locale. |
| 2026-11-10 | Dark and light themes and text scaling from 85% to 200% are foundation work, specified in design-tokens.md and enforced by tests. |
