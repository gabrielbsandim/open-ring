# Roadmap

The phased plan, decisions log, and closure criteria live in [`plan.md`](plan.md).

## Current status

- [x] Foundation (Phases 0-6): protocol parser (`ring_protocol`), `ColmiDriver` (`ring_driver`), scoring formulas (`metrics`), Drift persistence (schema v21), Health Connect outbox and native writers (`health_connect_writer`), ring and workout alerts (`ring_notifications`), workouts with GPS, CSV/JSON/GPX export, and 11 locales.
- [x] Epic #15 modular expansion on `develop`: Modules, Body, Day Score, Level, Overall, Energy, Effort, Goals, Workout Notifications (`N2-N8`), Food, AI Analysis, Trajectory, Widgets v2, and core docs.
- [x] Release `v0.7.0` (`0.7.0+7`): real-phone validation on Android 15 + COLMI R09 (`RMX3741`, Release APK, Drift v21, WorkManager, Glance v2 `widgetCategory` + dynamic `ThisWeekWidgetReceiver`, O12 LAN `http`, Health Connect rationale intent, `WorkoutForegroundService`), floating 4s `SnackBar` fix (`#425`), PR `#424` merged to `main` (`f05cce8`), Shorebird build & GitHub Release `v0.7.0` published, and AAB + `mapping.txt` + 11 `whatsnew` notes uploaded to Play `production`.
- [x] Play Console updates saved (queued in Managed Publishing): all 11 store descriptions + titles/short descriptions, O13 Data safety form, and foreground service / Health declarations verified against Play Console.
- [ ] Play Console final review submission: click "Enviar alteracoes para revisao" in *Visao geral da publicacao* (`Publishing overview`) so the saved 11 store descriptions, O13 Data safety form, and `v0.7.0 (7)` release enter review together, then monitor Play review.
- [x] `it-IT` and `ja-JP` store descriptions aligned with the app's UI labels (`Sforzo`, `Inizia allenamento`, `ボディ`, `エフォート`, `推移`, `ワークアウトを開始`); Play Console still holds the earlier text until it is re-pasted or uploaded.
- [ ] Post-release check: visual verification of the floating 4s `SnackBar` on physical device once `v0.7.0` installs.
- [ ] Held / hardware-dependent items: notification merge slice N9 and disconnect alert issue `#235` (await targeted live-workout phone verification), plus remaining long-workout / launcher edge checks (screen-off checkpoint recovery, live disconnect vibration, S/M/L widget resizing in launcher).
- [ ] iOS client & HealthKit (deferred until a Mac is available, including O14 LAN `http` ATS).
