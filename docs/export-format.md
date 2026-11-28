# Export format

What OpenRing writes when you export your data. Everything is produced on the
phone from the local drift database; nothing is uploaded. The writers live in
`apps/mobile/lib/features/export/domain` and are pure Dart, so the format below
is exactly what the golden tests in `test/features/export` pin.

Formats: **CSV** (one file per kind, or one file per workout from its summary
screen), **JSON** (one document), and **GPX 1.1** for a single workout route.

## Common rules

- **Range**: an export covers `[from, to)`. A record belongs to the range when
  its start time is inside it: `time` for samples, `start` for activity buckets
  and workouts, and the **session start** for sleep, so a night is never cut in
  half at a range edge.
- **Timestamps**: ISO 8601 with the UTC offset that was in force on the phone
  when the record was captured, for example `2026-10-25T02:30:00+02:00`. The
  offset is never `Z` in CSV and JSON; UTC is written `+00:00`. Seconds are
  always present; milliseconds appear only when they are not zero
  (`2026-12-31T23:30:00.250+01:00`).
- **Daylight saving time**: every row carries its own offset, so the repeated
  hour of a fall back is unambiguous (`02:30:00+02:00`, then `02:30:00+01:00`)
  and a night that crosses a spring forward keeps the offset of each stage.
  Sort by instant, not by the text of the wall clock time. Sleep from other
  apps is the exception: every stage of a night is written with the offset of
  its session, so after a clock change inside the night the instant is right
  and the wall clock time is the one of the old offset.
- **Order**: rows are sorted by time, then by device id (workouts: by start,
  then by internal id; workouts and sleep from other apps: by start, then by
  record id).
- **Numbers**: integers as integers. Decimals are rounded to 2 places with
  trailing zeros removed (`31.5`, `402`, `6012.35`).
- **Missing values**: an empty CSV field, `null` in JSON.
- **Device id**: the ring's Bluetooth id as stored at pairing (`R09_C0FE` in the
  examples). Workouts recorded without a ring have no device id.

## Kinds and columns

Column order is stable: new columns are only ever appended, and a change that
removes or renames one bumps the JSON `schema_version`. The JSON object for a
record uses exactly the same keys in the same order.

| Kind | File / JSON key | Columns, in order |
| :--- | :--- | :--- |
| Sleep | `sleep` | `session_start`, `start`, `end`, `device_id`, `stage`, `duration_s` |
| Heart rate | `heart_rate` | `time`, `device_id`, `bpm` |
| HRV | `hrv` | `time`, `device_id`, `hrv_ms` |
| SpO2 | `spo2` | `time`, `device_id`, `spo2_percent` |
| Stress | `stress` | `time`, `device_id`, `stress_level` |
| Steps and activity | `activity` | `start`, `end`, `device_id`, `steps`, `distance_m`, `active_kcal` |
| Workouts | `workouts` | `start`, `end`, `client_id`, `device_id`, `activity_type`, `duration_s`, `distance_m`, `active_kcal`, `effort_rating` |
| Weigh-ins | `weigh_ins` | `time`, `weight_kg`, `body_fat_percent`, `waist_cm`, `source` |
| Day tags | `day_tags` | `date`, `tag` |
| Workouts from other apps | `imported_workouts` | `start`, `end`, `record_id`, `source`, `activity_type`, `duration_s`, `effort_rating` |
| Sleep from other apps | `imported_sleep` | `session_start`, `start`, `end`, `record_id`, `source`, `stage`, `duration_s` |

Weigh-ins are offered only while the Body module is on. With the module off the
kind is not listed and is never written, even when weigh-ins are stored. Hide
numbers changes the screens only: an export always carries the values.

Day tags are offered only while the Open Score module is on. `date` is a local
calendar date, `YYYY-MM-DD`, with no time and no offset; `tag` is `sick`,
`travel` or `rest`. A tag is exported when its date lies between the local
dates the two ends of the range fall on, both included.

Workouts from other apps are the workouts read from Health Connect. The kind is
always offered and carries every stored row whose start is in the range: also
with the reading switched off, and also a workout the app hides because it
overlaps one you recorded. The app reads no distance, energy or device id for
these workouts, so the kind has none. The time the row was imported is stored
and is not exported.

Sleep from other apps is the nights read from Health Connect, one row per
stage, like the sleep kind. It is always offered and carries every stage of a
night whose start is in the range: also with the reading switched off, and also
a night the app does not show because another source comes first. A stage has
no offset of its own, so every timestamp of a night carries the offset of its
session. The end of the session and the time the row was imported are stored
and are not exported, and a night stored with no stages has no row.

### Units and meaning

