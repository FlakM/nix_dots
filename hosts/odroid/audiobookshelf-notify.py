#!/usr/bin/env python3
"""Point Audiobookshelf notifications at the local Apprise API.

Runs from audiobookshelf.service's preStart hook, i.e. before ABS reads
notification settings out of its SQLite database. The update is idempotent:
it only rewrites the row when one of the managed fields drifted.

ABS requires every notification to carry at least one Apprise URL, so the
ntfy destination stays in the notification itself; the Apprise API acts as
the delivery/formatting backend (proper ntfy title/body instead of raw JSON).

ABS does not template `urls`, so the per-episode Storii play link is added by
abs-notify-relay.py. The episode body carries a hidden marker with the item and
episode IDs; the relay strips it and turns it into ntfy click/actions.
"""

import json
import os
import sqlite3
import sys
import time
import uuid

DB = os.environ.get(
    "ABS_DB", "/var/lib/audiobookshelf/config/absdatabase.sqlite"
)

TITLE_TEMPLATE = "New episode: {{episodeTitle}}"
# The HTML comment is consumed by abs-notify-relay.py and never reaches the
# phone; it is how the per-episode "Play" deep link survives ABS' lack of URL
# templating.
BODY_TEMPLATE = (
    "From {{podcastTitle}} ({{libraryName}})\n\n{{episodeDescription}}\n\n"
    "<!--storii:{{libraryItemId}}:{{episodeId}}-->"
)


def utcnow() -> str:
    # Match the format Sequelize writes to the settings table.
    return time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime()) + f".{int(time.time() * 1000) % 1000:03d} +00:00"


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: audiobookshelf-notify.py <relay-url> <ntfy-url>",
            file=sys.stderr,
        )
        return 2
    # ABS posts here instead of straight to Apprise: the relay adds the Storii
    # play button. See abs-notify-relay.py.
    relay_url, ntfy_url = sys.argv[1:3]

    # A fresh install has no database until ABS has started once; nothing to
    # migrate in that case.
    if not os.path.exists(DB):
        print(f"audiobookshelf-notify: {DB} does not exist yet, skipping")
        return 0

    db = sqlite3.connect(DB, timeout=30)
    db.execute("PRAGMA busy_timeout = 30000")

    try:
        row = db.execute(
            "SELECT value FROM settings WHERE key = 'notification-settings'"
        ).fetchone()
    except sqlite3.OperationalError as exc:
        print(f"audiobookshelf-notify: settings table not ready ({exc}), skipping")
        return 0

    if row is None:
        settings = {
            "id": "notification-settings",
            "appriseType": "api",
            "appriseApiUrl": relay_url,
            "notifications": [],
            "maxFailedAttempts": 5,
            "maxNotificationQueue": 20,
            "notificationDelay": 1000,
        }
    else:
        settings = json.loads(row[0])

    before = json.dumps(settings, sort_keys=True)

    settings["appriseType"] = "api"
    settings["appriseApiUrl"] = relay_url

    notifications = settings.setdefault("notifications", [])
    episodes = [
        n for n in notifications if n.get("eventName") == "onPodcastEpisodeDownloaded"
    ]
    if not episodes:
        episode = {
            "id": str(uuid.uuid4()),
            "libraryId": None,
            "eventName": "onPodcastEpisodeDownloaded",
            "titleTemplate": TITLE_TEMPLATE,
            "bodyTemplate": BODY_TEMPLATE,
            "type": "info",
            "enabled": True,
            "lastFiredAt": None,
            "lastAttemptFailed": False,
            "numConsecutiveFailedAttempts": 0,
            "numTimesFired": 0,
            "createdAt": int(time.time() * 1000),
        }
        notifications.append(episode)
        episodes = [episode]

    for note in episodes:
        note["urls"] = [ntfy_url]
        note["enabled"] = True
        note.setdefault("type", "info")
        note["titleTemplate"] = TITLE_TEMPLATE
        note["bodyTemplate"] = BODY_TEMPLATE

    if json.dumps(settings, sort_keys=True) == before:
        print("audiobookshelf-notify: notification settings already up to date")
        return 0

    now = utcnow()
    with db:
        if row is None:
            db.execute(
                "INSERT INTO settings (key, value, createdAt, updatedAt) VALUES (?, ?, ?, ?)",
                ("notification-settings", json.dumps(settings), now, now),
            )
        else:
            db.execute(
                "UPDATE settings SET value = ?, updatedAt = ? WHERE key = 'notification-settings'",
                (json.dumps(settings), now),
            )
    print(f"audiobookshelf-notify: notifications -> {relay_url} -> {ntfy_url}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
