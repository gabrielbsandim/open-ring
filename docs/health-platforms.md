# Health platforms: writes and opt-in reads

How ring data leaves drift and lands in Health Connect (Android) and HealthKit
(iOS), and how sleep other apps wrote is read back, opt-in, with a per-type
source priority (see "The read side" below).

Plugin: `health` 13.3.2 (carp-dk, current stable, the version Kapi uses). Every
claim about it below was checked in its source under
`~/.pub-cache/hosted/pub.dev/health-13.3.2` (`HealthDataWriter.kt`,
`HealthDataWriter.swift`, `HealthDataOperations.*`, `health_plugin.dart`).

## Rule from plan.md

Start with the plugin. Drop to a native channel only for a record type the
plugin cannot write, or cannot write idempotently, and write the gap down first.
Two native write channels exist, for Health Connect sleep and heart rate
(below); the other gaps are the backlog. They live, with the exercise read
channel, in the local Flutter plugin `packages/health_connect_writer`
(`HealthConnectWriterPlugin`), so every engine registers them through
`GeneratedPluginRegistrant`, the WorkManager engine included. Only the
channels that need an Activity (permissions, Health Connect settings) stay in
`MainActivity`.

## What the plugin can write, per type

"Idempotent" means a re-send updates the record instead of adding a second one.

