# OpenRing

Open-source, privacy-first, multi-brand Smart Ring companion application for Android and iOS, built with Flutter.

## Mission

Smart ring hardware from budget manufacturers (such as Colmi, generic QCWireless rings, Da Fit rings, and Realsil/JieLi OEM rings) offers premium titanium and alloy designs with solid PPG and accelerometer sensors for $20 to $60 without any mandatory subscription fees.

However, the companion apps bundled with these rings (most notably **QRing**, **Da Fit**, and generic OEM clones) suffer from severe limitations:
- Closed and unreliable Bluetooth sync with frequent disconnections.
- Incomplete and one-way third-party integration (failing to write workouts or detailed sleep stages to Health Connect or Apple Health).
- Cluttered interfaces filled with bloatware (games, remote camera triggers, unoptimized machine translations).
- No export tools (CSV/JSON/FIT), no widgets, and no integration with modern fitness platforms like Strava or Kapi.

**OpenRing** provides a clean, reliable, and extensible cross-platform companion app that bridges any smart ring directly into Apple Health, Android Health Connect, and local storage with full user ownership.

## Project Documentation Index

- [`docs/product-vision.md`](docs/product-vision.md): Target audience, supported rings, and core value propositions.
- [`docs/features-benchmark.md`](docs/features-benchmark.md): Comprehensive feature breakdown of QRing vs OpenRing MVP.
- [`docs/market-analysis.md`](docs/market-analysis.md): Review audit from Google Play Store, Apple App Store, and Reddit user communities.
- [`docs/protocols/realsil-colmi.md`](docs/protocols/realsil-colmi.md): Colmi R09 (Realsil RTL8762) reverse engineering, GATT services, and packet structure.
- [`docs/protocols/multi-ring-architecture.md`](docs/protocols/multi-ring-architecture.md): Driver abstraction layer to support multiple ring brands and chipsets.
- [`docs/architecture.md`](docs/architecture.md): Flutter client architecture, Riverpod 3, BLE state machines, and health platform synchronizers.
- [`docs/reusable-assets-kapi.md`](docs/reusable-assets-kapi.md): Reusable architecture patterns, design tokens, and platform channels from Kapi.
- [`docs/roadmap.md`](docs/roadmap.md): Phased roadmap from protocol spike to v1.0 release.
- [`docs/screenshots/qring/`](docs/screenshots/qring/): Complete screenshot catalogue of QRing running on device.

## Target Platforms

- **Android**: Android 9.0+ (API 28+), Android Health Connect integration.
- **iOS**: iOS 15.0+, Apple HealthKit integration.

## License

MIT
