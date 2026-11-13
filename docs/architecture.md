# OpenRing Client Architecture

Comprehensive architectural design for the Flutter cross-platform client (Android and iOS).

## 1. System Context & Layering

> [!NOTE] Hybrid Ingestion Model
> OpenRing adopts a hybrid telemetry model:
> 1. **Direct BLE Drivers**: Dedicated to Smart Rings (Colmi, Da Fit, JieLi, generic rings), providing raw sensor acquisition, offline flash history sync, and device controls.
> 2. **Health Platform Bridge**: Dedicated to external smartwatches and bands (Xiaomi, Garmin, Apple Watch, Samsung Galaxy Watch), reading structured workouts and metrics via Android Health Connect and Apple HealthKit without requiring reverse-engineered proprietary Bluetooth protocols.

```mermaid
flowchart TD
    subgraph UI ["Presentation Layer (Flutter)"]
        Dashboard["Dashboard & Metrics"]
        SleepView["Sleep Hypnogram View"]
        WorkoutView["Workout Recorder"]
        SettingsView["Device & Driver Settings"]
    end

    subgraph AppState ["Application State Layer (Riverpod 3)"]
        RingController["RingConnectionController"]
        HealthSyncController["HealthSyncController"]
        MetricsNotifier["DailyMetricsNotifier"]
    end

    subgraph Domain ["Domain Layer"]
        RingDriver["SmartRingDriver (Interface)"]
        SleepModel["SleepSession & Stages"]
        WorkoutModel["RingWorkout"]
        BiometricsModel["BiometricsSnapshot"]
    end

    subgraph Drivers ["Infrastructure: Hardware Drivers"]
        RealsilDriver["RealsilColmiDriver (R09/R02)"]
        DaFitDriver["DaFitDriver"]
        JieLiDriver["JieLiDriver"]
    end

    subgraph Storage ["Infrastructure: Persistence"]
        LocalDb["Local Database (SQLite via drift)"]
        SecureStore["FlutterSecureStorage (Bonding keys)"]
    end

    subgraph Bridges ["Infrastructure: OS Health Bridges"]
        HealthConnectBridge["Health Connect Writer (Android)"]
        HealthKitBridge["HealthKit Writer (iOS)"]
    end

    UI --> AppState
    AppState --> Domain
    AppState --> Storage
    AppState --> Bridges
    Domain --> Drivers
    Drivers --> BleStack["flutter_blue_plus (BLE Transport)"]
```

---

## 2. Bluetooth Lifecycle & State Machine

Managing Bluetooth Low Energy connections with wearables requires a resilient state machine to handle aggressive OS battery management:

```mermaid
stateDiagram-v2
    [*] --> Idle: App Startup
    Idle --> Scanning: User initiates pairing or background auto-connect
    Scanning --> Connecting: Target ring advertisement detected
    Connecting --> Authenticating: GATT services discovered
    Authenticating --> Syncing: Clock synchronized & handshake validated
    Syncing --> Connected: Flash history downloaded & parsed
    
    Connected --> Streaming: Active workout or live telemetry requested
    Streaming --> Connected: Session ends
    
    Connected --> Disconnecting: Sync or workout done
    Connected --> Idle: Connection dropped, retried at the next sync
    Disconnecting --> Idle: Clean disconnect
```

### Key Strategies:
1. **Connect, sync, disconnect**: The app holds no permanent link and runs no reconnect loop. Each sync (app foreground, pull to refresh, the WorkManager job) connects, pulls, and disconnects; a dropped link waits for the next sync. Only a workout keeps the link open, and a paused workout stops the live heart rate stream.
2. **Android Foreground Service**: `RingSyncForegroundService` (type `connectedDevice`, minimum-importance notification) runs only while a background sync holds the ring, so Android does not kill the worker's process mid sync.
3. **iOS Background Modes**: Leverages `bluetooth-central` background execution and `BGAppRefreshTask` to process morning sleep syncs automatically.

---

## 3. Data Flow & Synchronization Pipeline

1. **Morning Wakeup Sync**:
   * The phone reconnects to the ring.
   * `syncSleepHistory(today)` is dispatched.
   * The ring transmits packed flash memory buffers over GATT characteristic `0xFEA2`.
   * The driver unpacks bytes into `SleepSession` (Start, End, Wake, Light, Deep, REM intervals).
   * Telemetry is written to the local database.
   * Telemetry is immediately dispatched to **Health Connect** (`SleepSessionRecord`) and **Apple HealthKit** (`HKCategoryTypeIdentifierSleepAnalysis`).

2. **Workout Recording Flow**:
   * The user starts a workout in OpenRing (or triggers sport mode on the ring).
   * Live PPG sampling rate increases (continuous 1Hz heart rate stream).
   * OpenRing calculates active energy and splits.
   * On completion, OpenRing generates an official workout and syncs it to Health Connect/HealthKit.
   * **Kapi** (and any other fitness app on the device) instantly imports the workout as a verified wearable session!

---

## 4. Technology Stack Selection

* **Framework**: Flutter 3.x (Dart 3.x).
* **BLE Engine**: `flutter_blue_plus` (cross-platform, reliable MTU negotiation, stable GATT subscription).
* **State Management**: Riverpod 3 (`flutter_riverpod`).
* **Routing**: `go_router`.
* **Local Persistence**: SQLite via `drift` and `drift_flutter` for fast time-series queries (see `plan.md`, Storage).
* **Health Platforms**:
  * Android: Custom native Kotlin MethodChannel implementing AndroidX Health Connect Client `1.2.0-alpha`.
  * iOS: Custom native Swift MethodChannel or `health` plugin for HealthKit.
* **Charts**: Custom Flutter painters or `fl_chart` for performant 60fps graphs.
