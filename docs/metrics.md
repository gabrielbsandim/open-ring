# Metrics

Every number OpenRing derives from ring samples or from what the user logs,
with its formula, constants, inputs, minimum data rule and sources. The code lives in `packages/metrics`
(pure Dart, no Flutter). The constants below are named constants or parameter
defaults there, except the stress bands, `220 - age` and the accepted input
ranges, which are literals in the function that applies them, so this file and
the code can be checked against each other.

**Estimate, not a medical diagnosis.** This label applies to every metric in
this file and is shown next to every score in the app. A consumer ring
estimates sleep stages, HRV, SpO2 and stress from a wrist or finger PPG signal;
none of it is validated against polysomnography, ECG or a medical oximeter.

Each constant is marked **sourced** when a published reference supports the
value, or **our choice** when it is a product decision. Where a sourced idea is
turned into a number we picked, both are said.

## Conventions

- Instants are UTC. Every sleep span carries the UTC offset the phone had when
  the span was captured (`SleepSpan.utcOffset`). Calendar dates are computed
  from that offset, never from the host time zone, so results do not change
  with the zone the phone or the test machine is in.
- A calendar date is a `LocalDate` (year, month, day). Day arithmetic runs on
  UTC midnights, so a DST change never makes a day 23 or 25 hours long.
- A zero from the ring means "slot not measured" and is dropped before any
  formula runs. This holds for heart rate, HRV, stress and SpO2.
- Scores return their inputs. A score is a list of contributions, each with the
  input value, a subscore from 0 to 1, the weight in points and the points it
  earned. The score is the rounded sum of the points, clamped to 0..100.
- When a required input is missing a score returns `InsufficientData` with the
  missing factors, never a number.
- Missing data never throws. A setting out of range does: a non positive
  window, slot, goal or sample interval, a minimum count below 1 (below 2, or
  above the window, for baseline days), a negative `maxGap`, an empty
  `SleepNight`, a non positive value compared against a log scale baseline, or
  a `to` that is not after `from`. These throw `ArgumentError`.

The shared shape of every subscore is a linear ramp:

```
ramp(x, zeroAt, fullAt) = clamp((x - zeroAt) / (fullAt - zeroAt), 0, 1)
```

It runs downhill when `zeroAt > fullAt` (for example latency, where less is
better).

## 1. Sleep night

Function: `stitchSleep(spans, maxGap)`, then `SleepNight` getters.

Inputs: sleep spans (start, end, stage light, deep, REM or awake, UTC offset)
from the ring's sleep log, any order.

### Stitching

1. Drop spans with zero or negative length. Sort by start; for equal starts
   the longer span comes first, then the order light, deep, REM, awake, so the
   result does not depend on input order.
2. Walk the spans. If a span starts inside the previous one, clip its start to
   the previous end; if it ends inside, drop it. Time is never counted twice.
3. If the gap from the previous end to the next start is at most `maxGap`,
   the span joins the same night. A longer gap starts a new night.
4. Drop nights with no asleep time.

| Constant | Value | Basis |
| :--- | :--- | :--- |
| `defaultMaxStitchGap` | 60 min | **our choice**. The ring closes a sleep record when it thinks you woke; a bathroom trip or a ring that slipped can split one night in two. An hour is long enough to rejoin those and short enough to keep apart an evening nap that ends more than an hour before bed; a nap that ends within the hour joins the night. |

Stage codes 0 (no data) and 1 (error) in a ring record produce no span, so they
arrive here as gaps. A gap inside a night is reported in `gaps` and counts as
awake time in bed.
This is what the Sleep screen shows as "two stretches joined into one night:
you woke at 04:12 for 9 min".

### Night measures

| Measure | Formula |
| :--- | :--- |
| Time in bed | last span end minus first span start |
| Total asleep | sum of light, deep and REM span durations |
| Awake | time in bed minus total asleep (includes gaps) |
| Efficiency | total asleep / time in bed |
| Sleep onset | start of the first light, deep or REM span |
| Latency | sleep onset minus night start; null when there is no sleep |
| Stage share (light, deep, REM) | stage time / total asleep |
| Awake share | awake / time in bed |
| Awakenings | maximal runs of awake spans and gaps between sleep onset and the last asleep span; a gap and the awake span next to it are one awakening, flagged `bridgesGap` |
| Wake after sleep onset | sum of awakening durations |

Stage shares use total asleep as the denominator, the convention of
polysomnography reports. Awake time before onset is latency, awake time after
the last asleep span is the final wake; neither counts as an awakening.

Latency only exists if the ring logged awake time before sleep. If the first
logged span is already light sleep the latency is zero; it is an estimate of
what the ring saw, not of when you went to bed.

### Assigning a night to a date

A night belongs to the local calendar date of its end, read with the UTC
offset of its last span: `LocalDate.fromInstant(end, lastSpan.utcOffset)`.
**Our choice**: it matches how people talk about a night ("last night's sleep"
is shown on the morning you wake). Consequences, all covered by tests:

- A night in Kiritimati (UTC+14) that ends at 06:00 local on 10 November is
  dated 10 November although it ends on 9 November in UTC.
- A day sleep in Honolulu (UTC-10) that ends at 15:00 local is dated that day
  although UTC has already moved to the next date.
- Across a DST change durations are real elapsed time (a fall back night shows
  one more hour than the wall clock difference) and the date comes from the
  offset in force at wake.
- A wake at exactly 00:00 local belongs to the new date.

When several nights share a date, `mainNightByDate` keeps the one with the
most asleep time (on a tie, the first passed); the others are naps and count
for nothing. There is no other nap rule, which has three known limits:

- A gap over 60 min splits a night. If both parts end on the same date only the
  part with more sleep counts and the other part's sleep is lost; if the first
  part ends before local midnight it is dated the previous day.
- A nap alone on its date is that date's night, and is scored when it reaches
  `minimumScoredSleep`.
- A nap with more sleep than the night on the same date replaces it.

Minimum data: one asleep span. No spans gives no night.

## 2. Sleep score

Function: `sleepScore(night, goal, remMeasured)`. Factors and weights:

| Factor | Input | Subscore | Weight | Basis |
| :--- | :--- | :--- | :--- | :--- |
| Duration | total asleep, minutes | `ramp(asleep, 0, goal)` | 35 | goal default `defaultSleepGoal` = 8 h. **Sourced**: 7 to 9 h is recommended for adults (Hirshkowitz 2015; Watson 2015 sets 7 h as the floor). 8 h is **our choice** at the middle of that range; the user can change it. No extra credit above the goal. |
| Efficiency | percent | `ramp(eff, 65, 85)` | 20 | **Sourced**: 85 percent or more indicates good sleep quality at every adult age (Ohayon 2017). The zero point `efficiencyZeroPercent` = 65 is **our choice**. |
| Latency | minutes | `ramp(lat, 60, 30)` | 10 | **Sourced**: up to 30 min indicates good sleep quality (Ohayon 2017). The zero point `latencyZeroMinutes` = 60 is **our choice**. |
| Deep | percent of asleep | `ramp(deep, 0, 15)` | 20 | Slow wave sleep share in healthy adults falls with age and sits around 15 to 25 percent in young and middle aged adults (Ohayon 2004). The target `deepTargetPercent` = 15 is **our choice** at the low end so older users are not penalised by age alone. |
| REM | percent of asleep | `ramp(rem, 0, 20)` | 15 | REM is roughly 20 to 25 percent of sleep in healthy adults (Ohayon 2004). The target `remTargetPercent` = 20 is **our choice**. |

The weights are **our choice**. Duration carries the most because it is the
input with the strongest evidence and the one a ring measures best; the stage
inputs together carry 35 because ring stage labels are model estimates.

REM is optional. The R09 may never emit stage code 4 (REM, see
`protocols/realsil-colmi.md`). When the app knows the ring cannot report REM it
passes `remMeasured: false`; the REM factor is dropped and the remaining
weights are scaled to sum to 100 (each weight times 100 / 85). When the ring
can report REM and a night has none, REM scores zero.

The app knows from the data, per ring: `RemReporting.observe(nights,
nightsWithRem)`. A night here is a ring sleep session with asleep time, dated
by its local end, for the paired ring only.

