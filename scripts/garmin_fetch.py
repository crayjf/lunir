#!/usr/bin/env python3
import json
import os
import sys
from datetime import date, timedelta
from pathlib import Path


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


def _get_sleep_data(client, day):
    try:
        return client.get_sleep_data(day) or {}
    except Exception:
        return {}


def _get_stats(client, day):
    try:
        return client.get_stats(day) or {}
    except Exception:
        return {}


def _get_steps_range(client, start_day, end_day):
    try:
        data = client.get_daily_steps(start_day, end_day) or []
    except Exception:
        return {}

    steps_by_day = {}
    for entry in data:
        day = entry.get("calendarDate")
        if not day:
            continue
        steps_by_day[day] = _safe_int(entry.get("totalSteps"))
    return steps_by_day


def _resolve_tokenstore(tokenstore):
    direct = Path(tokenstore).expanduser()
    if (direct / "oauth1_token.json").exists():
        return str(direct)

    quickshell_root = Path.home() / ".local" / "share" / "quickshell"
    if quickshell_root.exists():
        matches = sorted(quickshell_root.rglob("oauth1_token.json"))
        if matches:
            return str(matches[0].parent)

    return str(direct)


def _load_cached_payload(cache_path):
    if not cache_path:
        return {}
    try:
        with open(Path(cache_path).expanduser(), "r", encoding="utf-8") as handle:
            data = json.load(handle)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _by_date(items):
    data = {}
    for item in items or []:
        day = item.get("date") if isinstance(item, dict) else None
        if day:
            data[day] = item
    return data


def _merge_series(days, cached_items, fresh_items):
    merged = _by_date(cached_items)
    merged.update(_by_date(fresh_items))
    return [merged[day] for day in days if day in merged]


def _merge_dated_items(cached_items, fresh_items):
    merged = _by_date(cached_items)
    merged.update(_by_date(fresh_items))
    return [merged[day] for day in sorted(merged.keys())]


def _latest_cached_day(cached_by_day, allowed_days, before_day=""):
    return max(
        (
            day for day in cached_by_day.keys()
            if day in allowed_days and (not before_day or day < before_day)
        ),
        default="",
    )


def _format_activity(act):
    type_key = (act.get("activityType") or {}).get("typeKey", "")
    start = act.get("startTimeLocal", "")
    return {
        "activityId": _safe_int(act.get("activityId")),
        "type": type_key,
        "date": start[:10] if start else "",
        "startedAt": start,
        "name": act.get("activityName", ""),
        "distance": float(act.get("distance") or 0),
        "duration": _safe_int(act.get("duration")),
        "averageHR": _safe_int(act.get("averageHR")),
        "calories": _safe_int(act.get("calories")),
        "elevationGain": round(float(act.get("elevationGain") or 0)),
        "elevationLoss": abs(round(float(act.get("elevationLoss") or 0))),
        "averageSpeed": float(act.get("averageSpeed") or 0),
    }


def _activity_sort_key(item):
    started_at = item.get("startedAt") if isinstance(item, dict) else ""
    day = item.get("date") if isinstance(item, dict) else ""
    return started_at or day or ""


def _merge_activities(cached_items, fresh_items, limit=3):
    merged = {}
    for item in cached_items or []:
        if not isinstance(item, dict):
            continue
        key = item.get("activityId") or _activity_sort_key(item) + "|" + str(item.get("type") or "")
        merged[key] = item
    for item in fresh_items or []:
        if not isinstance(item, dict):
            continue
        key = item.get("activityId") or _activity_sort_key(item) + "|" + str(item.get("type") or "")
        merged[key] = item
    items = sorted(merged.values(), key=_activity_sort_key, reverse=True)
    return items[:limit]


