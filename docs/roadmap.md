# Implementation Roadmap

Step-by-step delivery plan for OpenRing across five strategic phases.

---

## Phase 0: Discovery & Reverse Engineering (Current Phase)
* [x] Create repository structure and project workspace in `/home/gabriel/work/open-ring`.
* [x] Extract and decompile `qring.apk` from connected phone.
* [x] Capture on-device UI screenshot catalog of all QRing screens.
* [x] Audit Google Play Store, Apple App Store, and community feedback.
* [x] Document GATT services, characteristics, and packet framing for Realsil Colmi rings.
* [x] Design the universal `SmartRingDriver` multi-brand abstraction layer.
* [x] Map reusable components and platform channels from Kapi.

---

## Phase 1: Protocol Spikes & CLI / BLE Harness
* [ ] Initialize Flutter project with clean feature-first structure.
* [ ] Configure Android permissions (`BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`).
* [ ] Configure iOS `Info.plist` with `NSBluetoothAlwaysUsageDescription` and `UIBackgroundModes` (`bluetooth-central`).
* [ ] Build a standalone BLE debugging harness screen to test:
  * Scanning and pairing with `COLMI Ring 2`.
  * Time synchronization handshake.
  * Real-time heart rate and SpO2 stream.
  * Battery reading and charging state.
* [ ] Verify flash memory dump of daily step history and sleep records.

---

## Phase 2: Core Domain & Local Persistence
* [ ] Implement local database schema (Isar / Drift) for:
  * `RingDevice` (bonded MAC, brand, hardware family, firmware version).
  * `DailySummary` (date, steps, distance, active kcal).
  * `SleepSession` and `SleepStage` (timestamps, deep/light/rem/awake stages).
  * `HeartRateSample` (hourly series, resting heart rate, HRV).
* [ ] Implement `RealsilColmiDriver` complying with `SmartRingDriver`.
* [ ] Implement `RingDriverRegistry` with automatic device signature matching.
* [ ] Build background synchronization service (Android Foreground Service + iOS Background Tasks).

---

## Phase 3: Health Connect & Apple Health Bridges
* [ ] Implement Android Kotlin MethodChannel for Health Connect writers:
  * `SleepSessionRecord` & `SleepStageRecord`.
  * `StepsRecord` & `ActiveCaloriesBurnedRecord`.
  * `HeartRateRecord`.
  * `ExerciseSessionRecord` (Structured workouts with `RECORDING_METHOD_ACTIVELY_RECORDED`).
* [ ] Implement iOS Swift MethodChannel for Apple HealthKit writers:
  * `HKCategoryTypeIdentifierSleepAnalysis`.
  * `HKQuantityTypeIdentifierStepCount`, `HKQuantityTypeIdentifierActiveEnergyBurned`.
  * `HKQuantityTypeIdentifierHeartRate`.
  * `HKWorkout`.
* [ ] End-to-end integration test: Verify that a workout started in OpenRing is automatically detected and rewarded with XP in **Kapi**!

---

## Phase 4: Polish, Multi-Brand Expansion & Launch
* [ ] Build complete UI with dark theme, circular progress widgets, and sleep hypnogram charts.
* [ ] Add home screen widgets (iOS WidgetKit and Android AppWidget) for ring battery and sleep score.
* [ ] Implement second driver: `DaFitDriver` for Da Fit / Moyoung generic smart rings.
* [ ] Implement third driver: `JieLiDriver` for generic audio/touch smart rings.
* [ ] Local-first export options: One-tap export to CSV, JSON, and FIT formats.
* [ ] Open-source release and distribution (APK / TestFlight).
