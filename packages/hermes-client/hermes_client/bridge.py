"""``hermes-bridge`` — desktop notifications + quickshell cache.

Runs as a systemd user service.  It subscribes to ``/api/events`` from
``~/.cache/hermes/last-event-id``, pops a ``notify-send`` toast for
``notify``/``reminder`` events, and republishes everything quickshell needs in
``~/.cache/hermes/bridge.json`` (atomic tmp + rename).

The loop is deliberately unkillable: the API being down (odroid off, VPN down,
bad token) means "retry with exponential backoff", never a traceback.
"""

from __future__ import annotations

import argparse
import signal
import subprocess
import sys
import threading
import time
from typing import Any

from . import __version__, store
from .client import EventStream, HermesClient, HermesError
from .config import ConfigError, load_config
from .format import (
    event_body,
    event_title,
    job_status,
    job_steps,
    job_title,
    step_line,
    thread_view,
    urgency,
)

THREAD_REFRESH_SECONDS = 30.0
NOTIFY_TIMEOUT = 10

_ICONS = {
    "reminder": "appointment-soon",
    "critical": "dialog-error",
    "low": "dialog-information",
    "notify": "dialog-information",
}


def log(message: str) -> None:
    timestamp = time.strftime("%H:%M:%S")
    print(f"{timestamp} hermes-bridge: {message}", file=sys.stderr, flush=True)


