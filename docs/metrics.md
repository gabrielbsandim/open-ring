# Metrics

Every number OpenRing derives from ring samples, with its formula, constants,
inputs, minimum data rule and sources. The code lives in `packages/metrics`
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
| `minSamples` (parameter default) | 3 | **our choice**. The heart rate log reports its slot length. The app sets the ring to 5 min on every sync (`plan.md` decisions), so a 30 min window holds 6 samples and 3 tolerates missed slots. At a 30 min slot no window can reach 3 samples and there is no value. |

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

## References

- Ainsworth BE, Haskell WL, Herrmann SD, et al. 2011 Compendium of Physical
  Activities: a second update of codes and MET values. Med Sci Sports Exerc.
  2011;43(8):1575-1581.
- Azarbarzin A, Sands SA, Stone KL, et al. The hypoxic burden of sleep apnoea
  predicts cardiovascular disease-related mortality: the Osteoporotic Fractures
  in Men Study and the Sleep Heart Health Study. Eur Heart J.
  2019;40(14):1149-1157.
- Buchheit M. Monitoring training status with HR measures: do all roads lead to
  Rome? Front Physiol. 2014;5:73.
- Fox SM, Naughton JP, Haskell WL. Physical activity and the prevention of
  coronary heart disease. Ann Clin Res. 1971;3(6):404-432.
- Gabbett TJ. The training-injury prevention paradox: should athletes be
  training smarter and harder? Br J Sports Med. 2016;50(5):273-280.
- Herrmann SD, Willis EA, Ainsworth BE, et al. 2024 Adult Compendium of
  Physical Activities: a third update of the energy costs of human activities.
  J Sport Health Sci. 2024;13(1):6-12.
- Hirshkowitz M, Whiton K, Albert SM, et al. National Sleep Foundation's sleep
  time duration recommendations: methodology and results summary. Sleep Health.
  2015;1(1):40-43.
- Impellizzeri FM, Tenan MS, Kempton T, Novak A, Coutts AJ. Acute:chronic
  workload ratio: conceptual issues and fundamental pitfalls. Int J Sports
  Physiol Perform. 2020;15(6):907-913.
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
- Watson NF, Badr MS, Belenky G, et al. Recommended amount of sleep for a
  healthy adult: a joint consensus statement of the American Academy of Sleep
  Medicine and Sleep Research Society. Sleep. 2015;38(6):843-844.
- Protocol slot sizes: `docs/protocols/realsil-colmi.md`, from Gadgetbridge
  `YawellRingPacketHandler` (heart rate, HRV, stress and SpO2 logs).