| Constant | Value | Basis |
| :--- | :--- | :--- |
| `remAbsentAfterNights` | 7 nights | **our choice**, the same count as `baselineMinDays`. One night with any REM span means the ring reports REM, for good. No REM across 7 nights means it does not: a healthy adult spends about a fifth of every night in REM (Ohayon 2004), so a ring that can label it has had a week of chances. Below 7 nights the answer is unknown and REM stays in the score. |

When the answer is "does not", the Sleep screen also drops the REM lane from
the hypnogram and REM from the stage legend, unless the night shown holds REM
time.

```
score = round( sum over factors of weight_i * subscore_i )
```

Minimum data, `minimumScoredSleep`: at least 60 min asleep. Below that, or with
no night, the result is `InsufficientData([duration])`. **Our choice**: a
shorter detection is more likely a nap or a false positive than a night.

## 3. Resting heart rate

Function: `restingHeartRate(samples, window, minSamples)`, run on the heart
rate samples of one night. The function does not choose them: the app passes
the samples with `night.start <= at < night.end`, and does the same for the
HRV readings of section 4.

```
RHR = min over every window of length `window` of mean(bpm in window)
```

Windows start at each sample and end before `start + window`. A window with
fewer than `minSamples` valid samples is skipped.

| Constant | Value | Basis |
| :--- | :--- | :--- |
| `window` (parameter default) | 30 min | **our choice**. The lowest sustained heart rate of the night; a mean over half an hour rejects a single low artefact. |
| `minSamples` (parameter default) | 3 | **our choice**. The heart rate log reports its slot length. The app sets the ring to 10 min on every sync (`plan.md` decisions); measured on an R09 one hour after a 10 min write, the log kept 5 min slots with every second one filled, and empty slots are dropped, so a 30 min window holds 3 samples and a missed slot loses that window. At a 30 min slot no window can reach 3 samples and there is no value. |

Minimum data: one window with 3 valid samples, else null (no value that night).

### Resting heart rate baseline

Function: `restingHeartRateBaseline(nightlyValues, today)`, the generic
baseline below on the bpm scale with a spread floor of
`restingHeartRateMinSpread` = 1 bpm.

A resting heart rate above the personal norm is a common marker of
incomplete recovery, illness or heat (Buchheit 2014). Comparing with the
user's own history, not a population table, follows the same source.

## 4. HRV

Nightly value, `nightlyHrv(readings, minReadings)`: the arithmetic mean of the
valid HRV readings of the night, in milliseconds. The ring logs one value per
30 min slot (Gadgetbridge `historicalHRV`, see `protocols/realsil-colmi.md`);
its exact HRV definition is not published, so the app labels it "HRV", not
rMSSD.

| Constant | Value | Basis |
| :--- | :--- | :--- |
| `nightlyHrvMinReadings` | 3 | **our choice**. 90 min of measured slots. |

### HRV baseline

Function: `hrvBaseline(nightlyValues, today)`, the generic baseline on the
natural log scale with a spread floor of `hrvMinLogSpread` = 0.05.

**Sourced**: HRV is analysed as ln(RMSSD) because its distribution is skewed,
and judged against the athlete's own rolling baseline and its variation
(Plews 2013; Buchheit 2014). The typical value shown to the user is the
geometric mean, `exp(mean of ln values)`.

## 5. Personal baseline (shared by RHR and HRV)

Function: `personalBaseline(history, today, scale, minSpread, windowDays,
minDays)`.

Inputs: one value per local date (the last value wins for a repeated date).

```
window  = dates d with 1 <= today - d <= windowDays   (today excluded)
x_i     = value_i            (linear scale)
x_i     = ln(value_i)        (log scale, values <= 0 dropped)
                             (non finite values dropped on both scales)
mean    = average of x_i
sd      = max( sample standard deviation of x_i, minSpread )
z       = (x_today - mean) / sd
delta   = today - typical          percent = (today / typical - 1) * 100
typical = mean (linear) or exp(mean) (log)
```

| Constant | Value | Basis |
| :--- | :--- | :--- |
| `baselineWindowDays` | 28 days | **our choice**, inside the 14 to 60 day range we considered. Four weeks holds every weekday four times, so a weekly routine does not bias it; one bad week moves it by a quarter at most; it still follows a change in training or season within a month. Shorter windows (14 days) let a week of illness drag the baseline toward the illness; longer ones (60 days) hide real adaptation. |
| `baselineMinDays` | 7 nights | **our choice**. Plews 2014 found that a weekly ln RMSSD mean needs at least three to five valid measurements to stay valid; we ask for seven nights inside the window before showing a baseline at all. Until then the result is `BaselineBuilding(daysCollected, daysNeeded)` and the app shows "n of 7 nights". |
| `hrvMinLogSpread` | 0.05 | **our choice**. A spread floor of about 5 percent, so a very stable history does not turn a trivial change into a large z score. |
| `restingHeartRateMinSpread` | 1 bpm | **our choice**, same reason. |

Today's value is the single night, not a 7 day rolling mean as in Plews 2013.
**Our choice**: readiness is a morning number and should react to last night.

The z score expresses "today versus baseline" in units of the user's own
night to night variation. Plews 2013 use the smallest worthwhile change (0.5
times the coefficient of variation) for the same purpose; the z score is the
same idea on a continuous scale.

## 6. Activity load

Function: `activityLoad(dailyActiveKilocalories, today)`.

```
acute   = mean of daily active kcal over days 1..7 before today
chronic = mean over days 1..28 before today (the acute week is included)
ratio   = acute / chronic
```

**Sourced** idea: the acute to chronic workload ratio, with the coupled
rolling 7 and 28 day windows, and the observation that ratios above about 1.5
follow a sharp rise in load (Gabbett 2016). The model is contested: the ratio
has statistical and conceptual problems (Impellizzeri 2020). OpenRing uses it
only as a small, optional readiness input and says so on screen.

| Constant | Value | Basis |
| :--- | :--- | :--- |
| `acuteLoadDays`, `chronicLoadDays` | 7, 28 | **sourced** (Gabbett 2016) |
| `minAcuteLoadDays` | 4 of 7 | **our choice**, more than half of the week |
| `minChronicLoadDays` | 14 of 28 | **our choice**, half of the month |

Today is excluded because in the morning it holds almost no activity. Days the
ring was not worn have no value and are left out of the means; a worn day with
no activity is a real zero. Negative or non finite values are dropped; the
last value wins for a repeated date.
Minimum data: the two day counts above and a chronic mean above zero, else
null.

## 7. Readiness

Function: `readiness(sleepScore, hrv, restingHeartRate, activityLoad)`.

| Factor | Input | Subscore | Weight |
| :--- | :--- | :--- | :--- |
| Sleep | last night's sleep score | `score / 100` | 35 |
| HRV | z of last night vs HRV baseline | `ramp(z, -3, +1)` | 30 |
| Resting HR | z of last night vs RHR baseline | `ramp(z, +3, -1)` | 20 |
| Activity load | acute to chronic ratio | `ramp(ratio, 2.0, 1.3)` | 15 |

```
readiness = round( sum over factors of weight_i * subscore_i )
```

All weights and ramp end points are **our choice**:

- `hrvZeroZ` = -3, `hrvFullZ` = +1: a night at baseline (z = 0) earns 0.75, so
  an ordinary day lands around 75 to 85 and the score has room to say "better
  than usual". One SD below baseline earns 0.5.
- `restingHeartRateZeroZ` = +3, `restingHeartRateFullZ` = -1: the mirror image,
  since a higher resting HR is worse.
- `loadFullRatio` = 1.3, `loadZeroRatio` = 2.0: full credit up to 1.3, the
  upper end of the range Gabbett 2016 describes as lower risk; zero at 2.0.
  A low ratio (a rest week) is not penalised.
- Weights: sleep and HRV carry most because they move most from night to
  night; activity load carries least because its evidence is weakest.

Minimum data: a sleep score, an HRV deviation and a resting HR deviation are
required. If any is missing the result is `InsufficientData` listing them
(for example during the first 7 nights, while the baselines are building).
Activity load is optional: when it is missing its weight is shared by the
other three (each times 100 / 85).

This is not the score of any commercial ring. The factors follow the
benchmark in `features-benchmark.md` (RHR, HRV deviation from baseline, sleep
quality) and the published monitoring practice cited above; the arithmetic is
ours and is published here so it can be argued with.

Verdict word shown with the score, function `readinessBand(score)`:

| Band | Score |
| :--- | :--- |
| optimal | 85 to 100 |
| good | 70 to 84 |
| fair | 55 to 69 |
| low | 0 to 54 |

