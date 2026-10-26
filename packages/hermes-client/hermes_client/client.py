"""Typed wrappers around the Hermes HTTP API (see PLATFORM.md).

The client never invents state: every call goes to the agent on the odroid.
Errors are normalised into two exceptions so callers can print one line:

``HermesUnreachable``  network/DNS/timeout -- "the API is down"
``HermesError``        the server answered with an error (message in ``str``)
"""

from __future__ import annotations

import json
import threading
import time
from typing import Any, Callable, Iterable, Iterator
from urllib.parse import quote

import httpx

from . import __version__
from .config import Config

DEFAULT_TIMEOUT = 15.0
TERMINAL_JOB_STATUSES = {
    "done",
    "ok",
    "finished",
    "complete",
    "completed",
    "error",
    "failed",
    "cancelled",
    "canceled",
}


class HermesError(RuntimeError):
    """API returned a non-2xx response, or the payload was unusable."""

    def __init__(self, message: str, *, status: int | None = None) -> None:
        super().__init__(message)
        self.status = status


class HermesUnreachable(HermesError):
    """The server could not be reached at all."""


def _clean_params(params: dict[str, Any] | None) -> dict[str, Any] | None:
    if not params:
        return None
    return {key: value for key, value in params.items() if value is not None}


def _event_id(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _iter_sse(lines: Iterable[str]) -> Iterator[dict[str, Any]]:
    """Parse ``text/event-stream`` lines into event dicts."""
    event_id: str | None = None
    data: list[str] = []
    for raw in lines:
        line = raw.rstrip("\r")
        if not line:
            if data:
                payload = "\n".join(data)
                try:
                    event: Any = json.loads(payload)
                except json.JSONDecodeError:
                    event = {"type": "unknown", "payload": {"raw": payload}}
                if not isinstance(event, dict):
                    event = {"type": "unknown", "payload": event}
                if event_id is not None and "id" not in event:
                    parsed = _event_id(event_id)
                    if parsed is not None:
                        event["id"] = parsed
                event.setdefault("ts", time.time())
                event.setdefault("type", "unknown")
                event.setdefault("payload", {})
                yield event
            event_id = None
            data = []
            continue
        if line.startswith(":"):
            # ": keepalive" comment emitted every 20s by the server
            continue
        field, _, value = line.partition(":")
        if value.startswith(" "):
            value = value[1:]
        if field == "data":
            data.append(value)
        elif field == "id":
            event_id = value
    if data:  # stream ended without the final blank line
        try:
            event = json.loads("\n".join(data))
        except json.JSONDecodeError:
            event = {"type": "unknown", "payload": {"raw": "\n".join(data)}}
        if isinstance(event, dict):
            if event_id is not None and "id" not in event:
                parsed = _event_id(event_id)
                if parsed is not None:
                    event["id"] = parsed
            event.setdefault("ts", time.time())
            event.setdefault("type", "unknown")
            event.setdefault("payload", {})
            yield event


class EventStream:
    """Reconnecting SSE iterator.

    ``events()`` never raises and never returns while stopped: it reconnects
    with exponential backoff, resuming from the last seen id.  Connectivity is
    reported through ``on_state`` so the TUI can show a banner and the bridge
    can record it::

        {"connected": bool, "error": str | None, "since": int}
    """

    def __init__(
        self,
        client: "HermesClient",
        since: int = 0,
        *,
        on_state: Callable[[dict[str, Any]], None] | None = None,
        max_backoff: float = 30.0,
        stop_event: threading.Event | None = None,
    ) -> None:
        self._client = client
        self.since = int(since or 0)
        self._on_state = on_state
        self._max_backoff = max(1.0, float(max_backoff))
        self._stop = stop_event or threading.Event()
        self.connected = False
        self.last_error: str | None = None
        self._last_state: tuple[bool, str | None, int] | None = None

    def set_state_callback(self, callback: Callable[[dict[str, Any]], None] | None) -> None:
        self._on_state = callback
        self._last_state = None

    def stop(self) -> None:
        self._stop.set()

    def stopped(self) -> bool:
        return self._stop.is_set()

    def _emit_state(self, connected: bool, error: str | None) -> None:
        self.connected = connected
        self.last_error = error
        state = (connected, error, self.since)
        if state == self._last_state:
            return
        self._last_state = state
        if self._on_state is not None:
            try:
                self._on_state({"connected": connected, "error": error, "since": self.since})
            except Exception:  # a bad callback must not kill the stream
                pass

    def events(self) -> Iterator[dict[str, Any]]:
        backoff = 1.0
        first_attempt = True
        while not self._stop.is_set():
            error: str | None = None
            try:
                with self._client.http.stream(
                    "GET",
                    "/api/events",
                    params={"since": self.since, "format": "sse"},
                    timeout=httpx.Timeout(15.0, read=90.0),
                ) as response:
                    if response.status_code >= 400:
                        response.read()
                        message = f"events endpoint returned HTTP {response.status_code}"
                        if response.status_code in (401, 403):
                            message += " (check the API token)"
                        raise HermesUnreachable(message)
                    self._emit_state(True, None)
                    backoff = 1.0
                    first_attempt = False
                    for event in _iter_sse(response.iter_lines()):
                        if self._stop.is_set():
                            return
                        parsed_id = _event_id(event.get("id"))
                        if parsed_id is not None and parsed_id > self.since:
                            self.since = parsed_id
                        yield event
                        # a long-lived stream is healthy even without new ids
                        self._emit_state(True, None)
            except HermesError as exc:
                error = str(exc)
            except httpx.HTTPError as exc:
                error = f"cannot reach Hermes at {self._client.api_url} ({exc.__class__.__name__})"
            except Exception as exc:  # unexpected: log, back off, retry
                error = f"event stream failed: {exc.__class__.__name__}: {exc}"

            if self._stop.is_set():
                return
            self._emit_state(False, error or "event stream disconnected")
            wait = 0.2 if first_attempt else backoff
            first_attempt = False
            self._stop.wait(wait)
            backoff = min(self._max_backoff, max(1.0, backoff * 2))

    __iter__ = events


class HermesClient:
    """Synchronous API client.  Safe to share between threads."""

    def __init__(
        self,
        api_url: str,
        token: str,
        *,
        timeout: float = DEFAULT_TIMEOUT,
        transport: httpx.BaseTransport | None = None,
    ) -> None:
        self.api_url = api_url.rstrip("/")
        self.http = httpx.Client(
            base_url=self.api_url,
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
                "User-Agent": f"hermes-client/{__version__}",
            },
            timeout=timeout,
            transport=transport,
            follow_redirects=True,
        )

    @classmethod
    def from_config(cls, config: Config, **kwargs: Any) -> "HermesClient":
        return cls(config.api_url, config.token, **kwargs)

    # -- plumbing ---------------------------------------------------------

    def close(self) -> None:
        self.http.close()

    def __enter__(self) -> "HermesClient":
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()

    def _handle(self, response: httpx.Response) -> Any:
        if response.status_code >= 400:
            message = ""
            try:
                body = response.json()
            except (json.JSONDecodeError, ValueError):
                body = None
            if isinstance(body, dict):
                message = str(body.get("error") or body.get("message") or "")
            if not message:
                message = (response.text or "").strip()[:400] or response.reason_phrase
            prefix = f"HTTP {response.status_code}"
            if response.status_code in (401, 403):
                prefix += " (check the API token)"
            raise HermesError(f"{prefix}: {message}", status=response.status_code)
        if response.status_code == 204 or not response.content:
            return None
        try:
            return response.json()
        except (json.JSONDecodeError, ValueError):
            return {"text": response.text}

    def request(
        self,
        method: str,
        path: str,
        *,
        params: dict[str, Any] | None = None,
        json_body: Any = None,
        timeout: float | None = None,
    ) -> Any:
        try:
            response = self.http.request(
                method,
                path,
                params=_clean_params(params),
                json=json_body,
                timeout=timeout,
            )
        except httpx.TimeoutException as exc:
            raise HermesUnreachable(f"timed out talking to Hermes at {self.api_url}") from exc
        except httpx.HTTPError as exc:
            raise HermesUnreachable(
                f"cannot reach Hermes at {self.api_url}: {exc.__class__.__name__}"
            ) from exc
        return self._handle(response)

    def get(self, path: str, **kwargs: Any) -> Any:
        return self.request("GET", path, **kwargs)

    def post(self, path: str, **kwargs: Any) -> Any:
        return self.request("POST", path, **kwargs)

    def patch(self, path: str, **kwargs: Any) -> Any:
        return self.request("PATCH", path, **kwargs)

    def delete(self, path: str, **kwargs: Any) -> Any:
        return self.request("DELETE", path, **kwargs)

    # -- health / state ---------------------------------------------------

    def health(self) -> dict[str, Any]:
        return self.get("/api/health") or {}

    def state(self) -> dict[str, Any]:
        return self.get("/api/state") or {}

    def usage(self) -> dict[str, Any]:
        return self.get("/api/usage") or {}

    # -- threads ----------------------------------------------------------

    def threads_page(
        self,
        filter: str = "tracked",  # noqa: A002 - matches the API parameter
        *,
        limit: int = 50,
        cursor: str | None = None,
    ) -> Any:
        return self.get(
            "/api/threads",
            params={"filter": filter, "limit": limit, "cursor": cursor},
        )

    def threads(
        self,
        filter: str = "tracked",  # noqa: A002 - matches the API parameter
        *,
        limit: int = 50,
        cursor: str | None = None,
    ) -> list[dict[str, Any]]:
        data = self.threads_page(filter, limit=limit, cursor=cursor)
        if isinstance(data, list):
            return [item for item in data if isinstance(item, dict)]
        if isinstance(data, dict):
            for key in ("threads", "items", "results", "data"):
                value = data.get(key)
                if isinstance(value, list):
                    return [item for item in value if isinstance(item, dict)]
        return []

    def thread(self, key: str) -> dict[str, Any]:
        return self.get(f"/api/threads/{quote(key, safe='')}") or {}

    def create_thread(self, **fields: Any) -> dict[str, Any]:
        payload = {key: value for key, value in fields.items() if value is not None}
        return self.post("/api/threads", json_body=payload) or {}

    def patch_thread(self, key: str, **changes: Any) -> dict[str, Any]:
        payload = {key: value for key, value in changes.items() if value is not None}
        return self.patch(f"/api/threads/{quote(key, safe='')}", json_body=payload) or {}

    def delete_thread(self, key: str) -> Any:
        return self.delete(f"/api/threads/{quote(key, safe='')}")

    def set_global_cadence(self, label: str) -> dict[str, Any]:
        """Global reminder cadence.

        PLATFORM.md documents the tracking API and a Slack ``reminders`` word
        but no HTTP endpoint; ``POST /api/reminders`` is the agreed shape.  A
        404/405 is surfaced by the caller as "not supported yet".
        """
        return self.post("/api/reminders", json_body={"cadence": label}) or {}

    # -- tasks ------------------------------------------------------------

    def create_task(
        self, text: str, project: str | None = None, kind: str = "vikunja"
    ) -> dict[str, Any]:
        payload: dict[str, Any] = {"text": text}
        if project:
            payload["project"] = project
        if kind and kind != "vikunja":
            payload["kind"] = kind
        return self.post("/api/tasks", json_body=payload) or {}

    # -- jobs -------------------------------------------------------------

    def job_id(self, data: Any) -> str | None:
        """Extract a job id from an ``ask``/``remote``/``jobs`` response."""
        if isinstance(data, dict):
            for key in ("job_id", "job", "id"):
                value = data.get(key)
                if isinstance(value, (str, int)) and str(value):
                    return str(value)
        return None

    # backwards-compatible alias used inside this module
    _job_id = job_id

    def ask(
        self,
        question: str,
        *,
        thread_key: str | None = None,
        conversation: Any = None,
        mode: str = "ask",
        speed: str = "auto",
    ) -> dict[str, Any]:
        payload: dict[str, Any] = {"question": question, "mode": mode}
        if thread_key:
            payload["thread_key"] = thread_key
        if conversation is not None:
            payload["conversation"] = conversation
        if speed and speed != "auto":
            payload["speed"] = speed
        return self.post("/api/ask", json_body=payload) or {}

    def notify(
        self, body: str, *, title: str = "Hermes", urgency: str = "normal"
    ) -> dict[str, Any]:
        return self.post(
            "/api/notify",
            json_body={"title": title, "body": body, "urgency": urgency},
        ) or {}

    def jobs(self) -> list[dict[str, Any]]:
        data = self.get("/api/jobs")
        if isinstance(data, list):
            return [item for item in data if isinstance(item, dict)]
        if isinstance(data, dict):
            for key in ("jobs", "items", "data"):
                value = data.get(key)
                if isinstance(value, list):
                    return [item for item in value if isinstance(item, dict)]
        return []

    def job(self, job_id: str) -> dict[str, Any]:
        return self.get(f"/api/jobs/{quote(str(job_id), safe='')}") or {}

    def cancel_job(self, job_id: str) -> Any:
        return self.post(f"/api/jobs/{quote(str(job_id), safe='')}/cancel")

    # -- remote compute ---------------------------------------------------

    def remote_run(self, command: str, *, timeout: float | None = None) -> dict[str, Any]:
        """``POST /api/remote/run`` (PLATFORM.md "Phone / remote compute").

        Assumed payload ``{"command": str, "timeout"?: number}``; the server
        either returns ``{"job_id": ...}`` (streamed) or ``{"output": ...}``.
        """
        payload: dict[str, Any] = {"command": command}
        if timeout is not None:
            payload["timeout"] = timeout
        return self.post("/api/remote/run", json_body=payload) or {}

    def wait_for_job(
        self,
        job_id: str,
        *,
        on_step: Callable[[dict[str, Any]], None] | None = None,
        interval: float = 0.5,
        timeout: float = 900.0,
    ) -> dict[str, Any]:
        """Poll a job until it finishes, reporting unseen steps."""
        seen: set[tuple[Any, ...]] = set()
        deadline = time.monotonic() + timeout
        while True:
            job = self.job(job_id)
            steps = job.get("steps") or []
            if isinstance(steps, list):
                for step in steps:
                    if not isinstance(step, dict):
                        continue
                    marker = (
                        step.get("ts"),
                        step.get("label"),
                        step.get("detail"),
                        step.get("status"),
                    )
                    if marker in seen:
                        continue
                    seen.add(marker)
                    if on_step is not None:
                        on_step(step)
            status = str(job.get("status") or "").lower()
            if status in TERMINAL_JOB_STATUSES or job.get("finished"):
                return job
            if time.monotonic() > deadline:
                raise HermesError(f"timed out waiting for job {job_id}")
            time.sleep(interval)

    # -- events -----------------------------------------------------------

    def events_json(self, since: int = 0, *, wait: int | None = None) -> Any:
        return self.get(
            "/api/events",
            params={"since": since, "format": "json", "wait": wait},
            timeout=(wait or 0) + 30 if wait else None,
        )

    def stream(
        self,
        since: int = 0,
        *,
        on_state: Callable[[dict[str, Any]], None] | None = None,
        max_backoff: float = 30.0,
        stop_event: threading.Event | None = None,
    ) -> EventStream:
        return EventStream(
            self,
            since=since,
            on_state=on_state,
            max_backoff=max_backoff,
            stop_event=stop_event,
        )
