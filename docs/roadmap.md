# Roadmap

The phased plan, decisions log, and closure criteria live in [`plan.md`](plan.md).

## Current status

- [x] Foundation (Phases 0-6): protocol parser (`ring_protocol`), `ColmiDriver` (`ring_driver`), scoring formulas (`metrics`), Drift persistence (schema v21), Health Connect outbox and native writers (`health_connect_writer`), ring and workout alerts (`ring_notifications`), workouts with GPS, CSV/JSON/GPX export, and 11 locales.
- [x] Epic #15 modular expansion on `develop`: Modules, Body, Day Score, Level, Overall, Energy, Effort, Goals, Workout Notifications (`N2-N8`), Food, AI Analysis, Trajectory, Widgets v2, and core docs.
- [x] Play Store descriptions (11 locales) and static landing page sync.
- [ ] iOS client & HealthKit (deferred until a Mac is available).
- [ ] Held / hardware-dependent items: notification merge slice N9 and disconnect alert issue `#235` (await real-phone validation), plus owner-owed real-device checks (O12 LAN `http`, O13 Play Data safety & Health Connect declarations, Release APK & Glance widget checks).