The cut points are **our choice**. An ordinary day lands around 75 to 85, so
`good` covers it and `optimal` needs a day better than usual. One standard
deviation below baseline on HRV and resting HR falls in `fair`. The word
describes the score against your own baseline and is not health advice.

## 8. Stress daily summary

Function: `stressDaySummary(readings, slot, minReadings)`, run on the stress
readings of one local date.

The ring reports a stress level from 1 to 100 every 30 min (Gadgetbridge
`historicalStress`). Its formula is not published, so OpenRing does not
reinterpret it; it summarises it.

```
valid  = readings with 1 <= level <= 100
mean, min, max over valid
time in band = count of valid readings in the band * slot
```

| Band | Levels |
| :--- | :--- |
| rest | 1 to 25 |
| low | 26 to 50 |
| medium | 51 to 75 |
| high | 76 to 100 |

| Constant | Value | Basis |
| :--- | :--- | :--- |
| bands | quartiles | **our choice**. Garmin's consumer stress level uses the same 0 to 25, 26 to 50, 51 to 75, 76 to 100 split; the ring's scale is unrelated and uncalibrated, so the bands are display bands with no clinical meaning. |
| `stressSlot` | 30 min | **sourced** from the protocol (slot size of the stress log) |
| `stressMinReadings` | 3 | **our choice**, 90 min of measured slots |

Minimum data: 3 valid readings, else null.

## 9. SpO2 nightly summary

Function: `spo2NightSummary(readings, from, to, sampleInterval, minReadings)`,
with `from` and `to` set to the night's start and end.

```
valid       = readings with from <= at < to and 70 <= percent <= 100
min, mean   over valid
time below  = count(valid < 90) * sampleInterval
share below = count(valid < 90) / count(valid)
```

| Constant | Value | Basis |
| :--- | :--- | :--- |
| `spo2LowThreshold` | 90 percent | **sourced**: time below 90 percent saturation (T90) is a standard nocturnal oximetry index, used for example as a comparator in Azarbarzin 2019 |
| `spo2MinPlausible` | 70 percent | **our choice**. A finger PPG reading below 70 during sleep is far more likely a motion or contact artefact than a real value. |
| `spo2SampleInterval` | 1 h | **sourced** from the protocol: the SpO2 log holds one min and max pair per hour (Gadgetbridge `historicalSpo2`) |
| `spo2MinReadings` | 3 | **our choice** |

With hourly samples "time below 90 percent" is coarse: each low reading counts
as a full hour. The screen shows it as an hour count, not to the minute. It is
not an apnea test.

Minimum data: 3 plausible readings in the night, else null.

## 10. Heart rate zones

Class: `HeartRateZones(age: , maxHeartRate: )`, used by the live workout screen.

```
max HR = maxHeartRate if given, else 220 - age
zone n lower bound = round(max HR * f_n),  f = 0.50, 0.60, 0.70, 0.80, 0.90
zone n covers [lower_n, lower_n+1); zone 5 has no upper bound
below zone 1 lower bound = no zone
```

Time in zone (`timeInZones`): each valid sample counts for the time until the
next valid sample, capped at `liveSampleMaxHold`; the last sample counts
nothing yet.

| Constant | Value | Basis |
| :--- | :--- | :--- |
| `220 - age` | | **sourced** (Fox 1971). It is a rough population estimate with an error of around 10 bpm or more for an individual (Robergs 2002; Tanaka 2001 propose 208 - 0.7 * age). Users who know their max HR should enter it; the override always wins. |
| `zoneLowerFractions` | 50, 60, 70, 80, 90 percent | **our choice**, following the five zone percent of max HR split common in consumer training apps |
| `liveSampleMaxHold` | 10 s | **our choice**. Live HR arrives about once a second; a longer silence is a dropout and is not credited to the last zone. |
| accepted max HR | 100 to 250 bpm, age 1 to 119 (age is only checked when it is used, that is without a `maxHeartRate`) | **our choice**, input validation |

## 11. Live workout

Class: `WorkoutSession` in `apps/mobile/lib/features/workout/domain`, driven
by the workout controller once per second. The phone owns the session clock;
the ring streams live HR and, for outdoor types, the phone streams GPS fixes.

States: idle, running, paused, finished, discarded. Start, pause, resume,
finish and discard are the only transitions; a finished or discarded session
never changes again. An instant earlier than the last transition (a clock that
stepped back) is clamped to it.

### Elapsed time

```
elapsed = (end, or the pause start while paused, or now) - start - sum of pauses
```

Pauses are stored, so the moving time can be rebuilt from the database.

### GPS filtering and distance

Fixes are only taken while running. A fix is dropped when:

| Rule | Value | Basis |
| :--- | :--- | :--- |
| horizontal accuracy worse than `maxFixAccuracyMeters` (or unknown, negative or NaN) | 25 m | **our choice**. Phone GNSS reports around 5 m in the open; 25 m rejects the urban canyon and the network fixes a cold start returns first. |
| speed from the last kept fix above `maxPlausibleSpeedMetersPerSecond` | 12 m/s (43 km/h) | **our choice**. Above a sprint and most recreational cycling, so a jump of a bad fix is rejected and a real ride is not. |
| timestamp not after the last kept fix, or before the start or last resume | | out of order |

Each resume opens a new route segment, so the distance between the last fix
before a pause and the first after it is never counted (and the GPX export
writes one `trkseg` per segment).

```
distance = sum over consecutive kept fixes in a segment of haversine(a, b)
haversine(a, b) = 2 R asin( sqrt( sin^2(dLat/2) + cos(lat_a) cos(lat_b) sin^2(dLon/2) ) )
R = 6 371 008.8 m
```

**Sourced**: the haversine formula (Sinnott 1984) and the IUGG mean Earth
radius (Moritz 2000). The spherical model differs from the ellipsoid by under
0.5 percent, well inside GPS noise.

Known limit: the speed rule compares with the last kept fix, so if the first
fix after a start or resume is itself an outlier with good accuracy, the next
fixes are dropped until enough time passes for the jump to look plausible.

### Pace

| Measure | Formula |
| :--- | :--- |
| Current pace | (moving time between the oldest and newest kept fix of the current segment whose moving time is within the last `currentPaceWindow` = 30 s) / their distance. Null while paused or with fewer than two such fixes. |
| Average pace | elapsed / distance |

Both are null below `minPaceDistanceMeters` = 5 m (**our choice**: under
that, GPS jitter dominates and a pace of hours per km is noise). Pace is
time per kilometre.

### Heart rate

Live readings outside 30 to 220 bpm (`minWorkoutHeartRate`,
`maxWorkoutHeartRate`, the same plausibility range as the spot measurement)
are dropped, and readings are only taken while running. Average HR is the
arithmetic mean of the kept readings (they arrive about once a second), max
HR their maximum. Current HR is the last reading if it is at most
`liveSampleMaxHold` (10 s, section 10) old, else none; the current zone is that
reading's zone from section 10, with the profile's max HR or `220 - age`.
Without either there are no zones.

### Energy (estimate)

**Estimate, not a measurement.** OpenRing has no calorimetry; this number is
a population average for the activity scaled by body weight and time.

```
active kcal = (MET - 1) * weight kg * elapsed hours
```

The weight is read when the workout starts: the latest weigh-in when the Body
module is on and has one, otherwise the profile weight. With neither there is
no energy number.

| Type | MET | GPS | Basis |
| :--- | :--- | :--- | :--- |
| running | 9.8 | on | **sourced**: Compendium code 12050, running 6 mph (Ainsworth 2011) |
| walking | 3.5 | on | **sourced**: code 17190, walking 2.8 to 3.2 mph, level, moderate |
| cycling | 7.5 | on | **sourced**: code 01015, bicycling, general |
| hiking | 6.0 | on | **sourced**: code 17080, hiking, cross country |
| strength training | 3.5 | none | **sourced**: code 02054, resistance (weight) training, multiple exercises, 8 to 15 repetitions at varied resistance |
| treadmill | 9.8 | none | **sourced**: code 12050, running 6 mph. The Compendium has no motorised treadmill code (12405 to 12416 are curved, non-motorised treadmills); **our choice** is the level running code at the same speed |
| stationary bike | 7.0 | none | **sourced**: code 02010, bicycling, stationary, general |
| elliptical | 5.0 | none | **sourced**: code 02048, elliptical trainer, moderate effort |
| yoga | 2.5 | none | **sourced**: code 02150, yoga, Hatha (the 2024 Compendium lists 2.3) |
| other | 4.0 | off | **our choice**, a moderate effort |

