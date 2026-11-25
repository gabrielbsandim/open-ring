# OpenRing Privacy Policy

Effective 2026-11-25. Applies to the OpenRing Android app, package
`gbs.openring.app`, version 0.1.0 and later.

## Short version

- OpenRing has no account, no server of its own and no analytics. Nobody behind
  OpenRing receives your health data.
- Your data is stored on your phone, in the app's private storage.
- The app uses the internet for two things: checking for and downloading app updates and, only with AI analysis on, reaching the AI service you chose, which receives only what you approved: a summary of your data, a Goals review decision or a meal photo. Your health data goes over the network in no other way.
- Health data leaves your phone only when you send it: to Health Connect, if you allow it, in a file you export and share, or to the AI service you chose, after you agree.

## Who we are

OpenRing is an open-source project published under the MIT license. The source
code, including every place this policy describes, is public at
<https://github.com/gabrielbsandim/open-ring>. Questions about this policy go to
the issue tracker of that repository.

## What the app stores, and why

All of it is kept in a local SQLite database, in the app's private photo folder
and in the app's private settings on your phone; the AI service key is kept in
Android's secure storage instead.

| Data | Where it comes from | Why |
| :--- | :--- | :--- |
| Ring name, Bluetooth address and battery level | The ring, over Bluetooth | To reconnect to your ring and show its battery |
| Steps, distance, active energy, heart rate, SpO2, stress, HRV and sleep stages | The ring, over Bluetooth | To show your days and nights and compute the scores; with the Energy module on, also the estimate of your day's energy; with the Effort module on, also your training load; with the Food module on, also the gap before sleep and your meal comparisons |
| Workouts: start, end, type, pauses, heart rate during the workout | The ring and the phone's clock | To record workouts you start; with the Energy module on, also the estimate of your day's energy; with the Effort module on, also your training load |
| Effort ratings: the number from 1 to 10 you give a workout (optional, Effort module) | You | To estimate the load of that workout |
| Workout routes: location points during an outdoor workout | The phone's GPS | To draw the route, compute distance, pace and splits and, with the Open Score module on, estimate your fitness |
| Age, height, weight, sex, maximum heart rate, step goal (all optional) | You, on the "About you" screen; the step goal also when you accept a raise in a Goals review, or put the raised goal back when you end a goal | Heart rate zones, the calorie estimate and the scores of the Open Score module; with the Energy module on, also the estimate of your day's energy; with the Effort module on, also your training load |
| Sleep sessions and workouts written by other apps, with the name of the app that wrote them (optional, each off by default) | Health Connect | To show sleep and workouts from another device when you turn that type on; with the Energy module on, also the estimate of your day's energy; with the Effort module on, also your training load; with the Food module on, also the gap before sleep and your meal comparisons |
| Weigh-ins: weight and, if you add them, body fat and waist (optional, Body module) | You | To show your weight trend and, with the Open Score module on, to score your body measures; with the Energy module on, also the estimate of your day's energy |
| Day tags: the days you set aside as sick, travel or rest (optional, Open Score module) | You | To leave those days out of your averages; with the Open Score and Effort modules both on, a sick day also makes the coach card say recover |
| Goals: the goal you choose with its start and reference weights, the weekly plan and its reviews, your check-in answers, and the screening result and date with the pregnancy answer (optional, Goals module) | You | To build the weekly plan, review it each Monday and keep its safety checks; the screening keeps the overall result, not each answer |
| Meals: capture time, meal kind, tags you tap and optional photos resized to 1024 px with camera and location details removed (optional, Food module) | You | To show your days, eating window, Plate pattern and personal comparisons with your ring nights |
| AI analysis: the service address, the model, the detail level and your other AI settings, your consents with their dates, usage counts and the last 60 readings, each with the summary that was sent (optional, AI analysis module) | You and the AI service you chose | To ask the service you chose for a reading, show the readings and what was sent, and ask for your consent again when something changes; each time a reading is saved, readings older than 30 days lose the sent summary and the raw answer |
| Your AI service key, if the service needs one (optional, AI analysis module) | You | Encrypted on this phone, outside the database, exports and backups, and sent only to the address you set, in the request header |
| Meal photo analyses: the service and model, the model's tag suggestions and its answer and, for photos analyzed with Weekly energy on, the items in household measures (optional, Food and AI analysis modules) | The AI service you chose | To show the suggestions you confirm, reuse an answer instead of sending the photo again and, with Weekly energy on, show one range a week |
| Settings: theme, units, sync interval, widget choices, ring alerts, which types go to Health Connect, demo mode, which modules are on, the weekly goal, heart rate on the lock screen, the ring drop alert in a workout | You | To remember your choices |
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
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE` | Keeps a background sync with the ring from being stopped by Android, with a silent notification, and keeps a workout running while the screen is off, with a notification that shows its time and heart rate while it runs, says so while it is paused, and lets you pause or end it. Runs only during a sync or a workout. |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Lets the app show Android's dialog asking to exempt it from battery optimization, so the periodic sync can run with the app closed. You can refuse it, or undo it in system settings. |
| Notifications (`POST_NOTIFICATIONS`) | The workout notification, the alert when the ring drops during a workout, a notice that a workout was saved or not saved, the silent notification during a background sync, a low ring battery and a failed sync. Denying it hides those notifications; sync still runs. |
| Health Connect write: steps, active calories, heart rate, oxygen saturation, heart rate variability, sleep, exercise, exercise route, distance | Sending your ring data and workouts to Health Connect, if you allow each type. |
| Health Connect read: sleep, exercise | Each only if you turn on that type from other apps. Records that OpenRing wrote itself are skipped. With no ring paired, it also asks to read them in the background, so the periodic sync can import them with the app closed. |
| Health Connect read in the background (`READ_HEALTH_DATA_IN_BACKGROUND`) | Asked only with no ring paired and a read on. Lets the periodic sync import those types with the app closed. Refusing it keeps the imports for when the app is open. |
| `INTERNET` | Checking for and downloading app updates, as described under App updates, and, only with the AI analysis module on, the requests you start to the AI service you chose, as described under AI analysis. |
| `WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`, `ACCESS_NETWORK_STATE` | Added by Android's WorkManager library, which runs the periodic background sync and keeps it scheduled after a restart. The sync job has no network condition; it talks to the ring over Bluetooth only. |

No camera or photo library permission is asked: when the Food module is on and
you attach photos, Android opens the system camera for a single photo or the
system photo picker (up to 20 at once) and hands back only the images you
choose.

Two parts of the app open network connections: the updater described under App
updates and, only with the AI analysis module on, the AI client. The AI client
connects only to the address you set, refuses http to a public address, does not
follow redirects and refuses a certificate that fails validation. No other code
opens a connection.

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

## AI analysis (optional)

The AI analysis module is off by default. OpenRing has no AI of its own: you
choose a service, set its address and model and, if the service needs one, add
your key. Any cost is between you and that service.

With the AI analysis module on, the app sends a summary of your data, or a Goals review decision to reword, to the AI service you chose, only when you tap to send and after you agree to sending to that address. You can open the summary before you send it. Connection tests, photo tests and the model list send your key and a fixed text or a generated image, never your data.

Never sent: GPS routes or any location, the ring's name or address, raw samples, phone identifiers, your Goals screening answers, sleep and workouts read from other apps.

With the Food module also on, a meal photo goes to that service only after you choose it with Analyze and give a separate consent, at most 768 px and without location or camera data. A photo still waiting is sent the next time the app runs.

The service receives what you send, your key if you set one and your phone's IP address, and may keep them under its own terms. OpenRing cannot delete anything there.

A service on your own network may use http, which is not encrypted. The app allows http only for private and local network addresses, and says so when you agree to send.

OpenRing gets quick fixes through Shorebird. Whoever can publish a fix could change the code that reads the key, so publishing goes through review in the public repository.

The key is stored with Android's secure storage, outside the database and every
export. Android cloud backup is off for OpenRing, and the phone to phone
transfer described below leaves the key out. A consent covers one address, one
detail level, the kinds of data it named and the date of this policy; a change
to any of them asks again. Readings, meal photo analyses, the AI settings and
the key never go into an export. In demo mode nothing is sent.

## What leaves the phone

Apart from the update check above, only what you send, in four ways:

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
4. **AI analysis.** With the module on, what you send to the AI service you
   chose, as described under AI analysis.

OpenRing sends nothing else to its developers or to any third party: no analytics,
no crash reports, no advertising identifiers, no usage statistics. The AI service
is one you choose and pay for yourself; OpenRing's developers receive nothing from
it.

## How long data is kept, and how to delete it

Data stays on your phone until you remove it. You can:

- delete a single workout in the app;
- delete a meal, old meal photos or all Food data in the app;
- remove the AI key, settings, readings and meal photo analyses with Remove key and readings in the AI analysis module, or withdraw a consent;
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
anything from them. The update check and the sends you start with the AI analysis
module are the only things it sends off the device.

## Changes

Changes to this policy are made in the repository, where the history of this
file shows every revision and its date. A change that makes the app send data
off the phone would be stated here before it ships.
