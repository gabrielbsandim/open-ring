# Deep Module Specifications: QRing Architecture Audit

Exhaustive breakdown of every internal module, data model, calculation, threshold, and limitation in QRing, derived from live navigation on physical hardware (`COLMI Ring 2`, Firmware `3.00.03`) and APK decompilation.

---

## 1. Heart Rate Module (`HeartRateDataDetailActivity`)

### UI & Data Display
* **Header Metrics**:
  * **Average**: 24-hour mean BPM (e.g., `88 bpm`).
  * **Minimum**: Daily lowest recorded BPM (e.g., `74 bpm`).
  * **Maximum**: Daily peak recorded BPM (e.g., `103 bpm`).
* **Timestamped Detail**: Displays time of the most recent measurement (e.g., `10:00 PM`).
* **Interactive Control**: Dedicated button `btn_measure` ("Click to start measurement") triggering on-demand live PPG sampling on the ring.
* **Historical Series**:
  * "Last 7 times trends" quick list with "More" pagination for historical logs.
  * Day, Week, Month bar charts showing hourly distribution.

### Heart Rate Zones
QRing divides daily heart rate samples into 5 physiological zones (minutes spent in each):
1. **Warm up**: Lowest aerobic zone (e.g., `10 min`).
2. **Fat burning**: Moderate aerobic zone.
3. **Aerobic endurance**: Cardiovascular training zone.
4. **Anaerobic endurance**: High-intensity threshold zone.
5. **Limit (Peak)**: Maximum effort zone near $HR_{max}$.

### Deficiencies in QRing vs OpenRing Opportunity
* **No Resting Heart Rate (RHR) Isolation**: QRing only displays the absolute minimum BPM. It does not calculate True Nocturnal Resting Heart Rate (lowest 30-minute rolling average during deep sleep), which is the gold standard for cardiovascular recovery.
* **Hardcoded Maximum Heart Rate**: The zone thresholds cannot be customized; they follow a generic formula rather than user-configured lactate threshold or Karvonen formula.
* **Health Connect Gap**: QRing writes daily average heart rate to Health Connect, but **drops high-frequency series samples**, preventing fitness apps (like Kapi) from pricing workouts by intensity zones.

---

## 2. Heart Rate Variability (HRV) Module (`HrvAPPDataDetailActivity`)

### UI & Data Display
* **Header Metrics**:
  * **Average**: Mean HRV in milliseconds (e.g., `42 ms`).
  * **Lowest**: Minimum recorded HRV (e.g., `37 ms`).
  * **Highest**: Peak recorded HRV (e.g., `48 ms`).
* **Scheduled Monitoring Setting**:
  * Toggle: "Scheduled HRV monitoring" (Option: "Monitor every hour").
  * Disclaimer: "When scheduled HRV monitoring is turned on, the device will automatically monitor HRV at regular intervals, providing more accurate data while taking into account power consumption."
* **On-Demand Control**: "Click to start measurement" button.

### HRV Classification Scale
QRing categorizes HRV scores into 4 tiers:
1. **Low**: `< 30 ms` (Sign of fatigue, overtraining, illness, or acute stress).
2. **Normal**: `30 - 60 ms` (Standard baseline autonomic nervous balance).
3. **Good**: `61 - 101 ms` (High parasympathetic tone, well-rested).
4. **Excellent**: `> 101 ms` (Optimal athletic recovery state).

### Deficiencies in QRing vs OpenRing Opportunity
* **Unclear Algorithm (rMSSD vs SDNN)**: QRing reports a raw millisecond value without disclosing whether it uses rMSSD (Root Mean Square of Successive Differences) or SDNN (Standard Deviation of NN intervals).
* **No Baseline Deviations**: Single HRV numbers are meaningless without rolling 14-day personal baselines. OpenRing will compute user-specific baseline bands (7-day rolling median vs 30-day baseline) to signal sympathetic vs parasympathetic dominance.

---

