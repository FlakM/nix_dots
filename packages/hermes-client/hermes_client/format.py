"""Display helpers shared by the CLI, TUI and bridge.

The API returns a superset of fields depending on how far ``tracking.describe``
has evolved; every accessor here is defensive and falls back to ``-`` instead
of raising, because a desktop client must never break on a new payload.
"""

from __future__ import annotations

import re
import time
from typing import Any

def as_float(value: Any) -> float | None:
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return None
    return None


def fmt_duration(seconds: float | None) -> str:
    """Compact age/cadence: ``now``, ``12m``, ``5h``, ``3d``, ``2w``."""
    if seconds is None:
        return "-"
    seconds = max(0.0, float(seconds))
    if seconds < 60:
        return "now"
    minutes = seconds / 60
    if minutes < 60:
        return f"{int(minutes)}m"
    hours = minutes / 60
    if hours < 24:
        return f"{int(hours)}h"
    days = hours / 24
    if days < 14:
        return f"{int(days)}d"
    return f"{int(days / 7)}w"


def fmt_epoch(ts: float | None) -> str:
    if not ts:
        return "-"
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(ts))


def cadence_text(value: Any, default: str = "-") -> str:
    """Render a cadence that may be a label, seconds, or ``{seconds,label}``."""
    if isinstance(value, dict):
        label = value.get("label") or value.get("cadence_label")
        if label:
            return str(label)
        seconds = value.get("seconds")
        if isinstance(seconds, (int, float)):
            return "activity" if seconds <= 0 else fmt_duration(seconds)
        return default
    if isinstance(value, (int, float)):
        return "activity" if value <= 0 else fmt_duration(value)
    if value not in (None, ""):
        return str(value)
    return default


def thread_view(thread: dict[str, Any]) -> dict[str, Any]:
    """Normalise one API thread into the flat shape the UI renders."""
    item = thread
    if isinstance(thread.get("item"), dict):
        item = {**thread["item"], **{k: v for k, v in thread.items() if k != "item"}}
    key = str(item.get("key") or thread.get("key") or "")

    summary = (
        item.get("summary")
        or item.get("title")
        or item.get("subject")
        or item.get("root_text")
        or key
    )
    summary = " ".join(str(summary).split())

    reminder = item.get("reminder") if isinstance(item.get("reminder"), dict) else {}
    cadence = (
        item.get("cadence_label")
        or reminder.get("cadence_label")
        or item.get("cadence")
        or reminder.get("interval")
    )
    if isinstance(cadence, (int, float)):
        cadence = "activity" if cadence <= 0 else fmt_duration(cadence)
    cadence = str(cadence) if cadence not in (None, "") else "-"

    idle = as_float(item.get("idle_seconds"))
    last_activity = (
        as_float(item.get("last_activity"))
        or as_float(item.get("last_activity_ts"))
        or as_float(item.get("latest_ts"))
        or as_float(item.get("updated"))
        or as_float(item.get("last_active"))
    )
    if idle is None and last_activity:
        idle = max(0.0, time.time() - last_activity)

    status = str(item.get("status") or item.get("state") or "").strip()
    waiting_flag = item.get("waiting_on_you", item.get("waiting"))
    if waiting_flag is None:
        waiting = status.lower() in {
            "waiting",
            "waiting on you",
            "needs reply",
            "needs_reply",
            "action required",
        }
    else:
        waiting = bool(waiting_flag)

    priority = item.get("priority")
    if isinstance(priority, (int, float)):
        priority_label = f"P{int(priority)}" if int(priority) > 0 else "-"
    elif priority:
        priority_label = str(priority).upper()
    else:
        priority_label = "-"

    return {
        "key": key,
        "summary": summary,
        "link": item.get("link") or item.get("url") or "",
        "kind": str(item.get("kind") or "slack"),
        "status": status,
        "priority": priority if isinstance(priority, (int, float)) else 0,
        "priority_label": priority_label,
        "importance": bool(item.get("important")),
        "cadence": cadence,
        "age_seconds": idle,
        "age": fmt_duration(idle),
        "waiting": bool(waiting),
        "done": bool(item.get("done")),
        "followed": item.get("followed", True) is not False,
        "snoozed": bool(item.get("snoozed") or item.get("snooze")),
        "note": str(item.get("note") or ""),
        "channel_name": str(item.get("channel_name") or ""),
        "root_author": str(item.get("root_author") or ""),
        "raw": item,
    }


