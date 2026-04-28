#!/usr/bin/env python3
import sys
import json
import os
from datetime import date

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
            GarminConnectTooManyRequestsError,
            GarminConnectAuthenticationError,
            GarminConnectConnectionError,
        )
    except ImportError:
        print(json.dumps({"error": "garminconnect not installed"}))
        sys.exit(1)

    try:
        client = Garmin(email=email, password=password)
        client.login(tokenstore=tokenstore)

        today = date.today().isoformat()
        stats = client.get_stats(today)

        steps = stats.get("totalSteps") or 0
        goal = stats.get("dailyStepGoal") or 10000
        distance_m = stats.get("totalDistanceMeters") or 0
        kcal = stats.get("activeKilocalories") or 0

        print(json.dumps({
            "steps": int(steps),
            "goal": int(goal),
            "distance_km": round(distance_m / 1000, 2),
            "active_kcal": int(kcal),
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
