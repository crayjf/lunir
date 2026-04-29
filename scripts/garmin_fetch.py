#!/usr/bin/env python3
import json
import os
import sys
from datetime import date, timedelta


def _safe_int(value, default=0):
    try:
        if value is None:
            return default
        return int(value)
    except (TypeError, ValueError):
        return default


def _iso_days(end_day, count):
    return [(end_day - timedelta(days=offset)).isoformat() for offset in range(count)]


def _get_sleep_metrics(client, day):
    try:
        data = client.get_sleep_data(day) or {}
    except Exception:
        return None

    sleep = data.get("dailySleepDTO") or {}
    if not sleep:
        return None

    seconds = _safe_int(sleep.get("sleepTimeSeconds"))
    score = _safe_int((((sleep.get("sleepScores") or {}).get("overall") or {}).get("value")))
    if seconds <= 0 and score <= 0:
        return None

    return {
        "date": day,
        "sleepTimeSeconds": seconds,
        "sleepScore": score,
    }


def _get_sleep_need(client, day):
    try:
        data = client.get_sleep_data(day) or {}
    except Exception:
        return 0
    sleep = data.get("dailySleepDTO") or {}
    return _safe_int(sleep.get("sleepNeed"))


def _get_stats(client, day):
    try:
        return client.get_stats(day) or {}
    except Exception:
        return {}


def main():
    if len(sys.argv) < 4:
        print(json.dumps({"error": "usage: garmin_fetch.py <email> <password> <tokenstore>"}))
        sys.exit(1)

    email, password, tokenstore = sys.argv[1], sys.argv[2], sys.argv[3]

    # Never attempt fresh password login from auto-fetch — that hammers the SSO
    # endpoint and triggers Garmin's rate limit permanently. Run garmin_setup.py once.
    if not os.path.exists(os.path.join(tokenstore, "oauth1_token.json")):
        print(json.dumps({"error": "no_tokens"}))
        sys.exit(0)

    try:
        from garminconnect import (
            Garmin,
            GarminConnectAuthenticationError,
            GarminConnectConnectionError,
            GarminConnectTooManyRequestsError,
        )
    except ImportError:
        print(json.dumps({"error": "garminconnect not installed"}))
        sys.exit(1)

    try:
        client = Garmin(email=email, password=password)
        client.login(tokenstore=tokenstore)

        today_date = date.today()
        today = today_date.isoformat()
        last_7_days = _iso_days(today_date, 7)
        stats_by_day = {}

        for day in last_7_days:
            stats_by_day[day] = _get_stats(client, day)

        stats = stats_by_day.get(today, {})

        steps_7d = []
        for day in sorted(last_7_days):
            steps_7d.append({"date": day, "steps": _safe_int(stats_by_day.get(day, {}).get("totalSteps"))})

        stress_7d = []
        for day in last_7_days:
            stress_value = stats_by_day.get(day, {}).get("averageStressLevel")
            if stress_value is None:
                continue
            stress_7d.append({
                "date": day,
                "averageStressLevel": _safe_int(stress_value),
            })

        sleep_7d = []
        for day in last_7_days:
            sleep_metrics = _get_sleep_metrics(client, day)
            if sleep_metrics:
                sleep_7d.append(sleep_metrics)
        sleep_7d.sort(key=lambda item: item["date"], reverse=True)
        last_night = sleep_7d[0] if sleep_7d else None
        sleep_need_today = _get_sleep_need(client, today)

        vo2max = 0
        try:
            training_status = client.get_training_status(today) or {}
            vo2max = _safe_int(
                (((training_status.get("mostRecentVO2Max") or {}).get("generic") or {}).get("vo2MaxValue"))
            )
        except Exception:
            pass

        marathon_prediction = 0
        try:
            race_predictions = client.get_race_predictions() or {}
            marathon_prediction = _safe_int(race_predictions.get("timeMarathon"))
        except Exception:
            pass

        hrv_28d = []
        hrv_status = ""
        hrv_baseline_low = 0
        hrv_baseline_high = 0
        hrv_low_upper = 0
        for day in sorted(_iso_days(today_date, 28)):
            try:
                hrv_data = client.get_hrv_data(day) or {}
                summary = hrv_data.get("hrvSummary") or {}
                avg = _safe_int(summary.get("lastNightAvg"))
                if avg > 0:
                    hrv_28d.append({"date": day, "hrv": avg})
                if day == today:
                    if summary.get("status"):
                        hrv_status = summary["status"]
                    baseline = summary.get("baseline") or {}
                    hrv_baseline_low = _safe_int(baseline.get("balancedLow"))
                    hrv_baseline_high = _safe_int(baseline.get("balancedUpper"))
                    hrv_low_upper = _safe_int(baseline.get("lowUpper"))
            except Exception:
                pass

        endurance_score = 0
        endurance_classification = 0
        endurance_26w = []
        try:
            start_26w = (today_date - timedelta(weeks=26)).isoformat()
            endurance_data = client.get_endurance_score(start_26w, today) or {}
            dto = endurance_data.get("enduranceScoreDTO") or {}
            endurance_score = _safe_int(dto.get("overallScore"))
            endurance_classification = _safe_int(dto.get("classification"))
            for week_start in sorted((endurance_data.get("groupMap") or {}).keys()):
                entry = endurance_data["groupMap"][week_start]
                endurance_26w.append({"date": week_start, "score": _safe_int(entry.get("groupMax"))})
        except Exception:
            pass

        print(json.dumps({
            "hrv28Days": hrv_28d,
            "hrvStatus": hrv_status,
            "hrvBaselineLow": hrv_baseline_low,
            "hrvBaselineHigh": hrv_baseline_high,
            "hrvLowUpper": hrv_low_upper,
            "steps7Days": steps_7d,
            "restingHeartRate": _safe_int(stats.get("restingHeartRate")),
            "averageStressLevelToday": _safe_int(stats.get("averageStressLevel")),
            "averageStressLevel7Days": stress_7d,
            "lastNightSleep": last_night,
            "sleep7Days": sleep_7d,
            "sleepNeedToday": sleep_need_today,
            "vo2Max": vo2max,
            "marathonPredictionSeconds": marathon_prediction,
            "enduranceScore": endurance_score,
            "enduranceClassification": endurance_classification,
            "endurance26Weeks": endurance_26w,
        }))

    except GarminConnectTooManyRequestsError:
        print(json.dumps({"error": "rate_limited — retry later"}))
        sys.exit(0)
    except GarminConnectAuthenticationError as e:
        print(json.dumps({"error": f"auth failed: {e}"}))
        sys.exit(1)
    except GarminConnectConnectionError as e:
        msg = str(e)
        if "429" in msg or "Too Many Requests" in msg:
            print(json.dumps({"error": "rate_limited — retry later"}))
            sys.exit(0)
        print(json.dumps({"error": f"connection error: {msg}"}))
        sys.exit(1)
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
