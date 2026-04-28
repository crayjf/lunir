# Garmin Connect — Available Data Fields

All fields verified against a live account via `garminconnect` + `garth`.
Fetched with `client.login(tokenstore=...)` (no SSO hit after initial setup).

---

## Activity & Movement — `get_stats(date)`

| Field | Description |
|---|---|
| `totalSteps` / `dailyStepGoal` | Steps taken + daily goal |
| `totalDistanceMeters` | Total distance walked/run |
| `activeKilocalories` / `totalKilocalories` / `bmrKilocalories` | Active burn, total burn, basal metabolic rate |
| `highlyActiveSeconds` / `activeSeconds` / `sedentarySeconds` / `sleepingSeconds` | Time breakdown by activity level |
| `moderateIntensityMinutes` / `vigorousIntensityMinutes` | Weekly intensity minute accumulation |
| `floorsAscended` / `floorsDescended` (+ `…InMeters`) | Floors climbed |

---

## Heart Rate — `get_stats(date)`, `get_heart_rates(date)`

| Field | Description |
|---|---|
| `restingHeartRate` / `lastSevenDaysAvgRestingHeartRate` | Resting HR today + 7-day avg |
| `minHeartRate` / `maxHeartRate` | Day min/max |
| `heartRateValues` | Full time-series `[timestamp_ms, bpm]` every ~2 min |

---

## Body Battery — `get_stats(date)`, `get_body_battery(date, date)`

| Field | Description |
|---|---|
| `bodyBatteryHighestValue` / `bodyBatteryLowestValue` / `bodyBatteryMostRecentValue` | Day high / low / current |
| `bodyBatteryChargedValue` / `bodyBatteryDrainedValue` | Net charged and drained |
| `bodyBatteryAtWakeTime` / `bodyBatteryDuringSleep` | Level at wake-up + sleep behavior |
| `bodyBatteryValuesArray` | Full time-series `[timestamp_ms, level]` |

---

## Stress — `get_stats(date)`, `get_stress_data(date)`

| Field | Description |
|---|---|
| `averageStressLevel` / `maxStressLevel` | Day average + peak (0–100) |
| `stressQualifier` | e.g. `CALM`, `BALANCED`, `STRESSFUL` |
| `lowStressDuration` / `mediumStressDuration` / `highStressDuration` / `restStressDuration` | Seconds at each tier |
| `stressValuesArray` | Full time-series `[timestamp_ms, level]` every ~3 min |

---

## Sleep — `get_sleep_data(date)`

Response root: `data["dailySleepDTO"]`

| Field | Description |
|---|---|
| `sleepTimeSeconds` / `napTimeSeconds` | Total sleep + nap duration |
| `deepSleepSeconds` / `lightSleepSeconds` / `remSleepSeconds` / `awakeSleepSeconds` | Sleep stage breakdown |
| `awakeCount` | Number of wake events |
| `avgSleepStress` / `avgHeartRate` | Stress and HR during sleep |
| `averageRespirationValue` / `lowestRespirationValue` / `highestRespirationValue` | Breathing rate (breaths/min) |
| `sleepScores.overall.value` | Overall sleep score (0–100) |
| `sleepScores.overall.qualifierKey` | `POOR` / `FAIR` / `GOOD` / `EXCELLENT` |
| `sleepScores.remPercentage.value` / `.qualifierKey` | REM % + rating |
| `sleepScores.deepPercentage.value` / `.qualifierKey` | Deep sleep % + rating |
| `sleepScores.lightPercentage.value` / `.qualifierKey` | Light sleep % + rating |
| `sleepScores.stress.qualifierKey` | Sleep stress rating |
| `sleepScores.awakeCount.qualifierKey` | Wake disruption rating |
| `sleepScoreFeedback` | Feedback key, e.g. `NEGATIVE_LONG_BUT_NOT_ENOUGH_REM` |
| `sleepNeed` / `nextSleepNeed` | Recommended sleep duration tonight (seconds) |

---

## HRV — `get_hrv_data(date)`

Response root: `data["hrvSummary"]`

| Field | Description |
|---|---|
| `lastNightAvg` / `weeklyAvg` | HRV last night + 7-day avg (ms) |
| `lastNight5MinHigh` | Peak 5-min HRV reading |
| `status` | `BALANCED`, `UNBALANCED`, `LOW` |
| `feedbackPhrase` | e.g. `HRV_BALANCED_2` |
| `baseline.balancedLow` / `balancedUpper` / `lowUpper` | Personal baseline range |
| `data["hrvReadings"]` | List of `{hrvValue, readingTimeLocal}` every 5 min during sleep |

---

## Respiration & SpO2 — `get_respiration_data(date)`, `get_spo2_data(date)`