GPS: "on" types start with GPS on and can turn it off on the pick screen;
"off" starts with it off and can turn it on; "none" are indoor types that
never ask for location. The choice is the session's, not the type's: with GPS
off there is no distance, pace, route or split, and the saved workout has a
null distance, which is how a stored workout tells it recorded no GPS.

One MET is taken as 1 kcal per kg per hour (Ainsworth 2011). Subtracting one
MET leaves the active part, so the value matches the active energy the ring
log already reports and is not double counted with resting energy. Pace and HR
do not enter the formula: a fixed MET per type is wrong for a fast or a slow
session by tens of percent, which is why the screen labels it an estimate. No
weight in the profile gives no energy.

### Splits per km

Function: `kilometreSplits` in `workout_analysis.dart`, on the finished route.

```
walk the kept fixes of each segment in order, adding haversine distance and
the time between consecutive fixes (a gap between segments is a pause and adds
neither); where the running distance crosses a whole km, the crossing time is
interpolated linearly inside that pair of fixes
split pace     = moving time of the split / its distance, per km
split HR       = mean of the HR samples between the split's first and last instant
last split     = the remainder, kept when it is at least minLastSplitMeters
```

| Constant | Value | Basis |
| :--- | :--- | :--- |
| `splitMeters` | 1000 m | the unit the pace is shown in |
| `minLastSplitMeters` | 50 m | **our choice**. A shorter remainder is a few GPS fixes, and its pace scaled to a km is noise. |

The relative speed bar is 100 percent for the fastest split and 55 percent
for the slowest, linear in pace between them (**our choice**, from the design).

### Elevation gain

Function: `elevationGainMeters`, on fixes that carry an altitude.

```
per segment, keep a reference altitude, starting at the first known one
altitude below the reference                   -> it becomes the reference
altitude at least elevationHysteresisMeters up -> gain += altitude - reference,
                                                  it becomes the reference
fewer than two fixes with an altitude          -> no value
```

| Constant | Value | Basis |
| :--- | :--- | :--- |
| `elevationHysteresisMeters` | 3 m | **our choice**. Phone GNSS altitude wanders by several metres at rest; summing every rise would count that noise as climbing. The value is shown as approximate. |

Pauses open a new segment, so a change of altitude while paused is not climb.

### Pauses

Each pause is stored with its start and end. The summary shows their count,
the total paused time and each one; the moving time of section 11 already
leaves them out. When a saved route is read back, a fix at or after a pause's
end starts a new segment, which rebuilds the segments the live session had.

## 12. History (trends)

Function: `TrendHistory.collect`, then `TrendSeries.of(values, today, days)`.
The code lives in the app (`lib/features/trends/domain`), not in
`packages/metrics`, because it only arranges values the functions above
already produce.

One value per local date:

| Series | Value of a date | Date |
| :--- | :--- | :--- |
| Resting HR | `restingHeartRate` of the night's heart rate samples (section 3) | the night's date (section 1) |
| Overnight HRV | `nightlyHrv` of the night's readings (section 4) | the night's date |
| Sleep | total asleep in minutes | the night's date |
| Sleep score | `sleepScore` of the night, nights without a score are left out (section 2) | the night's date |
| SpO2 | mean of `spo2NightSummary` over the night (section 9) | the night's date |
| Steps | steps summed over the activity buckets of the date; a date with zero steps counts as not worn | the bucket's local date |

```
days      = the last N local dates ending today (N = 7, 30 or 90)
a date    = mean of its values, null when it has none (a gap)
settled   = dates with a value, without today for steps
mean, min, max over settled
change    = mean(second half) - mean(first half), halves split at N / 2
```

| Constant | Value | Basis |
| :--- | :--- | :--- |
| ranges | 7, 30, 90 days | **our choice**, the design's week, month and three months |
| `trendMinHalfValues` | 2 | **our choice**. Each half needs two values, so one stray day cannot set the direction. Below that the screen says there are not enough days. |
| today's steps | left out of mean, min and max | **our choice**. The day is still running, so its count would always look like a low day. It is drawn and named "so far". |

A gap stays a gap: it is drawn as an empty slot and never filled in or counted
as zero. Dates come from `LocalDate` arithmetic, so a DST change neither adds
nor drops a day.

Readiness over the last 14 days, on the Readiness screen, is function
`ReadinessTrend.collect` (`lib/features/today/application`). It runs
`readiness` (section 7) again for each date, with the sleep score, HRV and
resting HR of that date and baselines and activity load as of that date, so it
is not stored and changes if the formula changes. A date without a score is a
gap. The average is the rounded mean of the dates with a score.

"Your range" is shown only for resting HR and HRV: it is the personal baseline
of section 5 as of today, one SD either side of the mean (on the log scale for
HRV, then converted back to ms). The other series have no published baseline,
so they show none.

## 13. Weight (trend, rate, noise)

Functions: `dailyWeights(weighIns)`, `weightTrend(weighIns)`,
`weightRate(weighIns, today)`, `weightNoise(weighIns)`.

Inputs: weigh-ins in kilograms, each with its local date. Values that are not
finite are dropped.

```
daily   = one value per local date, the mean of that date's weigh-ins

trend_1 = mean of the first min(7, n) daily values
gap     = days since the previous daily value (>= 1)
pull    = 1 - (1 - alpha)^gap
trend_d = trend_prev + pull * (daily_d - trend_prev)

window  = daily values with 0 <= today - date < 28
t_i     = days since the first date of the window
slope   = sum((t_i - mean t) * (w_i - mean w)) / sum((t_i - mean t)^2)
se      = sqrt( sum(residual_i^2) / (n - 2) / sum((t_i - mean t)^2) )
rate    = 7 * slope                              kg per week
low, high = 7 * (slope -/+ t(0.975, n - 2) * se)
stable  = low <= 0 <= high

noise   = max( floor, sqrt( mean((daily_d - trend_d)^2) ) )
```

| Constant | Value | Basis |
| :--- | :--- | :--- |
| `weightTrendAlpha` | 0.1 per day | **sourced** method and value: Walker 1991, 10 percent smoothing. Half life 6.6 days. |
| `weightTrendSeedDays` | 7 | **our choice**. Starting at the mean of the first week keeps one odd first weigh-in from setting the trend for a month. |
| `weightRateWindowDays` | 28 days | **our choice**. With a day to day spread of 0.6 kg and daily weigh-ins the 95 percent interval of the slope is about 0.55 kg per week either side at 14 days and 0.19 at 28, so four weeks can tell 0.25 kg per week from nothing and two cannot. |
| `weightRateMinDays` | 8 dates | **our choice**. Six degrees of freedom is the least we accept for an interval. |
| `weightRateMinSpanDays` | 14 days | **our choice**. Eight dates inside one week measure water, not a rate. |
| interval | Student t, 95 percent, n - 2 degrees of freedom | **sourced**: the standard interval of a least squares slope. The normal 1.96 would be too narrow at 8 dates (the t value is 2.447). |
| `weightNoiseMinDays` | 3 dates | **our choice**. Below that the band is `weightNoiseDefault`. |
| `weightNoiseDefault` | 0.5 kg | **our choice**, the low end of the 0.5 to 1 kg day to day spread of body weight from water, glycogen, gut content and sodium. |
| `weightNoiseFloor` | 0.35 kg | **our choice**. A few close weigh-ins must not draw a band narrower than a scale and a glass of water can move. |

Below `weightRateMinDays` dates or `weightRateMinSpanDays` of span the rate is
`WeightRateBuilding(daysMissing, spanMissing)`, never a number. When the
interval contains zero the rate is `stable`: the change is not larger than the
noise, and the app shows no direction.

Under a steady change the trend lags the true weight by
`(1 - alpha) / alpha = 9` days of change. So the trend is for display and the
rate comes from the raw daily values, not from the trend.

The weigh-ins used for the first trend value are counted again by the
following steps, and the noise is measured around that same trend, so the band
of a short series is rough. It is a drawing aid, not an interval.

## 14. Intensity minutes