## 3. Blood Oxygen (SpO2) Module (`BloodOxygenDataDetailActivity`)

### UI & Data Display
* **Header Metrics**:
  * **Average**: Daily mean saturation (e.g., `97%`).
  * **Minimum**: Daily nadir (e.g., `96%`).
  * **Maximum**: Daily peak (e.g., `99%`).
* **Timestamped Detail**: Hourly latest read (e.g., `09:00 PM`).
* **On-Demand Control**: "Click to start measurement" (triggers dual red + infrared LED reflective photoplethysmography).

### SpO2 Classification Scale
1. **Hypoxia / Low**: `< 95%` (Triggers potential oxygen depletion warning).
2. **Normal / Moderate**: `95% - 97%` (Typical acceptable range).
3. **Optimal**: `>= 98%` (High atmospheric oxygenation).

### Deficiencies in QRing vs OpenRing Opportunity
* **No Overnight Desaturation Index (ODI)**: SpO2 sensors on smart rings are most valuable for detecting sleep apnea (drops of $\ge 3\%$ or $4\%$ lasting more than 10 seconds). QRing only samples periodically and reports broad averages, completely missing nocturnal hypoxic dips.

---

## 4. Stress / Pressure Module (`RingPressureDetailActivity`)

### UI & Data Display
* **Header Metrics**:
  * **Average Stress**: Scale from 1 to 100 (e.g., `40`).
  * **Minimum**: Daily lowest stress score (e.g., `23`).
  * **Maximum**: Daily peak stress score (e.g., `60`).
* **Interactive Control**: "Click to start measurement" button.

### Stress Classification Scale
QRing partitions stress levels into 4 bands:
1. **Relax**: `0 - 29` (Parasympathetic dominance, calm/sleep state).
2. **Normal**: `30 - 59` (Mild cognitive or physical activity).
3. **Medium**: `60 - 79` (Elevated sympathetic activity, pressure/workload).
4. **High**: `80 - 100` (Acute stress, extreme fatigue, or heavy physical strain).

### Deficiencies in QRing vs OpenRing Opportunity
* **Zero Actionable Feedback**: The app informs the user they are "High" or "Normal", but offers no context, biofeedback breathing exercises, or correlation with sleep debt. OpenRing will incorporate guided Box Breathing and physiological recovery insights.

---

## 5. Body Temperature Module (`TemperatureDataDetailActivity`)

### UI & Data Display
* **Header Metrics**:
  * **Average**: Mean skin temperature (e.g., `36.3 °C`).
  * **Minimum**: Daily nadir (e.g., `35.5 °C`).
  * **Maximum**: Daily peak (e.g., `36.8 °C`).
* **Interactive Control**: "Click to start measurement" button.

### Temperature Classification Scale
1. **Low**: `≤ 35.9 °C`
2. **Normal**: `36.0 °C - 37.2 °C`
3. **Elevated / Fever**: `≥ 37.3 °C`

