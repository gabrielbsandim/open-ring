# Product Vision

## 1. Executive Summary

OpenRing is an open, modular, community-driven Smart Ring companion mobile app for Android and iOS. It acts as an open-source alternative to proprietary smart ring apps like QRing, Da Fit Ring, and generic Chinese OEM apps.

The goal is to provide a unified, beautiful, and reliable interface that extracts raw biometrics from smart rings, calculates standardized health metrics (Readiness, Sleep Score, Daily Strain), and synchronizes seamlessly with Apple Health and Android Health Connect.

## 2. Problem Statement

### The Hardware Paradox
The smart ring market has exploded with high quality, low-cost hardware:
- Models such as **Colmi R02, R03, R06, R09, R10, Nova Ring, J-Style 2301, and Lookee Ring** cost between $20 and $60.
- They feature medical-grade optical heart rate (PPG) sensors, red/infrared SpO2 sensors, contact skin temperature sensors, and 3D accelerometers inside titanium or ceramic shells with 3 to 7 days of battery life.
- They have no monthly paywalls or subscription fees.

### The Software Disaster
Despite solid hardware, the software delivered by manufacturers (predominantly **QRing** by Shenzhen Qianhai / QCWireless):
1. **Broken Ecosystem Integration**: QRing only exports basic daily steps and heart rate to Health Connect/Google Fit. It has zero capability to export structured workouts (`ExerciseSessionRecord`), and frequently drops deep sleep stages or skin temperature.
2. **Aggressive Disconnections**: Background BLE synchronization is fragile, often requiring users to toggle Bluetooth, unbind, or re-open the app manually.
3. **Bloat and Gimmicks**: Bundled apps include games, camera shutters, and irrelevant modules, while lacking essential health features like export to CSV, Strava workout sync, or home screen widgets.
4. **Data Lock-in**: Users cannot inspect their raw sensor samples or export their continuous telemetry.

## 3. Core Principles

- **Driver Abstraction (Multi-Brand Support)**: The core app must not know about specific hardware details. Each ring model or chipset family is implemented as a modular `SmartRingDriver`.
- **First-Class Health Connect and HealthKit Sync**: Every piece of data collected by the ring (sleep hypnogram, heart rate samples, HRV, active energy, and manual/ring workouts) must be cleanly published to the operating system's health platform.
- **Privacy First and Local Storage**: Telemetry belongs to the user. All storage is local-first (SQLite through drift). No external cloud servers or accounts required to operate the ring.
- **Modern Clean Design**: Dark-mode first, minimal typography, fluid charts, and zero ads or bloatware.

## 4. Supported Hardware Families (Phased)

1. **Phase 1: Realsil / Realtek RTL8762 Series**
   - Colmi R09 (tested). R02, R03, R06, R10 share the protocol and may work, untested.
   - QRing-compatible rings (QCWireless firmware)
   - Da Fit Ring family
2. **Phase 2: JieLi (JL) Series**
   - Ultra-budget generic smart rings utilizing JieLi AC7012 / AC695X microcontrollers
3. **Phase 3: Nordic Semiconductor (nRF52 Series)**
   - High-end generic rings and custom firmware devices exposing the Nordic UART Service (NUS)
4. **Phase 4: Standard Bluetooth SIG Sensors**
   - Heart Rate Profile (HRS 0x180D) and Battery Service (BAS 0x180F) generic rings