Functions: `heartRateIntensity(samples, maxHeartRate, maxHold)`,
`metIntensity(met, elapsed)`, `workoutIntensity(met, elapsed, heartRate,
maxHeartRate)`, `walkingIntensity(buckets, workouts)`,
`weeklyIntensityMinutes(dailyEquivalent, today, windowDays, minDays)`.

```
equivalent = moderate + 2 * vigorous                       minutes

by heart rate: a sample counts for the time to the next one, at most maxHold
  moderate when 0.64 * max <= bpm < 0.77 * max
  vigorous when bpm >= 0.77 * max

by type:       met < 3 earns nothing
               3 <= met < 6 is moderate for the whole elapsed time
               met >= 6 is vigorous for the whole elapsed time

workout      = the credit with the larger equivalent of the two
               (by type alone when there is no max heart rate)

walking      = minutes of every activity bucket with steps / minutes >= 100
               that does not overlap a workout, all moderate

weekly       = sum of the daily equivalents with 0 <= today - date < 7
```

`weeklyIntensityMinutes` takes one value for each day the ring reported
activity, zero included, so a rest day counts as a day of data. A date given
twice counts once.

| Constant | Value | Basis |
| :--- | :--- | :--- |
| `vigorousMinuteWeight` | 2 | **sourced**, WHO 2020 treats one vigorous minute as two moderate ones. Checked against the source on 2026-11-15. |
| `moderateFraction`, `vigorousFraction` | 0.64, 0.77 of max heart rate | **sourced**, Garber 2011 (ACSM). Checked on 2026-11-15 through a secondary table of the position stand, not the paper itself. Stricter than the 50 and 70 percent some apps use. |
| `moderateMet`, `vigorousMet` | 3, 6 | **sourced**, the WHO 2020 definitions of moderate and vigorous. Checked against the source on 2026-11-15. |
| larger of the two credits | | **our choice**: heart rate understates the load of resistance work |
| `briskStepsPerMinute` | 100 | **sourced**, Tudor-Locke 2018, cadence of moderate walking. Checked against the source on 2026-11-15. |
| heart rate outside workouts | not used | **our choice**: a raised heart rate without movement is stress or caffeine, not exercise |
| `intensityWindowDays` | 7 | **our choice**: the target is weekly, so a rest day after training days costs nothing |
| `intensityMinDays` | 4 | **our choice**, the same minimum as the acute load window |

Minimum data: 4 days with activity data in the window, else null. A heart rate
credit needs two valid samples.

## 15. Day Score

Function: `dayScore(sleepScore, steps, stepGoal, intensityMinutes, hrv,
restingHeartRate, stress, spo2Mean, readiness)`, for one local date D. Also
`dayScoreBand(score)` and `stressBaseline(dailyStressMean, today)`.

Inputs: the sleep score (section 2) of the night that ended on D, the steps of
D, the weekly intensity minutes ending on D (section 14), the z of last
night's HRV and resting heart rate against their baselines (section 5), the z
of the day's stress mean (section 8) against the stress baseline, and the mean
SpO2 of the night (section 9). The readiness of D (section 7) is an optional
input that only sets the step goal of the day, below.

| Pillar | Factor | Subscore | Points |
| :--- | :--- | :--- | :--- |
| Sleep | sleep | `ramp(score, 0, 100)` | 30 |
| Movement | steps | `ramp(steps, 0, dayStepGoal)` | 15 |
| Movement | intensity | `ramp(minutes, 0, 150)` | 20 |
| Recovery | HRV | `ramp(z, -3, +1)` | 10 |
| Recovery | resting heart rate | `ramp(z, +3, -1)` | 10 |
| Stress | stress | `ramp(z, +3, -1)` | 10 |
| Oxygen | SpO2 | `ramp(mean, 90, 95)` | 5 |

```
coverage = sum of the points of the factors present
score    = round(100 * sum(points_i * subscore_i) / coverage)
```

A missing factor is left out and the rest is rescaled, so it never costs
points. Each contribution carries its rescaled weight; `coverage`, `isFull`
and `missing` read the result. Steps above the goal earn nothing extra.

### Low readiness day

`dayStepGoal` is the step goal, except on a day whose readiness is below
`readinessFairFrom` (55, the low band of section 7), where it is
`round(stepGoal * lowReadinessStepGoalFactor)`, never below 1. Readiness 55
and a day without a readiness value keep the full goal. Only the steps factor
moves: the weekly intensity minutes and every other factor are scored the
same, and the weights do not change.

`fullGoalStepPoints` is what the steps would have earned against the full
goal, `15 * ramp(steps, 0, stepGoal)`, and exists only on a low day with
steps. The receipt prints it next to the goal of the day, so the easier goal
is never hidden.

The app computes the readiness of each of the 90 days of the history with the
function and inputs of the Readiness card, so a past day reads the same as
today. For that the history also reads the 28 nights before its first day,
used only for the HRV and resting heart rate baselines, so the oldest day has
the same 28 day baseline as today. The HRV and resting heart rate factors of
the Day Score read the same baselines, so with those nights any day older
than about 62 days, low or not, is scored against a full baseline where it
used to have a short one or none, and its score can move up or down. Nothing
is stored. Readiness reads active energy through the activity load, so on a
low day active energy reaches the Day Score through the step goal and in no
other way. Age reaches it only through the heart rate zones of a workout,
when the profile has no maximum heart rate (section 14).

A day at 54 and a day at 55 are scored against
different goals: the step is one rule a person can check, and a ramp would be
a second number to explain.

The stress baseline is the personal baseline of section 5 on a linear scale,
28 days, at least 7, with a minimum spread of `stressMinSpread`.

| Band | Score |
| :--- | :--- |
| great | 85 to 100 |
| good | 70 to 84 |
| mixed | 55 to 69 |
| low | 0 to 54 |

| Constant | Value | Basis |
| :--- | :--- | :--- |
| weights | 30, 15, 20, 10, 10, 10, 5 | **our choice**: sleep and movement are measured best; recovery is capped at 20 so HRV and resting heart rate, which readiness already reads, do not dominate here too; stress is an unpublished vendor number and hourly finger SpO2 is noisy |
| `intensityWeeklyTarget` | 150 min | **sourced**, the lower end of the WHO 2020 weekly range. Checked against the source on 2026-11-15. |
| HRV and resting heart rate ramps | as readiness | the constants of section 7 |
| `stressZeroZ`, `stressFullZ` | +3, -1 | **our choice**, the resting heart rate ramp, since higher is worse for both |
| `stressMinSpread` | 3 points | **our choice**, so a flat history does not turn one point into a large z |
| `spo2ZeroAt`, `spo2FullAt` | 90, 95 percent | **our choice**: 90 is the low threshold of section 9 and 95 is a usual sleeping value |
| `dayScoreMinCoverage` | 60 points | **our choice** |
| `lowReadinessStepGoalFactor` | 0.6 | **our choice**: on a day the body asks for less, a lighter walk still earns the steps in full. Not from a study. |
| band cut points | 85, 70, 55 | **our choice**, the readiness cut points, so there is one scale to learn |

Minimum data: the sleep score and at least one step, and 60 points of
coverage. Zero steps reads as the ring off the finger. Otherwise the result is
`InsufficientData` with every missing factor. The Day Score describes the day,
not the person's health.

## 16. Level

The Level is the user's own recent average of Day Scores, shown with one decimal. It is the line a day is
compared with. Code: `packages/metrics/lib/src/level.dart`.

**Inputs.** Closed days, oldest first, each with its Day Score or none, and whether the user set the day aside
(sick, travel or rest). Today is not an input until it closes.

**Rule.**

```
alpha = 1 - exp(-1 / 28)            about 0.0351
level = level + alpha * (score - level)
```

- A day counts when it has a score and was not set aside. A day that does not count leaves the Level exactly
  where it was: no data, sickness, travel and rest never lower it.
- There is no Level before 14 counted days. The first Level is the simple mean of those 14 scores.
- A day 10 points above the line raises the Level by about 0.35; a day 10 points below lowers it by the same.
- There is no window: a counted day keeps a weight of `alpha * (1 - alpha)^k`, where `k` is the number of counted
  days after it. Once 28 days have counted after the first Level, those 28 carry about 63 percent of it.

**The line and the side.** The line of a day is the Level as it stood before that day. A Day Score is a whole
number and the Level has one decimal, so the score is compared with the Level rounded to a whole number: 71
against 71.4 is on the line, 72 is above, 70 is below.