| Field | Description |
|---|---|
| `avgSleepRespirationValue` / `avgWakingRespirationValue` | Breaths/min asleep vs awake |
| `lowestRespirationValue` / `highestRespirationValue` | Day extremes |
| `respirationValuesArray` | Full time-series `[timestamp_ms, breaths/min]` |
| `averageSpO2` / `lowestSpO2` / `avgSleepSpO2` | Blood oxygen % — **null if device doesn't measure it** |

---

## Training Readiness — `get_training_readiness(date)`

Returns a list; use `[0]`.

| Field | Description |
|---|---|
| `score` | 0–100 readiness score |
| `level` | `POOR` / `FAIR` / `GOOD` / `PRIME` |
| `feedbackShort` / `feedbackLong` | Advice keys, e.g. `LET_YOUR_BODY_RECOVER` |
| `sleepScore` / `sleepScoreFactorPercent` | Sleep contribution |
| `recoveryTime` | Minutes of recovery time remaining |
| `recoveryTimeFactorPercent` | Recovery time contribution |
| `acuteLoad` / `acwrFactorPercent` | Acute training load + load ratio impact |
| `stressHistoryFactorPercent` | Stress history impact |
| `hrvFactorPercent` / `hrvWeeklyAverage` | HRV contribution + weekly avg |
| `sleepHistoryFactorPercent` | Sleep trend contribution |

---

## Training Status & VO₂ Max — `get_training_status(date)`

| Field | Description |
|---|---|
| `mostRecentVO2Max.generic.vo2MaxValue` | VO₂ max (integer) |
| `mostRecentVO2Max.generic.vo2MaxPreciseValue` | VO₂ max (float) |
| `mostRecentVO2Max.generic.calendarDate` | Date of last measurement |
| `mostRecentTrainingLoadBalance` | Training load breakdown by device |

---

## Performance & Fitness

### `get_fitnessage_data(date)`
| Field | Description |
|---|---|
| `fitnessAge` / `chronologicalAge` | Fitness age vs real age |
| `achievableFitnessAge` | Best achievable fitness age |
| `components.vigorousMinutesAvg.value` | Avg vigorous minutes/week |
| `components.rhr.value` | Resting HR used in calculation |
| `components.bmi.value` | BMI used in calculation |

### `get_endurance_score(date, date)`
| Field | Description |
|---|---|
| `enduranceScoreDTO.overallScore` | Endurance score (raw) |
| `enduranceScoreDTO.classification` | Tier: 0=Untrained … 6=Elite |
| Tier thresholds | `gaugeLowerLimit`, `classificationLowerLimit{Intermediate,Trained,WellTrained,Expert,Superior,Elite}` |

### `get_race_predictions()`
| Field | Description |
|---|---|
| `time5K` / `time10K` / `timeHalfMarathon` / `timeMarathon` | Predicted finish times in **seconds** |

---

## Last Activity — `get_last_activity()`

| Field | Description |
|---|---|
| `activityName` / `activityType.typeKey` | Name + type key, e.g. `trail_running` |
| `distance` | Meters |
| `duration` / `movingDuration` / `elapsedDuration` | Total, moving, elapsed time (seconds) |
| `elevationGain` / `elevationLoss` | Elevation in meters |
| `averageSpeed` / `maxSpeed` | m/s |
| `startTimeLocal` | Local start time string |

Full activity list: `get_activities_by_date(start, end)` — returns list with same fields.

---

## Personal Records — `get_personal_record()`

Returns a list. Each entry:

| Field | Description |
|---|---|
| `activityType` | e.g. `trail_running` |
| `activityName` | Name of the activity where PR was set |
| `value` | PR value (distance in meters, time in ms — depends on type) |
| `actStartDateTimeInGMTFormatted` | When it was set |

---

## Not Available Without Hardware

| Data | Requires |
|---|---|
| `weight`, `bodyFat`, `muscleMass`, `bmi`, `bodyWater` | Garmin Index scale or manual log |
| `averageSpO2`, `lowestSpO2` | Device with pulse ox (e.g. Fenix, Epix) |
| `cyclingVO2Max` | Cycling power meter |

---

## Timeseries Note

HR, stress, body battery, and respiration all return full intraday arrays as `[timestamp_ms, value]` pairs.
Useful for sparklines or graphs in the widget.

---

## Auth Note

Tokens stored at `Quickshell.dataPath("garmin-tokens")` — currently:
`~/.local/share/quickshell/by-shell/7d7c040b76f85ab30b067dedf7cf4ff5/garmin-tokens/`

If tokens ever expire, re-run:
```
python3 scripts/garmin_setup.py <email> <tokenstore_path>
```
Uses web SSO (`/sso/signin`) — not the rate-limited mobile endpoint.