### Deficiencies in QRing vs OpenRing Opportunity
* **Skin vs Core Confusion**: Smart rings measure *peripheral skin temperature* on the finger, which fluctuates heavily with ambient room temperature and blood vessel constriction. QRing displays it as if it were core oral temperature, confusing users.
* **OpenRing Solution**: OpenRing will follow the Oura/Apple Health standard of displaying **Skin Temperature Baseline Deviation** ($\Delta T = \pm X.X^\circ\text{C}$ relative to the user's 14-day sleeping average), which accurately flags onset of illness or menstrual cycle phases.

---

## 6. Sleep Module (`Sleep` tab & `SleepSummary`)

### UI & Data Display
* **Top Overview**:
  * **Total Sleep Duration**: Split into Hours and Minutes (e.g., `7H 45M`).
  * **Sleep Score**: Overall rating from 0 to 100.
  * **Sleep Efficiency**: Ratio of time asleep vs total time in bed (0-100%).
  * **Sleep Quality Score**: Calculated rating of sleep calmness.
* **Stage Durations (Hypnogram)**:
  * **Wake up**: Total nocturnal awakenings in minutes.
  * **Light sleep**: Light NREM duration.
  * **Deep sleep**: Slow-wave sleep (N3) duration.
* **Sleep Physiology**:
  * **Duration to fall asleep**: Sleep onset latency (SOL) in minutes.
  * **Average sleeping heart rate**: Nocturnal BPM average.
  * **Average sleeping blood oxygen**: Nocturnal SpO2 average.

### Deficiencies in QRing vs OpenRing Opportunity
* **Missing or Obscured REM Sleep**: The standard QRing view collapses REM sleep into Light sleep or drops it entirely.
* **Rigid Single-Window Sleep**: If a user wakes up at 5:00 AM, walks around for 10 minutes, and sleeps until 8:00 AM, QRing often discards the second segment. OpenRing will support multi-segment sleep stitching and daytime nap detection.

---

## 7. Sports Mode & Workout Module (`ExerciseActivity`)

### UI & Data Display
* **Sport Mode Catalog**:
  1. Walk
  2. Run
  3. Cycling
  4. Hiking
  5. Spinning bike
  6. Rope skipping
  7. Swimming
  8. Elliptical machine
  9. Yoga
  10. Basketball
  11. Volleyball
  12. Badminton
* **Active Workout Dashboard**:
  * Elapsed timer (`HH:MM:SS`).
  * Live heart rate reading with intensity color coding.
  * Active calorie burn estimation.
  * GPS track recording (relies on phone GPS).
* **Workout Confirmation**:
  * Safety modal dialog: "Are you sure to end the exercise?" (`Cancel` / `Confirm`).

### Critical Flaw in QRing
* **No OS Export**: When a workout ends, QRing stores it in its internal SQLite table and **does not emit an `ExerciseSessionRecord` or `HKWorkout`**. Third-party aggregators (Google Fit, Apple Health, Kapi) have no visibility into the workout.
* **OpenRing Solution**: Full Health Connect and HealthKit workout writer with active recording method (`RECORDING_METHOD_ACTIVELY_RECORDED`), allowing Kapi to immediately award verified wearable XP.

---

## 8. Gesture Control Module (`RingGestureGuideActivity`)

The Colmi R09 ring contains a capacitive touch sensor on the outer surface that registers double-taps:
* **Music Mode**: Tap twice to advance to the next audio track.
* **Short Video Mode**: Tap twice to scroll down to the next short video (TikTok / Instagram Reels / YouTube Shorts).
* **E-Book Mode**: Tap twice to turn to the next page.
* **Couple Interaction**: Double-tap to send a notification vibration to a linked partner's ring ("Space of Love").
* **Close**: Deactivates touch processing to conserve ring battery.

---

## 9. AI Health Analysis Module (`AiHealthAnalysisActivity`)

### Features
* Analyzes daily health telemetry against user anthropometrics (Age, Height, Weight).
* Generates an aggregated "Health Score" (0-100%).
* Outputs narrative paragraphs summarizing Steps, Sleep, Heart Rate, Calories, Stress, SpO2, and HRV.
* Provides health and lifestyle recommendations.

### Privacy Risk in QRing vs OpenRing Solution
* QRing sends the user's complete biometric profile to unencrypted OEM cloud APIs in China to generate this report.
* OpenRing will implement an **On-Device Local Health Engine** (rule-based expert system or local on-device small model) that runs entirely offline with zero data leaving the phone.

---

## 10. Device & System Settings

* **Hardware Remote Shutdown**: Sends BLE command `0x02` to turn off the smart ring (requires placing on charging cradle to power back on).
* **Hardware Factory Reset**: Resets internal flash memory and bonding keys.
* **Unit Format**: Metric (`km`, `kg`, `°C`) vs Imperial (`miles`, `lbs`, `°F`).
* **Low Battery Prompt**: User-configurable threshold alert.
