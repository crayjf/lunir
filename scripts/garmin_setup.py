#!/usr/bin/env python3
"""
One-time Garmin token setup.

Uses the web SSO endpoint (/sso/signin) which is NOT rate-limited, unlike
the mobile API endpoint (/mobile/api/login) that garth uses by default.
The browser login also goes through the web SSO, which is why browser logins
work even when the mobile endpoint is rate-limited.

Usage: python3 garmin_setup.py <email> <tokenstore_dir>
"""
import sys
import os
import re
import getpass
import requests


SERVICE_URL = "https://mobile.integration.garmin.com/gcm/android"
CLIENT_ID   = "GCM_ANDROID_DARK"
SSO_BASE    = "https://sso.garmin.com"
SSO_PARAMS  = {
    "service": SERVICE_URL,
    "clientId": CLIENT_ID,
    "locale": "en_US",
    "consumeServiceTicket": "false",
}
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) "
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Sec-Fetch-Mode": "navigate",
    "Sec-Fetch-Dest": "document",
}


def setup(email: str, password: str, tokenstore: str) -> None:
    from garth import sso as garth_sso
    from garth.http import Client as GarthClient

    sess = requests.Session()
    sess.headers.update(HEADERS)

    # 1. GET sign-in page — collect session cookies and CSRF token
    print("  Fetching sign-in page...")
    resp = sess.get(f"{SSO_BASE}/sso/signin", params=SSO_PARAMS, timeout=15)
    resp.raise_for_status()

    csrf_m = re.search(r'name=["\']_csrf["\']\s+value=["\']([^"\']+)["\']', resp.text)
    if not csrf_m:
        raise RuntimeError("CSRF token not found — Garmin may have changed their sign-in page.")
    csrf = csrf_m.group(1)

    # 2. POST credentials — response body embeds the service ticket in JS
    print("  Submitting credentials...")
    resp2 = sess.post(
        f"{SSO_BASE}/sso/signin",
        params=SSO_PARAMS,
        data={"username": email, "password": password, "_csrf": csrf, "embed": "false"},
        headers={"Referer": resp.url},
        allow_redirects=False,
        timeout=15,
    )

    # Ticket is in: var response_url = 'https://.../android?ticket=ST-...'
    url_m = re.search(r'var response_url\s*=\s*["\']([^"\']+)["\']', resp2.text)
    if not url_m:
        # Fallback: ticket in a redirect Location header
        loc = resp2.headers.get("Location", "")
        ticket_m = re.search(r"ticket=(ST-[^&\s]+)", loc)
        if not ticket_m:
            raise RuntimeError(
                f"Login failed — no service ticket in response.\n"
                f"Status: {resp2.status_code}, Location: {loc or '(none)'}\n"
                "Check credentials or whether Garmin requires MFA."
            )
        ticket = ticket_m.group(1)
    else:
        response_url = url_m.group(1).replace("&amp;", "&").replace("\\/", "/")
        ticket_m = re.search(r"ticket=(ST-[^&\s]+)", response_url)
        if not ticket_m:
            raise RuntimeError(f"No ticket in response_url: {response_url}")
        ticket = ticket_m.group(1)

    print(f"  Got ticket ({ticket[:15]}...)")

    # 3. Exchange SSO ticket for OAuth1 + OAuth2 tokens
    print("  Exchanging for OAuth tokens...")
    gc = GarthClient()
    oauth1 = garth_sso.get_oauth1_token(ticket, gc)
    oauth2 = garth_sso.exchange(oauth1, gc, login=True)
    gc.configure(oauth1_token=oauth1, oauth2_token=oauth2)

    os.makedirs(tokenstore, exist_ok=True)
    gc.dump(tokenstore)
    print(f"  Saved → {tokenstore}")
    print("Done. The module will refresh tokens via OAuth without hitting the login endpoint again.")


def main():
    if len(sys.argv) < 3:
        print("Usage: python3 garmin_setup.py <email> <tokenstore_dir>")
        sys.exit(1)

    email = sys.argv[1]
    tokenstore = os.path.expanduser(sys.argv[2])

    try:
        import garth  # noqa: F401
    except ImportError:
        print("Missing: pip install garth requests")
        sys.exit(1)

    password = getpass.getpass(f"Garmin password for {email}: ")

    try:
        setup(email, password, tokenstore)
    except Exception as e:
        print(f"Failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