def parse_duration(value: str) -> int | None:
    """``1d``/``6h``/``30m``/``90s``/``2w`` -> seconds; ``off`` -> 0.

    ``None`` means "use the default".  Raises ``ValueError`` on nonsense.
    """
    text = str(value).strip().lower()
    if text in {"off", "never", "none"}:
        return 0
    if text in {"default", "auto"}:
        return None
    match = re.fullmatch(r"(\d+)\s*([smhdw])", text)
    if not match:
        if text.isdigit():
            return int(text)
        raise ValueError(f"not a duration: {value!r} (try 1d, 6h, off)")
    amount = int(match.group(1))
    unit = match.group(2)
    factor = {"s": 1, "m": 60, "h": 3600, "d": 86400, "w": 604800}[unit]
    return amount * factor


def duration_label(value: str) -> str:
    """Normalise a user cadence to the label the server displays."""
    seconds = parse_duration(value)
    if seconds is None:
        return "default"
    if seconds == 0:
        return "off"
    return fmt_duration(seconds)


def job_status(job: dict[str, Any]) -> str:
    status = str(job.get("status") or "unknown").lower()
    return status or "unknown"


def job_title(job: dict[str, Any]) -> str:
    return " ".join(
        str(job.get("title") or job.get("question") or job.get("label") or "job").split()
    )


def job_steps(job: dict[str, Any]) -> list[dict[str, Any]]:
    steps = job.get("steps")
    if not isinstance(steps, list):
        return []
    return [step for step in steps if isinstance(step, dict)]


def step_line(step: dict[str, Any]) -> str:
    label = " ".join(str(step.get("label") or step.get("message") or "").split())
    detail = " ".join(str(step.get("detail") or "").split())
    if label and detail:
        return f"{label} — {detail}"
    return label or detail or "(step)"


def urgency(value: Any) -> str:
    text = str(value or "normal").lower()
    return text if text in {"low", "normal", "critical"} else "normal"


def event_title(event: dict[str, Any]) -> str:
    payload = event.get("payload") if isinstance(event.get("payload"), dict) else {}
    kind = str(event.get("type") or "")
    if kind == "notify":
        return str(payload.get("title") or "Hermes")
    if kind == "reminder":
        return "⏰ Still waiting"
    if kind == "thread.update":
        return str(payload.get("summary") or payload.get("key") or "Thread updated")
    if kind == "job.done":
        return "Job finished" if payload.get("ok", True) else "Job failed"
    if kind == "job.step":
        return str(payload.get("label") or "Job step")
    return kind or "event"


def event_body(event: dict[str, Any]) -> str:
    payload = event.get("payload") if isinstance(event.get("payload"), dict) else {}
    kind = str(event.get("type") or "")
    if kind == "notify":
        body = str(payload.get("body") or payload.get("message") or "")
    elif kind == "reminder":
        body = str(payload.get("summary") or "")
        idle = as_float(payload.get("idle_seconds"))
        if idle is not None:
            body = f"{body} (last activity {fmt_duration(idle)} ago)".strip()
    elif kind == "thread.update":
        body = str(payload.get("summary") or payload.get("key") or "")
    elif kind == "job.done":
        body = str(payload.get("result") or payload.get("error") or "")
    else:
        body = str(payload.get("detail") or payload.get("message") or "")
    link = payload.get("link")
    if link and str(link) not in body:
        body = f"{body} — {link}".strip()
    return body