| Column | Unit | Notes |
| :--- | :--- | :--- |
| `session_start` | timestamp | Start of the night the stage belongs to, with the session's own offset. Rows with the same value are one night. For sleep from other apps, rows with the same `record_id` are one night. |
| `start`, `end` | timestamp | `end` is exclusive. For activity it is `start` plus the bucket length. Every exported workout has an `end`: one still running, or left open when the app was closed, is not exported until it is saved. |
| `stage` | text | One of `light`, `deep`, `rem`, `awake`. |
| `duration_s` | seconds | `end - start`, whole seconds. Empty when `end` is empty. |
| `bpm` | beats per minute | As logged by the ring. |
| `hrv_ms` | milliseconds | The ring's own HRV value. Its definition is unpublished (see `metrics.md` section 4); it is exported as stored, not converted to rMSSD or SDNN. |
| `spo2_percent` | percent | Integer percent, as stored. |
| `stress_level` | ring scale | The ring's 1 to 100 stress value. Not a medical measure. |
| `steps` | steps | Steps in the bucket. |
| `distance_m` | meters | Integer for activity buckets, decimal for workouts. |
| `active_kcal` | kilocalories | Active energy only, not total energy. |
| `effort_rating` | 1 to 10 | The effort you gave the workout, 10 the hardest. Empty when it has none. |
| `client_id` | text | The workout's stable id, the same one used for Health Connect and HealthKit. |
| `activity_type` | text | The workout type as recorded by the app. For a workout from another app, the type the app gave it when it was read. |
| `record_id` | text | The id Health Connect gives the record: the workout, or the night a stage belongs to. |
| `weight_kg` | kilograms | The weigh-in as logged, never the trend weight. Always kilograms, whatever unit the app shows. |
| `body_fat_percent` | percent | Empty when the weigh-in has none. |
| `waist_cm` | centimeters | Empty when the weigh-in has none. |
| `source` | text | `manual` for a weigh-in typed in the app, `demo` for demo data. Weigh-ins have no device id. For a workout or a night from another app, the package name of the app that wrote it, as stored. |

Values are exported as stored: implausible readings that the screens hide (a
zero heart rate, an SpO2 under the plausible floor) are kept, so an export is
a faithful copy of the database, not of the charts.

`effort_rating` is the same: it is always in the workouts kind, with the
Effort module on or off, and a stored value outside 1 to 10 is exported as it
is. The rating given to a workout read from another app is in the
`imported_workouts` kind, under the same rule.

## CSV