**In the app.** Nothing is stored: the Level is walked again from the Day Score history the app keeps, with the
tagged days set aside. The first 14 counted days of that history are the seed, so the seed moves forward as old
days leave the history; by then it carries a few percent of the Level. Days inside the seed have no line of
their own.

**Weekly goal.** A week runs from Monday to Sunday. A closed day counts when its score is on its line or above,
by the comparison above. The goal is a number of such days, from 3 to 7, 4 unless the user changes it. Today counts
only once it has closed. A tagged day, a day without a score and a day inside the seed count neither for nor
against. Nothing carries from one week to the next: there is no streak.

**Personal bests.** Over the closed, counted days of the history the app keeps: the highest Day Score, the highest
Level at one decimal, and the best week, which is the rounded mean of the counted scores of a whole week already
over with at least 4 counted days. A tie keeps the earlier holder. Because they are read from the kept history, a
best leaves when its day does.

**Celebration.** The morning after, Today shows one card when yesterday completed the weekly goal, set a best
day over an earlier one, or set a highest Level over an earlier one. The highest Level is celebrated once a week:
only when the best it beat was set before that week's Monday. The app stores only the date of the last card the
user closed, so a closed card stays closed for that day.

**What it is not.** Not a streak, not a rank against other people, not a health forecast. It is an average chosen
by the product, not a published clinical formula, and it is stated as such on the screen that shows it.

## 17. Overall

Function: `OverallInputs(...).score`, with `overallBand(score)`. A slow number
for "how am I in general", built from trailing windows and not from Day
Scores. The formula comes first; the windows that feed it and the weekly cadence are
under "Windows and weeks" below.

| Group | Factor | Input | Subscore | Points |
| :--- | :--- | :--- | :--- | :--- |
| Heart | fitness | position among people of the same age and sex, 0 to 100 | `ramp(position, 0, 90)` | 30 |
| Heart | resting heart rate | mean nightly value, bpm | `ramp(bpm, 80, 50)` | 15 |
| Sleep | sleep duration | mean hours asleep | `ramp(hours, 5, 7)` | 10 |
| Sleep | sleep regularity | Sleep Regularity Index | `ramp(sri, 50, 90)` | 15 |
| Movement | movement | three habits, below | sum of the three, over 20 | 20 |
| Body | body | waist to height ratio, or BMI | below | 10, or 5 with BMI |

```
coverage = sum of the points of the factors present
score    = round(100 * sum(points_i * subscore_i) / coverage)
```

Movement adds three parts: weekly moderate equivalent minutes, 10 points,
`0.75 * ramp(m, 0, 150) + 0.25 * ramp(m, 150, 300)`; strength sessions a
week, 4 points, `ramp(sessions, 0, 2)`; mean daily steps, 6 points,
`ramp(steps, 2500, 8000)`, or full at 7,000 for an older adult. It needs
minutes and steps; no strength session counts as zero, not as missing.

Body with a waist measure is `ramp(ratio, 0.65, 0.50)` over 10 points, full
anywhere at or below 0.50. Without the waist it is BMI over 5 points: full
from 18.5 to 25, then `ramp(bmi, 35, 25)`. A ratio under 0.40 or a BMI under
18.5 removes the factor: it is neither scored low nor high, so the score
never rewards getting leaner inside or below the healthy range.

A missing factor is left out and the rest is rescaled, so it never costs
points. HRV is not a factor.

Minimum data: 50 points of coverage, with fitness or resting heart rate, and
with one sleep factor. Otherwise the result is `InsufficientData` with every
missing factor.

| Band | Score |
| :--- | :--- |
| strong | 85 to 100 |
| solid | 70 to 84 |
| building | 55 to 69 |
| start | 0 to 54 |

| Constant | Value | Basis |
| :--- | :--- | :--- |
| weights | 30, 15, 10, 15, 20, 10 | **our choice** |
| `fitnessFullPercentile` | 90 | **our choice**, so the score does not push people who are already fit toward extremes |
| resting heart rate ramp | 80 to 50 bpm | **sourced**, the central range of Quer 2020. Not checked against the source. |
| `sleepHoursFullAt` | 7 h | **sourced**, Watson 2015. Not checked against the source. Zero at 5 h is **our choice**. |
| sleep regularity ramp | 50 to 90 | **our choice** |
| movement minutes | 150 and 300 a week | **sourced**, the WHO 2020 range, as in section 14. The three quarters share is **our choice**. |
| `movementStrengthTarget` | 2 a week | **sourced**, WHO 2020. Not checked against the source. |
| steps ramp | 2,500 to 8,000, or 7,000 | **sourced** for the full mark, Paluch 2022, not checked against the source. The floor is **our choice**. |
| waist to height | 0.40, 0.50, 0.65 | 0.40 and 0.50 from the NICE bands, not checked against the source. Zero at 0.65 is **our choice**. |
| BMI | 18.5, 25, 35 | 18.5 and 25 from the WHO bands. Zero at 35 and the 5 points are **our choice**. |
| `overallMinCoverage` | 50 points | **our choice** |
| band cut points | 85, 70, 55 | **our choice**, the Day Score cut points |
| `overallNoiseBelow` | 2 points | **our choice**: a weekly change smaller than this is not reported as a change |

The Overall describes habits and measures, not the person's health.

### Windows and weeks

Functions: `overallMondays(today)` and `overallInputsOn(monday, ...)`. The
app shows the Overall of the last 12 Mondays, oldest first, and the last one
is the current value: it does not change until the next Monday. Nothing is
stored. Each Monday is recomputed from the data, so a past Monday can move
when a day is tagged, a weigh-in is edited or a late sync brings older
samples.

The first Overall does not wait for a Monday. While the last Monday has no
score, the app shows the Overall of the first day after it on which the
minimum was met, and keeps it until the next Monday. Before that the app counts, of the 14 it
needs, the nights with a resting heart rate in the 28 days before today.
Next to the score the
screen says how far it is from the Monday before, and calls a change under
2 points noise.

The window of a Monday is the 28 days that end the day before it, without the
days tagged Sick or Travel. Rest days stay: rest is part of a routine. A worn
day is a day of the window with at least one heart rate sample.

| Input | From | Needs |
| :--- | :--- | :--- |
| resting heart rate | mean of the nightly resting heart rate (section 3) of the nights that ended in the window | 14 nights |
| sleep duration | mean time asleep of the main night of each date in the window | 14 nights |
| sleep regularity | the index below over the worn days, naps included | 14 pairs |
| weekly minutes | moderate equivalent minutes (section 14) of the worn days, times 7 over their count | 14 worn days |
| daily steps | mean steps of the worn days; a worn day without steps counts as zero | 14 worn days |
| strength | distinct days with a strength workout in the window, times 7 over its length | 14 days in the window |
| body | the last waist and the last weight logged before the Monday, with the profile height; only while the Body module is on | a height and a weigh-in |
| fitness | the position, by age and sex, of the best estimate among the outdoor runs and walks recorded in the 90 days before the Monday (below) | one estimate, a resting heart rate, a sex and an age from 20 to 79 |

Sleep comes from one source per date, the first in the user's order that has
any sleep on it, and that source's naps count for the regularity index. An
older adult, for the steps rule, is 60 or more this year by the profile's
birth year. The height, the birth year and the source order of today are
applied to past Mondays too. The 28 days, the 14, the worn day rule and which
tags leave are **our choice**.

Each row of the Overall screen opens an evidence sheet with the value, the
window, the rule, its source, what is our choice and the limits. The numbers
of the rule in that sheet are the constants above, formatted, so the sheet
cannot drift from the formula.

The 12 weeks screen (`OverallTrend.of`) reads the same 12 Mondays. The
typical week is the median of the scored weeks and the floor is their 10th
percentile by nearest rank, which is the lowest week until there are 11 of
them. A point is drawn hollow, and the line breaks, where a week was scored
on other factors than the latest scored week: a missing factor rescales the
rest, so those two scores do not compare exactly. It needs two scored
weeks; an early first score counts as the last one, so "now" is the number
of the Overall screen. The change of the Body points is not listed while the
Body numbers are hidden. These choices are **our choice**.

### Fitness estimate

`packages/metrics/lib/src/fitness_estimate.dart` and
`features/open_score/domain/fitness_efforts.dart`. The source is a workout of
type running or walking recorded in the app with a route. Workouts imported
from Health Connect carry no route here and are not read.