class Bridge:
    def __init__(self, client: HermesClient, *, verbose: bool = False) -> None:
        self.client = client
        self.verbose = verbose
        self.lock = threading.RLock()
        self.stop = threading.Event()
        self.bridge = store.load_bridge()
        self.last_id = store.load_last_event_id()
        self.seen: set[int] = set()
        self.notify_available = True
        self.connection = {"connected": False, "error": "starting"}

    # -- persistence ------------------------------------------------------

    def _persist(self) -> None:
        # Events are low-frequency and the file is tiny; always write so the
        # last event of a burst (e.g. job.done + notify) is never dropped.
        with self.lock:
            self.bridge["connection"] = dict(self.connection)
            store.write_bridge(self.bridge)

    def _append_event(self, event: dict[str, Any]) -> None:
        with self.lock:
            events = [
                {
                    "id": event.get("id"),
                    "type": event.get("type"),
                    "ts": event.get("ts", time.time()),
                    "title": event_title(event),
                    "body": event_body(event),
                    "key": (event.get("payload") or {}).get("key"),
                    "link": (event.get("payload") or {}).get("link"),
                }
            ] + list(self.bridge.get("events") or [])
            self.bridge["events"] = events[: store.MAX_EVENTS]

    # -- notifications ----------------------------------------------------

    def _icon_for(self, event: dict[str, Any]) -> str:
        payload = event.get("payload") or {}
        if event.get("type") == "reminder":
            return _ICONS["reminder"]
        level = urgency(payload.get("urgency"))
        if level == "critical":
            return _ICONS["critical"]
        if level == "low":
            return _ICONS["low"]
        return _ICONS["notify"]

    def notify(self, event: dict[str, Any]) -> None:
        if not self.notify_available:
            return
        payload = event.get("payload") or {}
        title = event_title(event) or "Hermes"
        body = event_body(event) or ""
        command = [
            "notify-send",
            "-a",
            "Hermes",
            "-u",
            urgency(payload.get("urgency")),
            "-i",
            self._icon_for(event),
            title,
            body,
        ]
        try:
            subprocess.run(
                command,
                check=False,
                timeout=NOTIFY_TIMEOUT,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except FileNotFoundError:
            self.notify_available = False
            log("notify-send not found; notifications disabled (bridge.json keeps working)")
        except (OSError, subprocess.SubprocessError) as exc:
            log(f"notify-send failed: {exc.__class__.__name__}")

    # -- event handling ---------------------------------------------------

    def handle_event(self, event: dict[str, Any]) -> None:
        raw_id = event.get("id")
        try:
            event_id = int(raw_id) if raw_id is not None else None
        except (TypeError, ValueError):
            event_id = None

        if event_id is not None:
            if event_id in self.seen:
                return
            if self.last_id is not None and event_id <= self.last_id:
                return
            self.seen.add(event_id)
            if len(self.seen) > 1000:
                self.seen = set(sorted(self.seen)[-500:])

        event_type = str(event.get("type") or "")
        payload = event.get("payload") if isinstance(event.get("payload"), dict) else {}

        if event_type in {"notify", "reminder"}:
            self._append_event(event)
            with self.lock:
                # `hermes read` (and the panel opening) clears the file behind
                # our back; honour that instead of reviving the old count.
                persisted = store.load_bridge().get("unread")
                base = persisted if isinstance(persisted, int) else int(self.bridge.get("unread") or 0)
                self.bridge["unread"] = base + 1
            self.notify(event)
            if self.verbose:
                log(f"{event_type}: {event_title(event)}")

        elif event_type == "thread.update":
            self._append_event(event)
            self._apply_thread_update(payload)

        elif event_type in {"job.step", "job.done"}:
            self._update_job(event_type, payload)

        elif event_type == "log":
            if self.verbose:
                log(f"server: {payload.get('level')}: {payload.get('message')}")

        if event_id is not None:
            self.last_id = event_id
            try:
                store.save_last_event_id(event_id)
            except OSError as exc:
                log(f"cannot persist last event id: {exc}")
        self._persist()

    # -- jobs -------------------------------------------------------------

    def _job_entry(self, job_id: str) -> dict[str, Any]:
        with self.lock:
            for job in self.bridge.get("jobs") or []:
                if str(job.get("id")) == str(job_id):
                    return job
        return {"id": job_id, "status": "running", "steps": [], "updated": time.time()}

    def _store_job(self, job: dict[str, Any]) -> None:
        with self.lock:
            jobs = [existing for existing in (self.bridge.get("jobs") or []) if str(existing.get("id")) != str(job.get("id"))]
            jobs.insert(0, job)
            self.bridge["jobs"] = jobs[: store.MAX_JOBS]

    def _update_job(self, event_type: str, payload: dict[str, Any]) -> None:
        job_id = str(payload.get("job_id") or payload.get("id") or "")
        if not job_id:
            return
        job = self._job_entry(job_id)
        steps = list(job.get("steps") or [])
        if event_type == "job.step":
            steps.append(
                {
                    "label": str(payload.get("label") or ""),
                    "detail": str(payload.get("detail") or ""),
                    "ts": payload.get("ts") or time.time(),
                }
            )
            job.update(status=str(payload.get("status") or job.get("status") or "running"), steps=steps[-40:])
            job.setdefault("title", str(payload.get("label") or "job"))
        else:
            ok = payload.get("ok", True)
            job.update(
                status="done" if ok else "error",
                result=payload.get("result"),
                error=payload.get("error"),
                finished=payload.get("ts") or time.time(),
                steps=steps[-40:],
            )
        job["updated"] = time.time()
        self._store_job(job)

    # -- threads ----------------------------------------------------------

    def _apply_thread_update(self, payload: dict[str, Any]) -> None:
        key = str(payload.get("key") or "")
        if not key:
            return
        with self.lock:
            existing = next(
                (thread for thread in (self.bridge.get("threads") or []) if thread.get("key") == key),
                None,
            )
            threads = [thread for thread in (self.bridge.get("threads") or []) if thread.get("key") != key]
            merged = dict(existing or {"key": key})
            merged.update({k: v for k, v in payload.items() if v is not None})
            view = thread_view(merged)
            view.pop("raw", None)  # keep Slack message text out of the panel cache
            threads.append(view)
            threads.sort(
                key=lambda thread: (
                    not thread.get("waiting"),
                    -float(thread.get("priority") or 0),
                    thread.get("age_seconds") or 0,
                )
            )
            self.bridge["threads"] = threads[: store.MAX_THREADS]

    def refresh_threads(self) -> None:
        try:
            threads = self.client.threads("tracked", limit=store.MAX_THREADS)
        except HermesError as exc:
            if self.verbose:
                log(f"thread refresh failed: {exc}")
            return
        views = [thread_view(thread) for thread in threads]
        for view in views:
            view.pop("raw", None)
        views.sort(
            key=lambda thread: (
                not thread["waiting"],
                -float(thread.get("priority") or 0),
                thread.get("age_seconds") or 0,
            )
        )
        with self.lock:
            self.bridge["threads"] = views[: store.MAX_THREADS]
        self._persist()
        if self.verbose:
            log(f"tracked threads: {len(views)}")

    def refresh_jobs(self) -> None:
        try:
            jobs = self.client.jobs()
        except HermesError as exc:
            if self.verbose:
                log(f"job refresh failed: {exc}")
            return
        with self.lock:
            for job in jobs[: store.MAX_JOBS]:
                job_id = str(job.get("id") or job.get("job_id") or "")
                if not job_id:
                    continue
                existing = next(
                    (entry for entry in (self.bridge.get("jobs") or []) if str(entry.get("id")) == job_id),
                    None,
                )
                if existing and existing.get("status") and job_status(job) in {"running", "unknown"}:
                    continue
                self._store_job(
                    {
                        "id": job_id,
                        "status": job_status(job),
                        "title": job_title(job),
                        "steps": [
                            {"label": step_line(step), "ts": step.get("ts")}
                            for step in job_steps(job)
                        ][-40:],
                        "started": job.get("started") or job.get("created"),
                        "finished": job.get("finished"),
                        "result": job.get("result"),
                        "error": job.get("error"),
                        "updated": time.time(),
                    }
                )
        self._persist()

    # -- helpers ----------------------------------------------------------

    def baseline(self) -> None:
        """First run: adopt the server's latest id without toasting history."""
        if self.last_id is not None:
            return
        try:
            data = self.client.events_json(since=0)
        except HermesError as exc:
            log(f"cannot establish event baseline ({exc}); will toast the replay")
            return
        events: list[dict[str, Any]] = []
        if isinstance(data, list):
            events = [event for event in data if isinstance(event, dict)]
        elif isinstance(data, dict):
            for key in ("events", "items", "data"):
                if isinstance(data.get(key), list):
                    events = [event for event in data[key] if isinstance(event, dict)]
                    break
        ids = [int(event["id"]) for event in events if str(event.get("id", "")).isdigit()]
        if ids:
            self.last_id = max(ids)
            store.save_last_event_id(self.last_id)
            log(f"starting after event {self.last_id}")

    def run(self) -> int:
        self.baseline()

        refresh_thread = threading.Thread(target=self._refresh_loop, name="threads", daemon=True)
        refresh_thread.start()

        since = self.last_id or 0
        stream = EventStream(self.client, since=since, max_backoff=60.0, stop_event=self.stop)
        stream.set_state_callback(self._on_state)
        log(f"subscribed from event {since}")
        try:
            for event in stream:
                if self.stop.is_set():
                    break
                try:
                    self.handle_event(event)
                except Exception as exc:  # a bad payload must not kill the bridge
                    log(f"dropping event {event.get('id')}: {exc.__class__.__name__}: {exc}")
                if self.last_id is not None:
                    stream.since = max(stream.since, self.last_id)
        finally:
            self.connection = {"connected": False, "error": "stopped"}
            self._persist()
        return 0

    def _on_state(self, state: dict[str, Any]) -> None:
        changed = (
            self.connection.get("connected") != state.get("connected")
            or self.connection.get("error") != state.get("error")
        )
        self.connection = {"connected": bool(state.get("connected")), "error": state.get("error")}
        if changed:
            if state.get("connected"):
                log("event stream connected")
            else:
                log(f"event stream disconnected: {state.get('error') or 'unknown'}")
            self._persist()

    def _refresh_loop(self) -> None:
        while not self.stop.is_set():
            self.refresh_threads()
            self.refresh_jobs()
            # sleep in 1s slices so SIGTERM/stop is honoured promptly
            deadline = time.monotonic() + THREAD_REFRESH_SECONDS
            while not self.stop.is_set() and time.monotonic() < deadline:
                time.sleep(1)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="hermes-bridge",
        description="Hermes desktop notification bridge (notify-send + quickshell cache).",
    )
    parser.add_argument("--mark-read", action="store_true", help="clear the unread count and exit")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--version", action="version", version=f"hermes-bridge {__version__}")
    args = parser.parse_args(argv)

    if args.mark_read:
        store.mark_read()
        return 0

    try:
        config = load_config()
    except ConfigError as exc:
        log(str(exc))
        return 1

    client = HermesClient.from_config(config)
    bridge = Bridge(client, verbose=args.verbose)

    def shutdown(signum: int, _frame: Any) -> None:
        log(f"signal {signum}, stopping")
        bridge.stop.set()

    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            signal.signal(sig, shutdown)
        except (ValueError, OSError):
            pass

    # Publish an initial file so quickshell has something to render immediately.
    bridge._persist()
    try:
        return bridge.run()
    finally:
        client.close()


if __name__ == "__main__":
    sys.exit(main())