| Record | Health Connect | HealthKit | Gap | What OpenRing does |
| :--- | :--- | :--- | :--- | :--- |
| Steps | `StepsRecord` via `writeHealthData`, with `clientRecordId` and `clientRecordVersion`. Idempotent. | `HKQuantitySample` step count. Metadata is only `HKMetadataKeyWasUserEntered`. Not idempotent. | iOS: no `HKMetadataKeySyncIdentifier` or `HKMetadataKeySyncVersion`. | Android upserts by client id. iOS deletes OpenRing's own samples of the type in the batch range, then writes. |
| Active energy | `ActiveCaloriesBurnedRecord`, client id and version. Idempotent. | Active energy quantity sample. Not idempotent. | iOS sync identifier, as above. | Same as steps. |
| Heart rate series | `HeartRateRecord`, but one record per sample: `createRecord` wraps a single `Sample`. Idempotent per sample. | One quantity sample per reading. Not idempotent. | Android: no multi-sample series record, so a night is hundreds of records instead of one. Closed by the app's own channel. iOS sync identifier. | Android: the plugin channel `gbs.openring.app/health_connect_heart_rate` (`HealthConnectHeartRateChannel.kt` in `health_connect_writer`) deletes OpenRing's own `HeartRateRecord`s in the batch range, which also clears the per-sample records older builds wrote, then inserts one series record per fixed UTC hour (see "Heart rate series" below), client id `heartRateSeries`, the row version, `TYPE_RING`, automatically recorded. iOS: one sample per reading after delete in range, unchanged. |
| Sleep with stages | `SLEEP_LIGHT`, `SLEEP_DEEP`, `SLEEP_REM`, `SLEEP_AWAKE` each write a separate `SleepSessionRecord` holding one stage; `SLEEP_SESSION` writes a session with no stages. Cannot write one session with a stage list. | `SLEEP_IN_BED` plus `asleepCore`, `asleepDeep`, `asleepREM`, `awake` category samples (iOS 16+). This is HealthKit's own model. Not idempotent. | Android: **cannot write the record type correctly**; a night shows as one session per stage. Closed by the app's own channel. iOS sync identifier. | Android: the plugin channel `gbs.openring.app/health_connect_sleep` (`HealthConnectSleepChannel.kt` in `health_connect_writer`, connect-client 1.2.0-alpha02, the `health` plugin's version) deletes OpenRing's own `SleepSessionRecord`s in the batch range, which also clears the per-stage sessions older builds wrote, then inserts one session per night with its stage list, client id `sleepSession` and the row version, recorded as `TYPE_RING`. iOS: in-bed span plus stage samples, after delete in range. REM is written on both. |
| SpO2 | `OxygenSaturationRecord` via `writeHealthData`, client id and version. Idempotent. `writeBloodOxygen` drops the client id, so it is not used. | Oxygen saturation sample; `HKUnit.percent()` takes a fraction, so 97 % is sent as 0.97. Not idempotent. | iOS sync identifier. | Android upsert. iOS delete in range, then write. |
| HRV | `HeartRateVariabilityRmssdRecord`, client id and version, value range 1 to 200 ms. Idempotent. | Only `HEART_RATE_VARIABILITY_SDNN` exists. Not idempotent. | Semantics: the R09's HRV definition is unpublished (`metrics.md` section 4), and each platform has one HRV type, rMSSD on Android and SDNN on iOS. The value goes to the closest type on each. iOS sync identifier. | Values outside 1 to 200 ms are not sent (Health Connect rejects the whole insert). |
| Workout session | `writeWorkoutDataUUID` writes an `ExerciseSessionRecord`, plus `DistanceRecord` and `TotalCaloriesBurnedRecord` when given, actively recorded: the app passes `RecordingMethod.manual`, which health 13.3.2 maps to `ACTIVELY_RECORDED` (its constant table is inverted, so the version is pinned). No client id or version on any of them. Not idempotent. | `HKWorkout` with `metadata: nil`. Not idempotent. `writeWorkoutDataUUID` calls `result` twice on success (uuid, then `""`). | Both: no sync id for workouts. Android: energy can only go in as total calories, not active. iOS: the double reply must be checked on a phone. | Delete OpenRing's own workouts (and, on Android, distance) in the session window, then write. Energy is left off on Android (active energy already arrives from the activity buckets) and sent as workout energy on iOS. |
| Workout HR series | Through the heart rate channel: one `HeartRateRecord` spanning the session with every sample, client id `workoutHeartRateSeries`, actively recorded. Health Connect links by time, there is no association. Idempotent. | Heart rate samples saved on their own: the plugin has no `HKWorkoutBuilder` or `add(_:to:)`, so they are not associated with the `HKWorkout`. | iOS: **cannot associate HR with the workout.** Apple Health may not show HR on the workout. Second candidate for a native channel. | Android: a workout carrying HR deletes OpenRing's heart rate records in its window, then writes its series; a workout without HR leaves the ring's records there alone. iOS: samples in the window. Inside a finished workout that has its own HR series, ring-log HR is not written, so the two sources never fight over the same window. |
| Workout GPS route | `ExerciseRoute` set through `finishWorkoutRoute` (`updateRecords` on the session). Needs `WRITE_EXERCISE_ROUTE`. | `HKWorkoutRouteBuilder` finished against the saved workout. | None found in source; idempotent through the workout replace. | Points outside the session are dropped (Health Connect rejects them). |
| Stress | No type. | No type. | Not applicable. | The outbox row is marked `notApplicable` and dequeued. |

Cross-cutting findings:

- On Android every write catches its exception and returns `false`, a
  `SecurityException` included. The adapter therefore checks write permission
  with `hasPermissions(..., WRITE)` before a batch, and treats a later `false`
  as transient.
- The plugin sends `RecordingMethod.automatic` with `Device.TYPE_UNKNOWN`; the
  Dart side never passes a device type, so Health Connect cannot show "ring".
  Workouts are the exception to the recording method: they go in as actively
  recorded on Health Connect, since readers drop automatic sessions, and the
  upgrade to schema 10 writes the last 7 days of them again on Android.
- Health Connect `deleteRecords` by time range for interval records is not
  documented as overlap or containment. The batch planner never cuts a session
  at a range edge, so either reading is safe; confirm on a phone.
- The iOS delete is `predicateForSamples(..., .strictStartDate)` filtered to
  OpenRing's own source: it matches samples that start in the range. Ranges end
  1 ms after the last record so a reading at the edge is included.

### Workout types

`PluginHealthWriter.workoutActivityType` maps the stored activity type:

| OpenRing | Health Connect | HealthKit |
| :--- | :--- | :--- |
| running, walking, hiking, elliptical, yoga | `RUNNING`, `WALKING`, `HIKING`, `ELLIPTICAL`, `YOGA` | the same names |
| cycling | `BIKING` | `BIKING` (`.cycling`) |
| strength training | `STRENGTH_TRAINING` | `TRADITIONAL_STRENGTH_TRAINING` |
| treadmill | `RUNNING_TREADMILL` | `RUNNING`: the plugin rejects `RUNNING_TREADMILL` on iOS and cannot set `HKMetadataKeyIndoorWorkout` |
| stationary bike | `BIKING`: the plugin lists `BIKING_STATIONARY` for Android, but its native writer has no entry for it and refuses the write | `BIKING`, without the indoor flag |
| other | `OTHER` (`EXERCISE_TYPE_OTHER_WORKOUT`) | `OTHER` |

Deleting a workout in OpenRing enqueues nothing. A session already written
stays in Health Connect or Apple Health until the user removes it there; an
outbox row not yet processed loads no workout for its window and writes nothing.

## Idempotency

- **Client record id**: `openring:<device>:<type>:<startUtcMs>`, where `type`
  is the written record (`steps`, `activeEnergy`, `heartRate` and
  `workoutHeartRate` (one sample, HealthKit only), `heartRateSeries` and
  `workoutHeartRateSeries` (Health Connect series), `spo2`, `hrv`,
  `sleepSession`, `sleepStage` (HealthKit only), `workout`) and `device` is
  the ring id, or `phone` for a phone-led workout. A series is keyed by its
  start.
- **Client record version**: the enqueue time (UTC ms) of the outbox row that
  carries the write. A record that changes is re-enqueued later, so its version
  only grows; a retry of the same row repeats the same version, which Health
  Connect treats as a no-op. No schema column is needed for it.
- **Replace contract** (`HealthWriter.replace`): after a batch, the platform
  holds exactly the batch entries among OpenRing records of that kind that start
  in `[from, to)`. Health Connect gets it from client ids (plus a range delete
  for sleep and workouts); HealthKit from delete-in-range then write.
- **Ranges** tile the outbox row's span, widened to the records loaded for it,
  so a record drift no longer holds is cleared too. Excluded windows (workouts
  that own HR) are never covered.

### Heart rate series

Health Connect gets heart rate as `HeartRateRecord` series, not one record per
sample:

- **Ring log**: one record per fixed UTC hour, from its first to its last
  sample. The bucket is a property of the samples, not of the outbox row, so
  the same samples always form the same records and keep the same client ids.
  An hour is also split at a workout window that owns HR, and the cap below
  splits it in theory (the ring logs 6 samples an hour at its 10 minute
  interval). Why an hour: Google suggests small series records (a minute in
  its guide) so reads stay cheap, but at the R09's interval a minute or 15
  minutes holds one or two samples, which is the problem being fixed; a day
  would be rewritten in full on every sync; an hour matches the hourly
  background sync and keeps a re-send to 6 samples.
- **Whole hours**: the record source widens a heart rate row to whole hours
  before loading, so a row that covers 15:20 to 16:40 rebuilds the 15:00 and
  16:00 records from all their samples instead of overwriting the 15:00 record
  with half of them. Batch ranges then start and end on hour edges, workout
  windows or series starts, so no earlier series straddles a range edge and
  the range delete is safe under either reading of `deleteRecords`.
- **Workout**: one record from the session start to its end with every sample,
  client id from the session start.
- **Limits**: an insert carries at most 1000 records (Health Connect's
  documented limit) and at most 10,000 samples; a series holds at most 10,000
  samples (`maxSeriesSamples`), a workout past that is split into several
  records that together cover the session. Health Connect documents no sample
  cap per series; 10,000 is about 2 h 45 min at one sample a second and keeps
  a record to a few hundred KB.
- **Retries**: a batch deletes OpenRing's own heart rate records in its range,
  then inserts with the row's version, so a retried row (same version) and a
  re-enqueued one (higher version) both leave exactly one record per series.
  Health Connect only replaces a record on a strictly higher version, which
  the delete makes moot.
- **Background**: the WorkManager engine registers the channel like any
  plugin, so the worker writes heart rate, workout and sleep rows itself.
  Health Connect needs no background permission to write;
  `READ_HEALTH_DATA_IN_BACKGROUND` only gates reads.
- **Older builds**: their per-sample records are cleared only when a row that
  covers them is sent again; rows already done are not re-sent, except the
  Android workouts of the last 7 days that the upgrade to schema 10 re-queues.

### A sleep session whose start moved

The ring can revise a night and move its start. `SleepDao.replaceNight` drops
every older session that overlaps the new one, and its write summary also
covers the dropped spans. The outbox row for that
sync therefore spans both the old and the new night, and the replace clears the
old session (and its stages) before writing the new one. The old client id is
never left behind. Tested in `process_health_outbox_test.dart`, "a night whose
start moved replaces the old session".

## Outbox processor

`ProcessHealthOutbox` (`features/health_sync/application`):

- Reads due rows (`pending`, and `next_attempt_at_utc_ms` null or past) in id
  order, loads their records from drift, writes them in batches of 200, then
  marks the row `done`.
- A failure increments `attempts`, stores `last_error` and
  `last_attempt_at_utc_ms`, and schedules the next try 1 min after the first
  failure, doubling up to 6 h. After 8 attempts the row is `dead` and never
  retried.
- Permission denied for a kind leaves its rows `pending` with no attempt
  counted, and the report carries the denied kinds. A missing Health Connect
  app stops the run the same way. `healthSyncProvider` exposes both as
  `HealthSyncState.denied`, `unavailable` and `blocked` for the UI.
- Holds its own `sync_locks` row, `health_outbox`, so it never waits for or
  blocks the ring sync, and two engines never write the same row at once.
- Runs after every successful foreground sync (`RingSyncController`, not
  awaited), after every successful background sync (`BackgroundSyncRunner`,
  errors swallowed so the worker still reports a completed sync), and on
  `healthSyncProvider.notifier.process()`. `requestAccess()` asks for write
  access to every writable kind and processes on a grant.

Schema v3 adds `status`, `last_attempt_at_utc_ms` and `next_attempt_at_utc_ms`
to `health_outbox`; rows already completed migrate to `done`.

## Platform setup

- Android: `health.WRITE_*` for steps, active calories, heart rate, oxygen
  saturation, HRV, sleep, exercise, exercise route and distance (distance
  because the plugin writes a `DistanceRecord` with each workout), plus
  `health.READ_SLEEP` and `health.READ_EXERCISE`, each asked only when that
  type of reading is turned on. `queries` for
  the Health Connect package and the rationale intent, the
  `ACTION_SHOW_PERMISSIONS_RATIONALE` filter on `MainActivity`, and the
  `ViewPermissionUsageActivity` alias for Android 14+. `MainActivity` extends
  `FlutterFragmentActivity` because the plugin requests permissions through
  `registerForActivityResult`. `minSdk` 28 is above the plugin's 26 and matches
  Health Connect's Android 9 floor.
- iOS: `Runner.entitlements` with `com.apple.developer.healthkit` (wired through
  `CODE_SIGN_ENTITLEMENTS` for Debug, Release and Profile), and
  `NSHealthShareUsageDescription` plus `NSHealthUpdateUsageDescription`. The
  deployment target 15.0 matches the plugin's floor. The HealthKit capability
  must also be enabled on the App ID in the developer portal.

## The read side

Plan.md v1 item 8. Sleep and workouts are built. The heart rate priority group
in the prototype is not built: no doc defines how heart rate from another
source is used (which screens, how it meets the ring's series), so there is no
rule to order it by.

- **Opt-in per type.** `health_reads` (schema v6) holds one row per kind with
  `enabled` (default off) and `last_read_at_utc_ms`. Turning sleep on in Data
  sources asks for `READ_SLEEP` only (`HealthReader.requestReadAccess`, through
  `requestAuthorization([SLEEP_SESSION], [READ])`); a declined request keeps it
  off and offers to open Health Connect. Turning it off stops reading and drops
  imported nights from every screen; the rows stay until "Delete all data".
- **Reading.** `PluginHealthReader` reads `SLEEP_SESSION` and then the stage
  types through `getHealthDataFromTypes`. Each stage point carries the uuid of
  its session, so stages are grouped under their session. Light, deep and REM
  map one to one; `SLEEP_ASLEEP` (no stage) counts as light; awake and awake in
  bed are awake; out of bed and unknown are dropped. A session without any sleep
  stage is skipped. The offset stored is the phone's offset at the session start,
  because the plugin does not pass the record's zone offset.
- **Own records excluded.** Points whose data origin is `gbs.openring.app` are
  dropped before storage (`isExternalSource`), so OpenRing never reads back what
  it wrote.
- **Storage.** `imported_sleep_sessions` (platform record id, source package,
  span, offset) and `imported_sleep_stages`, keyed by record id. Imported nights
  never enter `health_outbox`, so they are never written back.
- **Window.** The first read covers 30 days, later reads start 2 days before the
  last read so a night the other app revised is read again. Nights are upserted
  by record id. On Android the plugin turns any read error (permission
  included) into an empty list, so its answer cannot prove a night is gone.
  Reconciliation therefore uses the `ids` method of `HealthConnectSleepChannel`,
  which reads `SleepSessionRecord` ids for the same window and reports errors:
  a stored night wholly inside the window whose id it no longer returns is
  deleted with its stages. A night straddling an edge of the window is kept.
  When the id read fails, nothing is deleted. The `ids` read is part of the
  sleep import, so in the worker it only runs once background reads are
  granted (see "When").
- **When.** After every foreground ring sync attempt, successful or not (the
  ring being on the charger is the night another source fills), from
  `RingSyncController`, and when sleep reading is turned on. In the background
  worker `BackgroundSyncRunner` runs the same `ImportExternalSleep` with the
  plugin, which the WorkManager engine registers (it is a pub plugin). Health
  Connect only lets an app read in the background with
  `READ_HEALTH_DATA_IN_BACKGROUND`, which OpenRing does not ask for yet, so there
  the reader reports `deferred` and the next foreground sync imports.
- **HealthKit.** Not built: the reader reports `unavailable` on iOS and the
  switch is disabled. HealthKit sleep has no session grouping, so it needs its
  own night builder.

### Workouts

- **Opt-in.** Off by default, its own `health_reads` row (`kind = 'workout'`).
  Turning it on asks for `READ_EXERCISE` only (`requestAuthorization([WORKOUT],
  [READ])`).
- **Why not the plugin's read.** The plugin's `WORKOUT` read also reads every
  app's `DistanceRecord`, `TotalCaloriesBurnedRecord` and `StepsRecord` in the
  session window and sums them. Without `READ_DISTANCE`,
  `READ_TOTAL_CALORIES_BURNED` and `READ_STEPS` that read throws and the plugin
  returns an empty list; with them, the totals add up records of several apps,
  OpenRing's own distance included, which breaks the never-summed rule. So
  sessions are read by `HealthConnectExerciseChannel` (in the
  `health_connect_writer` plugin, `gbs.openring.app/health_connect_exercise`), which reads
  `ExerciseSessionRecord` only, behind the `ExerciseSessionSource` port of
  `PluginHealthReader`. The channel maps Health Connect exercise types to
  OpenRing's ten workout types; any other type shows as Other.
- **What is read.** Record id, source package, type, start, end and start zone
  offset (the phone's offset at the start when the record has none). No
  distance, energy, heart rate or route.
- **Route and heart rate are not read.** Another app's route needs
  `READ_EXERCISE_ROUTES` or a per-session consent intent, neither of which the
  plugin offers; heart rate needs `READ_HEART_RATE`, and heart rate from other
  sources has no defined use. An imported workout therefore has no route, so it
  has no GPX export.
- **Own records excluded** by `isExternalSource`, as for sleep. Workouts with no
  duration are dropped.
- **Storage.** `imported_workouts` (schema v7), keyed by record id, upserted,
  never in `health_outbox`. The exercise channel reports its errors, so after a
  read a stored workout wholly inside the window whose id it no longer returns
  is deleted, as for sleep. A failed read fails the import, so nothing is
  deleted.
- **Window and when.** Same as sleep: 30 days first, then 2 days before the last
  read; after every foreground sync attempt and when the switch is turned on.
  In the background worker the reader reports `deferred` without
  `READ_HEALTH_DATA_IN_BACKGROUND`, so the exercise channel is not called there.
- **Shown.** In Activity's recent workouts, mixed with OpenRing's own and
  labelled "From <app>". Tapping one opens a read-only summary (type, time,
  duration, the app that recorded it): no delete, no GPX, no Health status.
  The home screen widget's last workout stays OpenRing's own.

### Source priority

`source_priorities` (`metric = 'sleep'`) holds the order. The ring is
`openring:ring` and leads by default; each new source an import sees joins at
the end. `resolveSourcePriority` keeps the stored order for sources that still
have nights. `readSleepNights` (`features/sleep/application`) is the one
function every sleep reader uses (Sleep screen, sleep score, Today and its
readiness through `sleepWeekProvider`, Heart, Trends, the widget snapshot): it
stitches each source on its own and, for each date, takes the night of the first
source in the order that has one. A night is never merged across sources, so a
ring and a watch that both cover 23:18 to 06:42 count once.

Workouts have their own order (`metric = 'workout'`), with `openring:ring`
standing for OpenRing's own workouts and leading by default.
`selectWorkouts` (`features/workout/application`) walks the sources in that
order and keeps a workout unless a workout from a higher source overlaps it in
time; workouts of one source never hide each other and two workouts are never
merged. A copy of an OpenRing run that Google Fit wrote is hidden by default
this way.

## What to check on a real phone (Phase 4 exit)

1. Android: grant access (the UI entry point is a later task; until then call
   `healthSyncProvider.notifier.requestAccess()` from a debug hook) and confirm
   the Health Connect sheet lists exactly the nine write permissions.
2. Tapping the privacy link in Health Connect opens the OpenRing privacy
   screen (rationale intent and alias), during onboarding too, and closing it
   leaves for Today or back to onboarding.
3. After a sync, Health Connect shows steps, active calories, HR, SpO2, HRV and
   last night with REM. Sync again: counts stay the same (no duplicates).
   Heart rate shows one entry per hour with a bpm range, not one per sample.
4. A night shows as one session with its stages, and the per-stage sessions an
   older build wrote are gone after the next send. Revise a night (or wait for
   the ring to) and confirm a single session remains.
5. Record a workout with GPS: Google Fit shows the session, the HR series in its
   window and the route. Health Connect lists the workout's heart rate as one
   entry spanning the session. Re-send it (kill the app mid-write) and confirm
   one session and one heart rate entry.
6. iOS: the HealthKit sheet appears with write types only; Apple Health shows
   the night with REM and the workout. Check whether the workout detail shows
   HR (expected gap) and that `writeWorkoutDataUUID`'s double reply does not
   crash.
7. Reads: with another app that writes sleep (Fitbit, Samsung Health), turn on
   sleep in Data sources. The Health Connect sheet asks for sleep read only.
   The app shows up with its nights, a night the ring missed appears on the
   Sleep screen, and moving the app above the ring switches a shared night to
   that app. Confirm OpenRing's own sessions never appear as a source.
   Then turn on workouts: the sheet asks for exercise read only, a watch
   workout appears in Activity with its app name and opens read-only, and an
   OpenRing workout another app copied stays hidden.
8. Background: let the Android worker run with the screen off and confirm
   writes land, sleep, heart rate and workouts included (the worker's engine
   registers the `health_connect_writer` channels, so nothing waits for a
   foreground send);
   on iOS, writes while the phone is locked fail (protected data) and must
   succeed on a later run.
