# Features Benchmark: QRing vs OpenRing

Based on real device screenshots and static analysis of `qring.apk` (v3.00.03, package `com.app.cq.ring`).

## 1. What QRing Has Today

| Feature Category | QRing Implementation | Limitations in QRing |
| :--- | :--- | :--- |
| **Daily Activity** | Steps, distance (km), active calories (kcal). | Goal progress ring only. No hourly breakdown charts, pace metrics, or intensity classification. |
| **Sleep Tracking** | Total sleep duration, sleep score (0-100), efficiency score, stages (Wake, Light, Deep). | No REM sleep detection in basic view; hypnogram often fails to sync across dates; sync must be triggered manually in the morning. |
| **Continuous Heart Rate** | Hourly average heart rate, daily min/max range, resting heart rate estimate. | Raw samples are collapsed into broad hourly buckets; cannot export raw PPG samples. |
| **Heart Rate Variability (HRV)** | Spot HRV check in milliseconds (ms), standard classification (Normal/Abnormal). | No overnight rMSSD calculation or baseline recovery trends. |
| **Blood Oxygen (SpO2)** | Percentage reading (90-100%), historical range. | Mostly manual spot-checks or coarse interval checks. |
| **Skin Temperature** | Surface temperature in °C or °F, baseline deviation. | Displayed as a simple gauge; no integration into fever alerts or menstrual cycle analysis. |
| **Stress / Pressure** | Score from 1 to 100 based on HRV intervals. | Proprietary uncalibrated formula with little actionable insight. |
| **Third-Party Sync** | Health Connect & Google Fit toggles in Me tab. | **Write-only**: only writes daily steps, total calories, heart rate, and basic sleep. **Never writes workouts** (`ExerciseSessionRecord`). Drops temperature and HRV. |
| **Device Controls** | Battery percentage, firmware version, gesture control toggle, disconnect/unbind button. | Gesture control is battery-heavy and erratic; no battery discharge rate prediction. |
| **Gimmicks & Bloat** | Remote camera shutter, "Ring Game", AI analysis chatbot, Muslim prayer times. | Non-core features that clutter the UI and introduce bloat and third-party trackers. |

---

## 2. What QRing Lacks (The OpenRing Opportunity)

### 1. Proper Workout Sessions (Health Connect & HealthKit)
* **The Gap in QRing**: Starting a sport activity in QRing does not create an `ExerciseSessionRecord` in Health Connect or an `HKWorkout` in Apple Health. Third-party apps like Kapi, Strava, or Google Fit cannot see the workout.
* **OpenRing Solution**:
  - Full workout recorder: Start Running, Walking, Cycling, Strength, or Freestyle sessions directly.
  - Generates official `ExerciseSessionRecord` (Android) and `HKWorkout` (iOS) with timestamps, active calories, distance, and heart rate samples.
  - Automatically awards verified workout XP in fitness apps like Kapi.

### 2. Multi-Brand Smart Ring Abstraction
* **The Gap in QRing**: Locked strictly to QCWireless/Colmi branded firmware. A user with a Da Fit ring, Nova Ring, or J-Style ring must use a completely different buggy app.
* **OpenRing Solution**:
  - Driver-based plugin architecture. The UI and health engine are completely agnostic of the ring model.
  - Pluggable drivers for Realtek (Colmi R02/R06/R09), JieLi (generic budget rings), and Nordic Semi rings.

### 3. Advanced Recovery & Readiness Metrics
* **The Gap in QRing**: Provides an arbitrary "Activity Score" and "Energy Score" with no scientific basis or explanation.
* **OpenRing Solution**:
  - **Readiness Score (0 to 100)**: Calculated using nocturnal resting heart rate (RHR), nightly HRV (rMSSD baseline deviation), and sleep stage quality.
  - **Sleep Debt & Recovery Target**: Highlights how much sleep debt accumulated over the rolling 7-day window.

### 4. Background Sync & Rock-Solid Connection
* **The Gap in QRing**: Frequent silent disconnects. Users frequently wake up to missing sleep data because the app was killed by Android battery optimization.
* **OpenRing Solution**:
  - Persistent Foreground Service with low-overhead BLE state machine on Android.
  - Periodic background sync handler on iOS (`BGAppRefreshTask` / BLE background mode).
  - Memory buffer recovery: Queries the ring's internal flash memory to backfill up to 7 days of offline telemetry on reconnect.

### 5. Open Data Export & Local Ownership
* **The Gap in QRing**: Data is trapped inside the app's SQLite database. No export options.
* **OpenRing Solution**:
  - One-tap export to CSV, JSON, and standard FIT/GPX files for workouts.
  - Complete local-first database (no account registration required).

### 6. Modern Mobile Experience
* **The Gap in QRing**: Rigid layout, bad translations, dated Android UI components.
* **OpenRing Solution**:
  - Flutter with Material 3 dark design, smooth micro-interactions.
  - Home screen widgets (iOS WidgetKit and Android AppWidget) displaying live ring battery, today's steps, and morning sleep score.
  - Pure English and Portuguese translations natively authored (no machine translations).