def main():
    if len(sys.argv) < 4:
        print(json.dumps({"error": "usage: garmin_fetch.py <email> <password> <tokenstore>"}))
        sys.exit(1)

    email, password, tokenstore = sys.argv[1], sys.argv[2], sys.argv[3]
    mode = sys.argv[4] if len(sys.argv) > 4 else "full"
    cache_path = sys.argv[5] if len(sys.argv) > 5 else ""
    light_mode = mode == "light"
    tokenstore = _resolve_tokenstore(tokenstore)
    cached = _load_cached_payload(cache_path)

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
        sorted_last_7_days = sorted(last_7_days)
        cached_recent_activities = list(cached.get("recentActivities") or [])

        cached_steps = _by_date(cached.get("steps7Days"))
        latest_cached_step_before_today = _latest_cached_day(
            cached_steps,
            sorted_last_7_days,
            before_day=today,
        )
        step_days_to_fetch = [
            day for day in sorted_last_7_days
            if day == today or day not in cached_steps
        ]
        if latest_cached_step_before_today:
            step_days_to_fetch.append(latest_cached_step_before_today)
        step_days_to_fetch = sorted(set(step_days_to_fetch))
        steps_7d = list(cached.get("steps7Days") or [])
        if step_days_to_fetch:
            steps_by_day = _get_steps_range(client, min(step_days_to_fetch), max(step_days_to_fetch))
            fresh_steps = []
            for day in sorted_last_7_days:
                if day in steps_by_day:
                    fresh_steps.append({"date": day, "steps": steps_by_day.get(day, 0)})
            steps_7d = _merge_series(sorted_last_7_days, cached.get("steps7Days"), fresh_steps)

        recent_activities = cached_recent_activities
        try:
            newest_cached_activity_date = ""
            for item in cached_recent_activities:
                if not isinstance(item, dict):
                    continue
                newest_cached_activity_date = max(newest_cached_activity_date, str(item.get("date") or ""))

            if newest_cached_activity_date:
                acts = client.get_activities_by_date(newest_cached_activity_date, today, sortorder="asc") or []
                recent_activities = _merge_activities(cached_recent_activities, [_format_activity(act) for act in acts])
            else:
                acts = client.get_activities(0, 3) or []
                recent_activities = [_format_activity(act) for act in acts][:3]
        except Exception:
            pass

        if light_mode:
            print(json.dumps({
                "steps7Days": steps_7d,
                "recentActivities": recent_activities,
            }))
            sys.exit(0)

        cached_stress = _by_date(cached.get("averageStressLevel7Days"))
        stats_by_day = {}
        stats_days_to_fetch = [
            day for day in sorted_last_7_days
            if day == today or day not in cached_stress
        ]
        for day in stats_days_to_fetch:
            stats_by_day[day] = _get_stats(client, day)

        stats = stats_by_day.get(today, {})

        fresh_stress = []
        for day, day_stats in stats_by_day.items():
            stress_value = day_stats.get("averageStressLevel")
            if stress_value is None:
                continue
            fresh_stress.append({
                "date": day,
                "averageStressLevel": _safe_int(stress_value),
            })
        stress_7d = _merge_series(sorted_last_7_days, cached.get("averageStressLevel7Days"), fresh_stress)

        cached_sleep = _by_date(cached.get("sleep7Days"))
        sleep_days_to_fetch = [
            day for day in sorted_last_7_days
            if day == today or day not in cached_sleep
        ]
        fresh_sleep = []
        sleep_need_today = 0
        for day in sleep_days_to_fetch:
            sleep_metrics = _get_sleep_metrics(client, day)
            if sleep_metrics:
                fresh_sleep.append(sleep_metrics)
            if day == today:
                sleep_data = _get_sleep_data(client, day)
                sleep = sleep_data.get("dailySleepDTO") or {}
                sleep_need_today = _safe_int(sleep.get("sleepNeed"))
        sleep_7d = _merge_series(sorted_last_7_days, cached.get("sleep7Days"), fresh_sleep)
        sleep_7d.sort(key=lambda item: item["date"], reverse=True)
        last_night = sleep_7d[0] if sleep_7d else None
        if sleep_need_today <= 0:
            sleep_need_today = _safe_int(cached.get("sleepNeedToday"))

        vo2max = _safe_int(cached.get("vo2Max"))
        try:
            training_status = client.get_training_status(today) or {}
            vo2max = _safe_int(
                (((training_status.get("mostRecentVO2Max") or {}).get("generic") or {}).get("vo2MaxValue"))
            )
        except Exception:
            pass

        marathon_prediction = _safe_int(cached.get("marathonPredictionSeconds"))
        try:
            race_predictions = client.get_race_predictions() or {}
            marathon_prediction = _safe_int(race_predictions.get("timeMarathon"))
        except Exception:
            pass

        cached_hrv = _by_date(cached.get("hrv28Days"))
        hrv_window = sorted(_iso_days(today_date, 28))
        hrv_28d = []
        hrv_status = str(cached.get("hrvStatus") or "")
        hrv_baseline_low = _safe_int(cached.get("hrvBaselineLow"))
        hrv_baseline_high = _safe_int(cached.get("hrvBaselineHigh"))
        hrv_low_upper = _safe_int(cached.get("hrvLowUpper"))
        hrv_weekly_avg = _safe_int(cached.get("hrvWeeklyAvg"))
        fresh_hrv = []
        hrv_days_to_fetch = [day for day in hrv_window if day == today or day not in cached_hrv]
        for day in hrv_days_to_fetch:
            try:
                hrv_data = client.get_hrv_data(day) or {}
                summary = hrv_data.get("hrvSummary") or {}
                avg = _safe_int(summary.get("lastNightAvg"))
                if avg > 0:
                    fresh_hrv.append({"date": day, "hrv": avg})
                if day == today:
                    if summary.get("status"):
                        hrv_status = summary["status"]
                    baseline = summary.get("baseline") or {}
                    hrv_baseline_low = _safe_int(baseline.get("balancedLow"))
                    hrv_baseline_high = _safe_int(baseline.get("balancedUpper"))
                    hrv_low_upper = _safe_int(baseline.get("lowUpper"))
                    hrv_weekly_avg = _safe_int(summary.get("weeklyAvg"))
            except Exception:
                pass
        hrv_28d = _merge_series(hrv_window, cached.get("hrv28Days"), fresh_hrv)

        endurance_score = _safe_int(cached.get("enduranceScore"))
        endurance_classification = _safe_int(cached.get("enduranceClassification"))
        endurance_26w = list(cached.get("endurance26Weeks") or [])
        try:
            start_26w = (today_date - timedelta(weeks=26)).isoformat()
            if endurance_26w:
                latest_cached_week = ""
                for item in endurance_26w:
                    if not isinstance(item, dict):
                        continue
                    latest_cached_week = max(latest_cached_week, str(item.get("date") or ""))
                start_26w = latest_cached_week or start_26w
            endurance_data = client.get_endurance_score(start_26w, today) or {}
            dto = endurance_data.get("enduranceScoreDTO") or {}
            endurance_score = _safe_int(dto.get("overallScore"))
            endurance_classification = _safe_int(dto.get("classification"))
            fresh_endurance = []
            for week_start in sorted((endurance_data.get("groupMap") or {}).keys()):
                entry = endurance_data["groupMap"][week_start]
                fresh_endurance.append({"date": week_start, "score": _safe_int(entry.get("groupMax"))})
            endurance_26w = _merge_dated_items(cached.get("endurance26Weeks"), fresh_endurance)
        except Exception:
            pass

        print(json.dumps({
            "hrv28Days": hrv_28d,
            "hrvStatus": hrv_status,
            "hrvBaselineLow": hrv_baseline_low,
            "hrvBaselineHigh": hrv_baseline_high,
            "hrvLowUpper": hrv_low_upper,
            "hrvWeeklyAvg": hrv_weekly_avg,
            "steps7Days": steps_7d,
            "restingHeartRate": _safe_int(stats.get("restingHeartRate"), _safe_int(cached.get("restingHeartRate"))),
            "averageStressLevelToday": _safe_int(stats.get("averageStressLevel"), _safe_int(cached.get("averageStressLevelToday"))),
            "averageStressLevel7Days": stress_7d,
            "lastNightSleep": last_night,
            "sleep7Days": sleep_7d,
            "sleepNeedToday": sleep_need_today,
            "vo2Max": vo2max,
            "marathonPredictionSeconds": marathon_prediction,
            "enduranceScore": endurance_score,
            "enduranceClassification": endurance_classification,
            "endurance26Weeks": endurance_26w,
            "recentActivities": recent_activities,
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