1. A workout is cut at its pauses. Each pause free stretch loses its first
   3 minutes, while the heart rate is still rising, and needs 10 minutes
   after that and at least one heart rate sample a minute.
2. The speed of a stretch is its distance over its time. The oxygen cost of
   that speed on flat ground is `3.5 + 0.1 * speed` for a walk between 50 and
   100 m/min and `3.5 + 0.2 * speed` for a run at 80 m/min or more, in
   mL/kg/min with the speed in m/min. Grade is ignored, so a climb reads low.
3. The share of the heart rate reserve used is
   `(mean bpm - resting) / (maximum - resting)`. The resting value is the
   Overall's own, the mean of the window; the maximum is the profile's, else
   `220 - age`. A stretch counts between 60 and 90 percent of the reserve.
4. `VO2max = 3.5 + (cost - 3.5) / share`.
5. A workout is the median of its stretches, and the value of a Monday is the
   highest workout of the 90 days before it.
6. The position comes from the table below by linear interpolation, kept
   between 5 and 95, for the age reached in the year of that Monday.

VO2max in mL/kg/min at percentiles 5, 10, 25, 50, 75, 90 and 95:

| Age | Men | Women |
| :--- | :--- | :--- |
| 20 to 29 | 29.0, 32.1, 40.1, 48.0, 55.2, 61.8, 66.3 | 21.7, 23.9, 30.5, 37.6, 44.7, 51.3, 56.0 |
| 30 to 39 | 27.2, 30.2, 35.9, 42.4, 49.2, 56.5, 59.8 | 19.0, 20.9, 25.3, 30.2, 36.1, 41.4, 45.8 |
| 40 to 49 | 24.2, 26.8, 31.9, 37.8, 45.0, 52.1, 55.6 | 17.0, 18.8, 22.1, 26.7, 32.4, 38.4, 41.7 |
| 50 to 59 | 20.9, 22.8, 27.1, 32.6, 39.7, 45.6, 50.7 | 16.0, 17.3, 19.9, 23.4, 27.6, 32.0, 35.9 |
| 60 to 69 | 17.4, 19.8, 23.7, 28.2, 34.5, 40.3, 43.0 | 13.4, 14.6, 17.2, 20.0, 23.8, 27.0, 29.4 |
| 70 to 79 | 16.3, 17.1, 20.4, 24.4, 30.4, 36.6, 39.7 | 13.1, 13.6, 15.6, 18.3, 20.8, 23.1, 24.1 |

| Part | Basis |
| :--- | :--- |
| the table | **sourced**, Kaminsky 2015, table 2 (FRIEND registry, treadmill tests in the United States), read from the paper at PMC4919021 |
| the cost of walking and running | **sourced**, the ACSM metabolic equations. Not checked against the source. |
| reserve share equals share of the oxygen reserve | **sourced**, Swain and Leutholtz 1997. Not checked against the source. |
| speed limits of each equation, 3 and 10 minutes, 60 to 90 percent, one sample a minute | **our choice** |
| best of 90 days, median inside a workout | **our choice**: a tired or hot day should not lower a capacity number |
| no grade | **our choice**: phone altitude is noisy, and flat ground errs low |

Known limits: the resting heart rate is measured asleep, lower than the awake
value the reserve method assumes, which lowers the estimate a little; a
maximum heart rate from age can be off by 10 beats or more; the table is not
a sample of any population. The app never estimates fitness from the resting
heart rate alone.

### Sleep Regularity Index

Function: `sleepRegularity(spans, days)`. The day is cut into 288 epochs of 5
minutes on the wall clock of each sleep span. An epoch is asleep when its
start falls inside a span that is not awake, so naps count. For every pair of
consecutive days in `days`, each epoch is compared with the same clock time
on the next day:

```
index = -100 + 200 * epochs with the same state / epochs compared
```

100 is every day repeating the one before, 0 is what chance gives, -100 is
opposite days. The caller gives the valid days: a pair counts only when both
days are in the set, and a valid day without any sleep is a real day awake.
Fewer than `sleepRegularityMinPairs` (14) pairs give no index.

The definition is the one of Phillips 2017, not checked against the source.
It compares clock times, so across a daylight saving change the second day is
read one hour off the 24 hours of the paper. The 5 minute epoch and the 14
pairs are **our choice**.

## 18. Energy (daily estimate)

`packages/metrics/lib/src/energy.dart`. Pure functions for the Energy module.
Today reads them through the row described at the end of this section. Every figure is an estimate for the average person
of a given size, never a measurement and never a target for eating.

| Part | Rule | Basis |
| --- | --- | --- |
| Resting | `9.99 * kg + 6.25 * cm - 4.92 * age + 5` for men, `- 161` for women, in kcal a day | Mifflin 1990, written from memory and not checked against the paper |
| Base | resting times `energyBaseFactor` (1.3), spread evenly over the 24 hours | **our choice**: resting plus the small movements of a day without exercise; the factor is not sourced |
| Steps | steps times `energyStepLengthFactor` (0.415) times height gives the distance; `energyWalkCostPerKgKm` (0.5) kcal per kg per km above rest | both constants are common rules of thumb, **not sourced** |
| Workout | `(MET - 1) * kg * hours`, never below zero | the rule of section 11 (Ainsworth 2011) |

The owner decided on 2026-11-15 that the step distance always comes from the
height, for both sexes, and never from the distance the ring reports: the
ring's formula is not published, and this one can be redone by hand.

`restingEnergy` gives no number without sex, age, weight and height, or under
`energyAdultAge` (18): the equation was fitted on adults.

A number is shown as a range. `energyRange` takes the margin on the total and
rounds each end to `energyRangeStep` (50 kcal): `energyRestingMargin` (10
percent) for the resting figure, `energyDayMargin` (15 percent) for a day.
Frankenfield 2005 found the equation within 10 percent of the measured resting
value for more people than the other common equations, which still leaves
people outside it. The 15 percent of the day is **our choice**.

### One day

`apps/mobile/lib/features/energy/domain/energy_day.dart`, `energyDay`. A day
is the sum of three parts. Base and workouts read the day between two local
midnights at the offset the phone has now, so a day before a clock change or
a trip is read that many hours off; the step buckets keep the date they were
stored with.

- **Base**: the day base for the time gone by, so today grows with the clock
  and a past day holds 24 hours, also on the day the clocks change.
- **Steps**: every 15 minute bucket of the day. The part of a bucket that a
  workout covers is left out, in proportion to the time covered, because the
  workout already counts that movement. Workouts over the same minutes cover
  them once.
- **Workouts**: the kcal stored with the workout when it has one, else the
  workout rule above with the current weight (a workout read from another app
  stores none). A workout counts whole on the day it started (owner decision
  of 2026-11-15, the rule the Day Score uses); one that started the day before
  adds nothing here and still removes the steps it covers, as does any
  workout over a bucket of this date.

An own workout and one from another app that overlap count once, by the
source order of the workout list. The weight is the latest weigh-in when the
Body module is on, else the profile weight. Without sex, birth year, height or
weight the day has no number and names the missing fields; under 18 it has
none either. Nothing is stored: the day is computed on every read.

### On Today

`apps/mobile/lib/features/energy/presentation/energy_row.dart`. With the
Energy module on, Today shows one thin row under the Day Score: the day so far
as a range in kcal, and the clock time it was computed at. The row is computed
again when new data arrives and when the app comes back to the foreground, not
on a timer, so the time on it says how old the number is. Today is the date of
that instant, so a return after midnight starts the new day, and the age
that hides the row uses the year of the same instant. While a new day loads
the row keeps the last one with its own time, and a day that fails to load
removes the row.

While the low end of the range is under `energyRowFloor` (100 kcal, about the
first hour after midnight for a person who has not moved) the row says the day is just starting and shows no
range. With a profile field missing it names the field, or asks to complete
the profile when more than one is missing, and a tap opens Settings; a person
who chose not to state a sex is asked to choose Female or Male, because the
equation has no third form. The row is absent for a person under 18, while
the Body module hides the numbers, and until the modules, the profile and the
hide choice have loaded (`energy_gate.dart`).

A tap on the range or on the starting line opens the Energy screen.

### The Energy screen

`apps/mobile/lib/features/energy/presentation/energy_screen.dart`, at
`/today/energy`. It reads the same day and the same instant as the row, and it
is empty under the same conditions: module off, under 18, numbers hidden.

