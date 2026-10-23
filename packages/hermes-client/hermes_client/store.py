"""The bridge cache that quickshell reads.

``~/.cache/hermes/bridge.json`` is written atomically (tmp file + rename) so
the QML ``FileView`` never observes a half-written document::

    {
      "unread": 3,
      "events": [ {id, type, ts, title, body, key, link}, ... last 20 ],
      "jobs":   [ {id, status, title, steps[], started, updated, result, error} ],
      "threads":[ normalised tracked threads for the panel ],
      "connection": {"connected": true, "error": null},
      "updated": 1729600000.0
    }

``threads`` is an addition to the shape in PLATFORM.md: the quickshell panel
has to render tracked threads and the bridge is the only process talking to the
API, so it publishes the list it already fetches.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any

from .config import cache_dir

BRIDGE_FILE = "bridge.json"
LAST_EVENT_ID_FILE = "last-event-id"
MAX_EVENTS = 20
MAX_JOBS = 10
MAX_THREADS = 30


def bridge_path() -> Path:
    return cache_dir() / BRIDGE_FILE


def last_event_id_path() -> Path:
    return cache_dir() / LAST_EVENT_ID_FILE


def ensure_cache_dir() -> Path:
    directory = cache_dir()
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def load_json(path: Path, default: Any) -> Any:
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError):
        return default


def atomic_write_json(path: Path, payload: Any) -> None:
    """Write JSON via ``path.tmp`` + ``os.replace``, preserving mode 0600."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    data = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            try:
                tmp.unlink()
            except OSError:
                pass


def empty_bridge() -> dict[str, Any]:
    return {
        "unread": 0,
        "events": [],
        "jobs": [],
        "threads": [],
        "connection": {"connected": False, "error": "bridge not running"},
        "updated": time.time(),
    }


def load_bridge() -> dict[str, Any]:
    data = load_json(bridge_path(), {})
    bridge = empty_bridge()
    if isinstance(data, dict):
        bridge.update({key: value for key, value in data.items() if value is not None})
    for key, fallback in (
        ("unread", 0),
        ("events", []),
        ("jobs", []),
        ("threads", []),
        ("connection", {"connected": False, "error": None}),
    ):
        if not isinstance(bridge.get(key), type(fallback)):
            bridge[key] = fallback
    bridge["unread"] = int(bridge.get("unread") or 0)
    return bridge


def write_bridge(bridge: dict[str, Any]) -> None:
    ensure_cache_dir()
    bridge["updated"] = time.time()
    bridge["events"] = list(bridge.get("events") or [])[:MAX_EVENTS]
    bridge["jobs"] = list(bridge.get("jobs") or [])[:MAX_JOBS]
    bridge["threads"] = list(bridge.get("threads") or [])[:MAX_THREADS]
    atomic_write_json(bridge_path(), bridge)


def mark_read() -> dict[str, Any]:
    """Clear the unread badge (called by ``hermes read`` and the panel)."""
    bridge = load_bridge()
    bridge["unread"] = 0
    write_bridge(bridge)
    return bridge


def load_last_event_id() -> int | None:
    try:
        text = last_event_id_path().read_text(encoding="utf-8").strip()
    except OSError:
        return None
    try:
        return int(float(text))
    except ValueError:
        return None


def save_last_event_id(event_id: int) -> None:
    ensure_cache_dir()
    path = last_event_id_path()
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(f"{int(event_id)}\n", encoding="utf-8")
    os.replace(tmp, path)