- [RFC 4180](https://www.rfc-editor.org/rfc/rfc4180): fields separated by `,`,
  records ended by CRLF (`\r\n`), including the last one.
- A field is quoted only when it contains `,`, `"`, CR or LF; inner quotes are
  doubled (`"run, ""easy"""`).
- UTF-8 without a byte order mark.
- The first row is always the header, so a kind with no records in the range is
  a file with only the header row.
- One kind exported: a single file `openring-<kind>-<yyyyMMdd-HHmmss>.csv`.
- Several kinds: one archive `openring-csv-<yyyyMMdd-HHmmss>.zip` holding
  `<kind>.csv` for each kind, in the order of the table above.

### Single workout

A workout exports from its summary screen as one
`openring-workout-<yyyyMMdd-HHmmss>.csv`, with the common CSV rules above and
these columns, in order:

| Column | Unit | Notes |
| :--- | :--- | :--- |
| `time` | timestamp | The sample's instant with the workout's recorded UTC offset. |
| `bpm` | beats per minute | The heart rate sample at this instant, else the heart rate stored on the track point. Empty otherwise. |
| `latitude`, `longitude` | decimal degrees | WGS84, up to 7 decimals. Empty when no track point has this instant. |
| `elevation_m` | meters | Empty when the phone gave no altitude. |
| `accuracy_m` | meters | Horizontal accuracy of the fix. Empty when the phone gave none. |

There is one row per distinct instant, sorted by time. Heart rate and GPS are
joined only when their instants are equal; nothing is interpolated or held over.
Workouts store no steps, so the file has no steps column. A workout with neither
heart rate nor route offers no CSV.

## JSON

One file `openring-<yyyyMMdd-HHmmss>.json`, UTF-8. One record per line, so the
file stays readable and diffable even when large.

```json
{
  "schema_version": 1,
  "exported_at": "2026-11-10T12:00:00-03:00",
  "range": {"from":"2026-10-25T00:00:00+02:00","to":"2026-10-26T00:00:00+01:00"},
  "device": {"id":"R09_C0FE","name":"R09_C0FE","model":"R09","firmware":null},
  "heart_rate": [
    {"time":"2026-10-25T02:30:00+02:00","device_id":"R09_C0FE","bpm":58},
    {"time":"2026-10-25T02:30:00+01:00","device_id":"R09_C0FE","bpm":57}
  ],
  "hrv": []
}
```

| Key | Type | Meaning |
| :--- | :--- | :--- |
| `schema_version` | integer | `1`. Bumped when a key is removed, renamed or changes meaning. Added keys do not bump it. |
| `exported_at` | timestamp | When the export ran, with the phone's offset at that moment. |
| `range` | object | `from` and `to` of the request; `to` is exclusive. |
| `device` | object or `null` | The most recently paired ring: `id`, `name`, `model`, `firmware` (the last two may be `null`). `null` when no ring was ever paired. Records still carry their own `device_id`. |
| `<kind>` | array | One key per requested kind, in the order of the kinds table, each an array of record objects with the columns above as keys. A requested kind with no records is `[]`; a kind that was not requested is absent. |

## GPX

A workout route exports as one `openring-route-<yyyyMMdd-HHmmss>.gpx`,
[GPX 1.1](https://www.topografix.com/GPX/1/1/), UTF-8.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="OpenRing"
     xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
     xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"
     xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd http://www.garmin.com/xmlschemas/TrackPointExtension/v1 http://www.garmin.com/xmlschemas/TrackPointExtensionv1.xsd">
  <metadata>
    <name>Morning run</name>
    <time>2026-11-10T15:00:00Z</time>
  </metadata>
  <trk>
    <name>Morning run</name>
    <type>running</type>
    <trkseg>
      <trkpt lat="-23.55052" lon="-46.63331">
        <ele>760</ele>
        <time>2026-11-10T09:00:00Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>128</gpxtpx:hr>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
    </trkseg>
  </trk>
</gpx>
```

- Element order follows the GPX 1.1 schema sequences: `metadata` then `trk`;
  inside `trk`, `name`, `type`, then one `trkseg` per continuous segment (a
  pause starts a new segment); inside `trkpt`, `ele`, `time`, `extensions`.
- `metadata/time` is when the file was written. Track point times are UTC with
  `Z`, the form every GPX consumer accepts.
- `lat` and `lon` are WGS84 decimal degrees, up to 7 decimals (about 1 cm),
  `lat` in [-90, 90] and `lon` in [-180, 180). `ele` is meters, up to 2
  decimals, and is left out when the phone gave no altitude.
- Heart rate uses the Garmin TrackPointExtension v1 `hr` element, in beats per
  minute. Strava, Garmin Connect and most GPX tools read it. It is left out for
  a point with no reading or a value outside 1 to 255 (the schema's
  `unsignedByte`).
- Points inside a segment are sorted by time. Empty segments are dropped.
- A saved workout is exported from its summary screen. Its route points are
  split at every stored pause (a point at or after a pause's end opens a new
  `trkseg`), and each point takes the heart rate sample at or before it, if
  that sample is at most 10 s older (`liveSampleMaxHold`, `metrics.md`
  section 10). `trk/type` is the workout's activity type.
- `name` and `type` are left out when the workout has none; text is XML
  escaped.

## Where files go

Exports are written into a fresh folder under the app's temporary directory
(`openring-export-*`), streamed page by page from drift, and the returned paths
are handed to the system share sheet. The OS may clear that directory at any
time after sharing; OpenRing does not keep a copy.

## Backup file

Settings, Data, Back up data writes `open-ring-backup-YYYYMMDD-HHMMSS.zip` and
hands it to the share sheet. Unlike the exports above it is meant to be read
back by OpenRing, not by other tools:

- `manifest.json`: `{"app": "open_ring", "format": 1, "schemaVersion": <n>,
  "createdAtUtc": "<ISO 8601>"}`. `schemaVersion` is the drift schema of the
  database inside.
- `open_ring.sqlite`: a copy of the whole database made with `VACUUM INTO`, AI
  readings, meal photo analyses and Trajectory projections included.
- `meal_photos/<name>`: every saved meal photo.

Restore from backup, in the same group, accepts a file only when the manifest
names this app and format 1, its schema is not newer than the app's, the
database passes `PRAGMA integrity_check` and every photo matches its CRC32. It
copies the file aside, stops background sync and restarts the app, which swaps
the database and the photos in before opening anything. The previous ones are
kept as `open_ring.sqlite.pre-restore` and `meal_photos.pre-restore` until the
next restore. Preferences kept outside the database (modules, units, theme,
alerts, the AI settings, consents and key) are not in the file.

## Never exported

The AI analysis and Trajectory modules keep their data out of every CSV, JSON
and GPX file, and adding them changed no format, so the JSON `schema_version`
stays 1. Only the backup file above carries the tables below, never the key or
the AI settings:

- the AI service key, which lives in the phone's secure storage, outside the
  database;
- the AI settings and consents (service address, model, detail level, prices,
  limits and the consent dates);
- AI readings (`ai_reports`), with the summaries that were sent and the raw
  answers;
- meal photo analyses (`meal_analyses`) and their items (`meal_items`);
- Trajectory projections (`trajectory_projections`), the 4 week weight bands
  stored each Monday. Delete Trajectory data, on its module screen, removes
  them and nothing else.

Tests pin it: `test/features/ai/infrastructure/ai_export_exclusion_test.dart`,
`test/features/food/infrastructure/meal_analysis_export_exclusion_test.dart`
and `test/features/trajectory/trajectory_projection_export_exclusion_test.dart`.