The day card shows the range, the middle of the range (the total rounded to
50 kcal), a bar and the three parts. Each part prints to the nearest 10 kcal
with the word "about", because a finer figure would claim more than the
estimate knows; the parts are single figures, and only the total is a range.
The bar is as wide as 1.5 times a full day of Base (`energyBarBaseDays`), or
as the top of the range once the day is past that, so it fills as the hours
pass; the factor is a choice with no source. The thin line under the bar is
the range. Under `energyRowFloor` the card says the day is just starting and
shows no range, bar or parts.

The resting card shows the resting burn as a range of 10 percent to each side
and never the exact figure. With a profile fact missing the screen lists the
four facts, marks the missing ones and offers Settings; it shows no number
at all.

The card "Through the day" (`energy_through_day.dart`) draws how today adds
up. `energyCurve` computes the same day at each full hour and at the instant
of the estimate, from the same inputs: at an hour it counts the step slots
that ended by it and the workouts that started before it, so a slot or a
workout shows up whole at a full hour and not minute by minute, and the total
never falls from one hour to the next. The last point is the day itself. The band above the total and the line under it are the 15 percent
margin. A tap picks the closest point; a screen reader steps hour by hour.
The card is absent while the day is under `energyRowFloor`, and a picked hour
under the floor shows the starting line and no range.

The chart through the day also draws the usual day as a dashed line
(`energyUsualByHour`, `energyUsualByHourProvider`): the mean total, at each
elapsed hour, of the same past days that make the usual day of the week
card, so its last point is that usual day. Under the readout one sentence
says how far the picked hour is from the usual day at that hour
(`energyUsualAt` reads between two hours on a straight line), to the nearest
50 kcal, or that it is about the same. No line and no sentence with fewer
than 3 past days, and no sentence while the picked hour is under the floor.
A past day of 23 or 25 hours stays out of the line, and on such a day the
chart shows no usual day, because the hours would not line up.

The formula screen (`energy_formula_screen.dart`, `/today/energy/formula`)
repeats the rule, the source, our choice and the limits of the four evidence
sheets with no value of the person, then the two margins and the full
references. It is empty unless the gate is on.

While the gate is on, the active energy the ring reports is named as coming
from the ring on Activity and on the Today activity card, because the app
then shows two energy figures that are not meant to be added. The hide
numbers choice names the energy estimate only while the Energy module is on.

The last 7 days (`energy_week.dart`, `energyWeekProvider`) are one range bar
per day, with the middle marked and an axis that starts at zero, so the bars
visibly overlap. A past day with no steps and no workout on record was most
likely a day without the ring: it shows as no data and stays out of the usual
day. The usual day is the mean total of the past days on record, without
today, shown as a range with the same 15 percent margin, and only with 3 days
or more (`energyUsualMinDays`, our choice). The card appears once one past day
is on record. A past day is computed with the weight and the profile of today.

A tap on the resting card or on a part of the day opens an evidence sheet
(`energy_evidence_sheet.dart`): what it is, the value of the person, the rule
with its constants printed from `packages/metrics`, the source, what is our
choice and the limits. The sheet of the resting burn shows the range and never
the exact figure, so it prints no worked sum. The figures it quotes from
studies are the ones the science review checked: Frankenfield 2005 (within 10
percent for more people than the other equations), the FAO, WHO and UNU 2001
range of 1.40 to 1.69 for a seated lifestyle, and Shcherbina 2017 (the best of
seven wrist devices 27 percent off on energy). The net cost of walking is
given as close to 0.5 kcal per kg per km with no paper named.

## References

- Ainsworth BE, Haskell WL, Herrmann SD, et al. 2011 Compendium of Physical
  Activities: a second update of codes and MET values. Med Sci Sports Exerc.
  2011;43(8):1575-1581.
- Azarbarzin A, Sands SA, Stone KL, et al. The hypoxic burden of sleep apnoea
  predicts cardiovascular disease-related mortality: the Osteoporotic Fractures
  in Men Study and the Sleep Heart Health Study. Eur Heart J.
  2019;40(14):1149-1157.
- Bull FC, Al-Ansari SS, Biddle S, et al. World Health Organization 2020
  guidelines on physical activity and sedentary behaviour. Br J Sports Med.
  2020;54(24):1451-1462.
- Buchheit M. Monitoring training status with HR measures: do all roads lead to
  Rome? Front Physiol. 2014;5:73.
- Fox SM, Naughton JP, Haskell WL. Physical activity and the prevention of
  coronary heart disease. Ann Clin Res. 1971;3(6):404-432.
- Frankenfield D, Roth-Yousey L, Compher C. Comparison of predictive equations
  for resting metabolic rate in healthy nonobese and obese adults: a
  systematic review. J Am Diet Assoc. 2005;105(5):775-789.
- Gabbett TJ. The training-injury prevention paradox: should athletes be
  training smarter and harder? Br J Sports Med. 2016;50(5):273-280.
- Garber CE, Blissmer B, Deschenes MR, et al. Quantity and quality of exercise
  for developing and maintaining cardiorespiratory, musculoskeletal, and
  neuromotor fitness in apparently healthy adults: guidance for prescribing
  exercise. Med Sci Sports Exerc. 2011;43(7):1334-1359.
- Herrmann SD, Willis EA, Ainsworth BE, et al. 2024 Adult Compendium of
  Physical Activities: a third update of the energy costs of human activities.
  J Sport Health Sci. 2024;13(1):6-12.
- Hirshkowitz M, Whiton K, Albert SM, et al. National Sleep Foundation's sleep
  time duration recommendations: methodology and results summary. Sleep Health.
  2015;1(1):40-43.
- Impellizzeri FM, Tenan MS, Kempton T, Novak A, Coutts AJ. Acute:chronic
  workload ratio: conceptual issues and fundamental pitfalls. Int J Sports
  Physiol Perform. 2020;15(6):907-913.
- Mifflin MD, St Jeor ST, Hill LA, Scott BJ, Daugherty SA, Koh YO. A new
  predictive equation for resting energy expenditure in healthy individuals.
  Am J Clin Nutr. 1990;51(2):241-247.
- Moritz H. Geodetic Reference System 1980. J Geod. 2000;74(1):128-133.
- Ohayon MM, Carskadon MA, Guilleminault C, Vitiello MV. Meta-analysis of
  quantitative sleep parameters from childhood to old age in healthy
  individuals: developing normative sleep values across the human lifespan.
  Sleep. 2004;27(7):1255-1273.
- Ohayon M, Wickwire EM, Hirshkowitz M, et al. National Sleep Foundation's
  sleep quality recommendations: first report. Sleep Health. 2017;3(1):6-19.
- Plews DJ, Laursen PB, Stanley J, Kilding AE, Buchheit M. Training adaptation
  and heart rate variability in elite endurance athletes: opening the door to
  effective monitoring. Sports Med. 2013;43(9):773-781.
- Plews DJ, Laursen PB, Le Meur Y, Hausswirth C, Kilding AE, Buchheit M.
  Monitoring training with heart rate variability: how much compliance is
  needed for valid assessment? Int J Sports Physiol Perform.
  2014;9(5):783-790.
- Robergs RA, Landwehr R. The surprising history of the "HRmax = 220 - age"
  equation. J Exerc Physiol Online. 2002;5(2):1-10.
- Sinnott RW. Virtues of the haversine. Sky Telesc. 1984;68(2):159.
- Tanaka H, Monahan KD, Seals DR. Age-predicted maximal heart rate revisited.
  J Am Coll Cardiol. 2001;37(1):153-156.
- Tudor-Locke C, Han H, Aguiar EJ, et al. How fast is fast enough? Walking
  cadence (steps/min) as a practical estimate of intensity in adults: a
  narrative review. Br J Sports Med. 2018;52(12):776-788.
- Walker J. The Hacker's Diet. 1991. Chapter "Signal and noise": the
  exponentially smoothed moving average with 10 percent smoothing.
- Watson NF, Badr MS, Belenky G, et al. Recommended amount of sleep for a
  healthy adult: a joint consensus statement of the American Academy of Sleep
  Medicine and Sleep Research Society. Sleep. 2015;38(6):843-844.
- Protocol slot sizes: `docs/protocols/realsil-colmi.md`, from Gadgetbridge
  `YawellRingPacketHandler` (heart rate, HRV, stress and SpO2 logs).
