# OpenRing Privacy Policy

Effective 2026-11-10. Applies to the OpenRing Android app, package
`gbs.openring.app`, version 0.1.0 and later.

## Short version

- OpenRing has no account, no server of its own and no analytics. Nobody behind
  OpenRing receives your health data.
- Your data is stored on your phone, in the app's private storage.
- The app uses the internet for one thing only: checking for and downloading app updates. Your health data never goes over the network.
- Health data leaves your phone only when you send it: to Health Connect, if you allow
  it, or in a file you export and share.

## Who we are

OpenRing is an open-source project published under the MIT license. The source
code, including every place this policy describes, is public at
<https://github.com/gabrielbsandim/open-ring>. Questions about this policy go to
the issue tracker of that repository.

## What the app stores, and why

All of it is kept in a local SQLite database and in the app's private settings
on your phone.

| Data | Where it comes from | Why |
| :--- | :--- | :--- |
| Ring name, Bluetooth address and battery level | The ring, over Bluetooth | To reconnect to your ring and show its battery |
| Steps, distance, active energy, heart rate, SpO2, stress, HRV and sleep stages | The ring, over Bluetooth | To show your days and nights and compute the scores |
| Workouts: start, end, type, pauses, heart rate during the workout | The ring and the phone's clock | To record workouts you start |
| Workout routes: location points during an outdoor workout | The phone's GPS | To draw the route and compute distance, pace and splits |
| Age, height, weight, sex, maximum heart rate, step goal (all optional) | You, on the "About you" screen | Heart rate zones and the calorie estimate |
| Sleep sessions and workouts written by other apps, with the name of the app that wrote them (optional, each off by default) | Health Connect | To show sleep and workouts from another device when you turn that type on |
| Settings: theme, units, sync interval, widget choices, ring alerts, which types go to Health Connect, demo mode | You | To remember your choices |
| A small summary of today's numbers | The app itself | To fill the home screen widgets |

Scores such as readiness and sleep are computed on the phone from this data.
They are estimates for following trends, not a medical diagnosis.

## Permissions

| Permission | Used for |
| :--- | :--- |
| Nearby devices (`BLUETOOTH_SCAN`, declared `neverForLocation`, and `BLUETOOTH_CONNECT`) | Finding and talking to the ring. Scanning is not used to derive your location. |
| `BLUETOOTH`, `BLUETOOTH_ADMIN` (Android 11 and lower only) | The older Bluetooth permissions those versions need. |
| Location (`ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`) | The GPS route of a workout, only while a workout runs. On Android 11 and lower, Android also requires location to scan for Bluetooth devices. The app never asks for background location. |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION` | Keeps the workout recording while the screen is off, with a visible notification. Runs only during a workout. |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE` | Keeps a background sync with the ring from being stopped by Android, with a silent notification. Runs only during a sync. |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Lets the app show Android's dialog asking to exempt it from battery optimization, so the periodic sync can run with the app closed. You can refuse it, or undo it in system settings. |
| Notifications (`POST_NOTIFICATIONS`) | The workout notification, the silent notification during a background sync, a low ring battery and a failed sync. Denying it hides those notifications; sync still runs. |
| Health Connect write: steps, active calories, heart rate, oxygen saturation, heart rate variability, sleep, exercise, exercise route, distance | Sending your ring data and workouts to Health Connect, if you allow each type. |
| Health Connect read: sleep, exercise | Each only if you turn on that type from other apps. Records that OpenRing wrote itself are skipped. |
| `INTERNET` | Checking for and downloading app updates, as described under App updates. |
| `WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`, `ACCESS_NETWORK_STATE` | Added by Android's WorkManager library, which runs the periodic background sync and keeps it scheduled after a restart. The sync job has no network condition; it talks to the ring over Bluetooth only. |

The only part of the app that opens a network connection is the updater
described under App updates.

On phones with Google Play services, the location fixes during a workout come
from Android's fused location provider, which runs inside Google Play services
and follows Google's own terms and your phone's location settings. OpenRing
only receives the fixes; it does not send them anywhere.

## App updates

OpenRing uses Shorebird (<https://shorebird.dev>) to deliver small fixes without
a full store update. When the app starts, it asks Shorebird's server whether a
fix exists for its version. That request carries the app's Shorebird id, its
release version, the installed patch number, the phone's platform and processor
architecture, and a random identifier created on this install, which Shorebird
uses to count active installs. Shorebird's servers also see your IP address, as
any server does, and follow Shorebird's own privacy terms
(<https://shorebird.dev/privacy/>). The request contains no health data, no ring
data and no location.

## What leaves the phone

Apart from the update check above, only what you send, in three ways:

1. **Health Connect.** If you grant write access, OpenRing writes the types
   above to Health Connect on the phone. Other apps you allow in Health Connect
   can then read them. Health Connect is part of Android; its own privacy terms
   apply, and you manage or delete that data in the Health Connect settings.
2. **Export.** You can export CSV, JSON or a workout's GPX file. The file is
   created on the phone and handed to the Android share sheet; you choose where
   it goes.
3. **Phone to phone transfer.** Android's cloud backup is turned off for
   OpenRing, so its data is not copied to your Google account. On Android 12 and
   later, a direct device to device transfer that you start when setting up a
   new phone can still copy the app's data to that phone.

OpenRing sends nothing else to its developers or to any third party: no analytics,
no crash reports, no advertising identifiers, no usage statistics.

## How long data is kept, and how to delete it

Data stays on your phone until you remove it. You can:

- delete a single workout in the app;
- remove all OpenRing data with Android Settings, Apps, OpenRing, Storage,
  Clear storage, or by uninstalling the app;
- delete what OpenRing wrote to Health Connect in the Health Connect settings,
  which also lets you revoke OpenRing's access at any time.

Revoking a permission stops the matching feature; it does not delete data the
app already stored.

## Build-time notice

OpenRing uses the `flutter_blue_plus` Bluetooth library. When a developer
builds the app, that library's build script may send the app's package name,
name and version to its author, as its license allows. This happens on the
build machine, once per build. It never happens on your phone and never
includes any user data.

## Children

OpenRing is not directed at children under 13 and does not knowingly collect
anything from them. The update check above is the only thing it sends off the
device.

## Changes

Changes to this policy are made in the repository, where the history of this
file shows every revision and its date. A change that makes the app send data
off the phone would be stated here before it ships.
