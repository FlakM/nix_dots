"""Command surface shared by the CLI helpers and programmatic callers.

The words are the Slack control surface from PLATFORM.md, so muscle memory
carries over between Slack, ``hermes`` and ``hermes-tui``.  The Rust TUI in
``packages/hermes-tui`` mirrors these verbs in its command bar;
``run_command`` remains here for scripts and tests.  It is pure apart from the
API calls: it returns a :class:`Result`, never touches a UI, and converts every
exception into a readable line.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any

from .client import HermesClient, HermesError
from .format import cadence_text, duration_label, fmt_duration, parse_duration, thread_view

SLACK_URL_RE = re.compile(
    r"^https?://(?P<host>[A-Za-z0-9.-]+)\.slack\.com/archives/(?P<channel>[A-Z0-9]+)/p(?P<digits>\d{10,})/?(?:\?.*)?$"
)
SLACK_KEY_RE = re.compile(r"^(?P<channel>[A-Z0-9]+):(?P<ts>\d{10}\.\d+)$")
JIRA_URL_RE = re.compile(r"^https?://[^/]+/browse/(?P<issue>[A-Z][A-Z0-9_]+-\d+)/?(?:\?.*)?$")
PR_URL_RE = re.compile(r"^https?://[^/]+/(?P<owner>[^/]+)/(?P<repo>[^/]+)/(?:pull|merge_requests)/(?P<number>\d+)/?")


@dataclass
class Result:
    output: str = ""
    refresh: bool = False
    job_id: str | None = None
    search: str | None = None
    help: bool = False
    quit: bool = False
    error: bool = False
    data: Any = field(default=None, repr=False)


def slack_ts_from_permalink(digits: str) -> str:
    """``1790929532923549`` -> ``1790929532.923549``."""
    if "." in digits:
        return digits
    if len(digits) <= 10:
        return digits
    return f"{digits[:10]}.{digits[10:]}"


def parse_track_spec(spec: str) -> dict[str, Any]:
    """Turn a permalink, a thread key or a bare URL into a POST /api/threads body."""
    spec = spec.strip()
    if not spec:
        raise ValueError("track needs a Slack/Jira/PR URL or <channel>:<thread_ts>")

    match = SLACK_URL_RE.match(spec)
    if match:
        return {
            "kind": "slack",
            "url": spec,
            "channel": match.group("channel"),
            "thread_ts": slack_ts_from_permalink(match.group("digits")),
        }

    match = SLACK_KEY_RE.match(spec)
    if match:
        return {
            "kind": "slack",
            "channel": match.group("channel"),
            "thread_ts": match.group("ts"),
        }

    if JIRA_URL_RE.match(spec):
        return {"kind": "jira", "url": spec}

    if PR_URL_RE.match(spec) or "github.com" in spec or "gitlab" in spec:
        return {"kind": "pr", "url": spec}

    if spec.startswith(("http://", "https://")):
        # Slack permalinks with a different workspace host still carry /archives/.
        if "/archives/" in spec:
            return {"kind": "slack", "url": spec}
        return {"kind": "pr", "url": spec}

    raise ValueError("unrecognised thread reference (expected a Slack/Jira/PR URL or <channel>:<thread_ts>)")


def parse_track_command(text: str) -> tuple[str, str | None]:
    """``<spec> [every 1d]`` -> (spec, cadence label or None)."""
    parts = text.split()
    cadence: str | None = None
    if "every" in parts:
        index = parts.index("every")
        if index + 1 >= len(parts):
            raise ValueError("`every` needs a duration, e.g. `track <url> every 6h`")
        cadence = duration_label(parts[index + 1])
        parts = parts[:index]
    return " ".join(parts), cadence


def _default_cadence(api: HermesClient) -> str:
    try:
        state = api.state()
    except HermesError:
        return "-"
    defaults = state.get("cadence") or state.get("default_cadence") or state.get("cadence_defaults")
    if isinstance(defaults, (dict, int, float)) and defaults not in (None, ""):
        return cadence_text(defaults)
    features = state.get("features")
    if isinstance(features, dict):
        tracking = features.get("tracking")
        if isinstance(tracking, dict):
            seconds = tracking.get("default_reminder_seconds")
            if isinstance(seconds, (int, float)):
                return fmt_duration(seconds)
    return "-"


def _thread_required(current_key: str | None) -> str:
    if not current_key:
        raise ValueError("no thread selected — pick one in the list first")
    return current_key


def run_command(api: HermesClient, line: str, *, current_key: str | None = None) -> Result:
    """Execute one control-surface command against the API."""
    text = line.strip()
    if not text:
        return Result()
    word, _, argument = text.partition(" ")
    word = word.lower()
    argument = argument.strip()

    try:
        if word in {"help", "?"}:
            return Result(help=True)

        if word == "quit" or word == "q":
            return Result(quit=True, output="bye")

        if word == "track":
            spec, cadence = parse_track_command(argument)
            payload = parse_track_spec(spec)
            if cadence:
                payload["cadence"] = cadence
            created = api.create_thread(**payload)
            view = thread_view(created if isinstance(created, dict) else {})
            key = view.get("key") or created.get("key") or spec
            return Result(
                output=f"tracked {key}" + (f" every {cadence}" if cadence else ""),
                refresh=True,
                data=created,
            )

        if word == "untrack":
            key = argument or _thread_required(current_key)
            api.delete_thread(key)
            return Result(output=f"untracked {key}", refresh=True)

        if word == "remind":
            key = _thread_required(current_key)
            if not argument:
                thread = api.thread(key)
                view = thread_view(thread)
                return Result(
                    output=f"reminders for {key}: every {view['cadence']} "
                    f"(default {_default_cadence(api)})"
                )
            label = duration_label(argument)
            api.patch_thread(key, cadence=label)
            return Result(output=f"{key}: reminders every {label}", refresh=True)

        if word == "reminders":
            if not argument:
                return Result(output=f"default reminder cadence: {_default_cadence(api)}")
            label = duration_label(argument)
            try:
                api.set_global_cadence(label)
            except HermesError as exc:
                if exc.status in (404, 405):
                    raise HermesError(
                        "the server does not expose a global cadence endpoint yet; "
                        "use `remind <value>` per thread"
                    ) from exc
                raise
            return Result(output=f"default reminder cadence set to {label}", refresh=True)

        if word == "task":
            if not argument:
                raise ValueError("usage: task <natural language>")
            created = api.create_task(argument)
            title = created.get("title") or created.get("summary") or argument
            url = created.get("url") or created.get("link") or ""
            return Result(output=f"task created: {title}" + (f" — {url}" if url else ""), data=created)

        if word in {"ask", "investigate", "draft"}:
            if word == "ask" and not argument:
                raise ValueError("usage: ask <question>")
            if word in {"investigate", "draft"} and not current_key:
                raise ValueError(f"{word} needs a selected thread")
            created = api.ask(argument, thread_key=current_key, mode=word)
            job_id = api.job_id(created)
            note = "" if word == "ask" else f" ({word})"
            return Result(
                output=f"job {job_id or '?'} started{note} — steps stream below",
                job_id=job_id,
                data=created,
            )

        if word == "snooze":
            key = _thread_required(current_key)
            if not argument:
                raise ValueError("usage: snooze 2h | snooze off")
            seconds = parse_duration(argument)
            value: Any = 0 if seconds == 0 else argument
            if seconds is None:
                value = "default"
            api.patch_thread(key, snooze=value)
            return Result(output=f"{key}: snoozed {argument}", refresh=True)

        if word == "done":
            key = _thread_required(current_key)
            api.patch_thread(key, done=True)
            return Result(output=f"{key}: marked done", refresh=True)

        if word == "important":
            key = _thread_required(current_key)
            thread = api.thread(key)
            important = not bool(thread_view(thread).get("importance"))
            api.patch_thread(key, important=important)
            state = "important" if important else "not important"
            return Result(output=f"{key}: {state}", refresh=True)

        if word == "follow":
            key = _thread_required(current_key)
            api.patch_thread(key, followed=True)
            return Result(output=f"{key}: following", refresh=True)

        if word == "unfollow":
            key = _thread_required(current_key)
            api.patch_thread(key, followed=False)
            return Result(output=f"{key}: not following", refresh=True)

        if word == "search":
            if not argument:
                return Result(output="filter cleared", search="")
            return Result(output=f"filtering by {argument!r}", search=argument)

        if word == "history":
            limit = 10
            if argument:
                try:
                    limit = max(1, min(100, int(argument)))
                except ValueError as exc:
                    raise ValueError("usage: history [count]") from exc
            jobs = api.jobs()[:limit]
            if not jobs:
                return Result(output="no recent jobs")
            lines = []
            for job in jobs:
                job_id = job.get("id") or job.get("job_id") or "?"
                status = str(job.get("status") or "?")
                title = " ".join(str(job.get("question") or job.get("title") or "").split())
                lines.append(f"{job_id}  {status:<9}  {title[:90]}")
            return Result(output="\n".join(lines), data=jobs)

        if word == "notify":
            if not argument:
                raise ValueError("usage: notify <text>")
            api.notify(argument)
            return Result(output="notification sent")

        if word == "remote":
            if not argument:
                raise ValueError("usage: remote <command>")
            created = api.remote_run(argument)
            job_id = api.job_id(created)
            output = created.get("output") if isinstance(created, dict) else None
            if output:
                return Result(output=str(output), data=created)
            return Result(
                output=f"remote job {job_id or '?'} started — steps stream below",
                job_id=job_id,
                data=created,
            )

        if word == "status":
            health = api.health()
            state = api.state()
            tracked = api.threads("tracked", limit=100)
            waiting = sum(1 for thread in tracked if thread_view(thread)["waiting"])
            snapshot = state.get("snapshot") if isinstance(state.get("snapshot"), dict) else {}
            counts = state.get("state") if isinstance(state.get("state"), dict) else {}
            following = snapshot.get("followed")
            version = health.get("version") or "-"
            age = health.get("state_age")
            if isinstance(age, (int, float)):
                age_text = "just now" if age < 60 else f"{fmt_duration(age)} old"
            else:
                age_text = "-"
            second = f"{len(tracked)} tracked · {waiting} waiting on you"
            if isinstance(following, int):
                second += f" · {following} followed"
            second += f" · default cadence {_default_cadence(api)}"
            seen = counts.get("subscriptions")
            history = counts.get("threads")
            third = ""
            if isinstance(seen, int) or isinstance(history, int):
                third = f"{seen or 0} subscriptions · {history or 0} threads seen"
            return Result(
                output="\n".join(
                    line
                    for line in (
                        f"hermes {version} · ok={health.get('ok', '?')} · state {age_text}",
                        second,
                        third,
                    )
                    if line
                ),
                data={"health": health, "state": state, "tracked": tracked},
            )

        raise ValueError(f"unknown command {word!r} — press ? for help")
    except HermesError as exc:
        return Result(output=f"error: {exc}", error=True)
    except ValueError as exc:
        return Result(output=f"error: {exc}", error=True)
    except Exception as exc:  # last resort: the TUI must not crash
        return Result(output=f"error: {exc.__class__.__name__}: {exc}", error=True)


HELP_TEXT = """\
Hermes commands (same words as the Slack control surface)

  track <slack|jira|pr url | channel:thread_ts> [every 1d]
  untrack [key]              stop tracking (defaults to the selection)
  remind [1d|6h|off|default] per-thread cadence (bare = show)
  reminders [1d|6h|off]      global default cadence
  task <text>                natural-language Vikunja task
  ask <question>             agentic question, job steps stream live
  investigate [text]         deep investigation of the selected thread
  draft [text]               draft a reply for the selected thread
  snooze [2h|1d|off]         silence reminders for the selection
  done                       mark the selection done
  important                  toggle important on the selection
  follow / unfollow          follow or unfollow the selection
  search <text>              filter the thread list (empty text clears)
  history [n]                recent jobs
  remote <command>           offload a build/test to amd-pc
  notify <text>              desktop notification on this machine
  status                     health, counts and default cadence
  quit                       leave the TUI

Keys
  ↑ ↓ / j k   move in the thread list
  Enter/o     open the selected thread link
  i or /      focus the command line
  Esc         leave the command line / close help
  r           refresh threads now
  ?           this help
  q           quit
"""
