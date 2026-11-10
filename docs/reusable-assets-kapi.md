# Reusable Assets from Kapi & Codebase

Analysis of architectural patterns, platform channels, and utilities from **Kapi** (`apps/mobile`) and sister projects that can be directly adapted for **OpenRing**.

---

## 1. Architectural Blueprint

OpenRing adopts the battle-tested architecture established in Kapi:
* **Feature-First Clean Architecture**:
  * `lib/features/<feature>/domain`: Pure immutable entities, value objects, rules.
  * `lib/features/<feature>/application`: Controllers, state notifiers, use cases.
  * `lib/features/<feature>/infrastructure`: BLE drivers, platform channels, local database.
  * `lib/features/<feature>/presentation`: UI widgets, screens, reactive state bindings.
* **State Management**: Riverpod 3 (immutable state, functional listeners, no global mutable singletons).
* **Router**: `go_router` with declarative routes and deep-linking support.
* **Coding Standards**:
  * English code, comments, and documentation.
  * Strictly no em dash character (U+2014).
  * No nested `if`; guard clauses and early returns.
  * Clean, minimal logging via structured loggers.

---

## 2. Platform Channels (Health Connect & HealthKit)

Kapi has a fully functioning native Android Health Connect channel and iOS HealthKit architecture. OpenRing will invert the flow: while Kapi *reads* workouts from Health Connect, OpenRing *writes* high-fidelity ring data *to* Health Connect and HealthKit.

### From Kapi (`apps/mobile/android/.../HealthConnectChannel.kt`):
* Health Connect client initialization and permission negotiation contracts (`PermissionController`).
* Aggregation and record mapping logic for:
  * `ExerciseSessionRecord` (Structured workouts with pauses and timestamps).
  * `HeartRateRecord` (Series of BPM samples inside workouts and rest intervals).
  * `StepsRecord` and `ActiveCaloriesBurnedRecord`.
  * `DistanceRecord` and `ElevationGainedRecord`.
* **OpenRing Adaptation**:
  Implement the reciprocal `HealthConnectWriterChannel.kt` to push sleep hypnograms (`SleepSessionRecord`, `SleepStageRecord`), continuous heart rate, and workouts recorded by the smart ring.

### From Kapi iOS (`apps/mobile/ios`):
* Background execution configurations (`UIBackgroundModes`: `bluetooth-central`, `fetch`, `processing`).
* HealthKit store integrations for writing `HKCategoryTypeIdentifierSleepAnalysis`, `HKWorkout`, and `HKQuantityTypeIdentifierHeartRate`.

---

## 3. UI Design System & Component Library

From Kapi's design system:
* **Color Palette & Theme**:
  * Dark-mode first palette (deep zinc `#0F0F12`, dark charcoal card surfaces `#1A1A22`, energetic accent neon green `#22C55E` or electric teal `#06B6D4`).
  * Contrast-compliant typography tuned for health statistics.
* **Custom Visualizers**:
  * Circular progress rings for daily goals (Steps, Calories, Sleep Score).
  * Time-series sparklines and bar charts for hourly step distribution and heart rate zones.
  * Sleep hypnogram visualizer (differentiating Deep, Light, REM, and Awake stages).

---

## 4. Internationalization (i18n)

Following Kapi's rule:
* All user-facing strings live in ARB catalog files (`lib/l10n/app_en.arb`, `lib/l10n/app_pt.arb`).
* Code, tests, and comments remain 100% English.
* Guarantees native English and Portuguese translations without the awkward machine-translated text found in QRing.
