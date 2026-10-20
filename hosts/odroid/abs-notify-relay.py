#!/usr/bin/env python3
"""Relay Audiobookshelf notifications to Apprise, adding a Storii play button.

Audiobookshelf renders its Apprise payload from Notification.getApprisePayload(),
which templates the title and body but sends `urls` verbatim. A per-episode
"Play" button therefore cannot live in the notification's URL list, because the
deep link needs {{libraryItemId}} and {{episodeId}}.

This relay sits between ABS and the Apprise API:

    ABS --POST--> relay --POST--> Apprise API --> ntfy --> phone

The episode notification body ends with a hidden marker

    <!--storii:<libraryItemId>:<episodeId>-->

which is stripped here (it never reaches the phone) and turned into ntfy's
`click` and `actions` parameters pointing at Storii's play link. Notifications
without the marker are forwarded untouched.

Usage: abs-notify-relay.py <port> <apprise-api-url>
"""

import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MARKER = re.compile(r"<!--\s*storii:([^:>]+):([^>]*?)\s*-->")
UPSTREAM_TIMEOUT = 4  # ABS gives up after 6s, keep the whole round trip below it


def build_play_url(item_id: str, episode_id: str) -> str:
    query = {"id": item_id}
    if episode_id:
        query["episodeId"] = episode_id
    return "storii://play?" + urllib.parse.urlencode(
        query, quote_via=urllib.parse.quote, safe=""
    )


def add_play_action(url: str, play_url: str) -> str:
    """Add click/actions to an ntfy URL, leaving other Apprise targets alone."""
    parts = urllib.parse.urlsplit(url)
    if parts.scheme.lower() not in ("ntfy", "ntfys"):
        return url

    # Drop stale values so re-delivery cannot stack duplicates.
    query = [
        (k, v)
        for k, v in urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
        if k not in ("click", "actions")
    ]
    query.append(("click", play_url))
    query.append(("actions", f"view, Play, {play_url}"))

    # Percent-encode everything so Apprise's query parser keeps the deep link
    # (which contains ? and &) in one piece.
    encoded = "&".join(
        f"{urllib.parse.quote(k, safe='')}={urllib.parse.quote(v, safe='')}"
        for k, v in query
    )
    return urllib.parse.urlunsplit(parts._replace(query=encoded))


def rewrite(payload: dict) -> dict:
    body = payload.get("body") or ""
    match = MARKER.search(body)
    if not match:
        return payload

    item_id, episode_id = match.group(1), match.group(2)
    payload["body"] = MARKER.sub("", body).rstrip()
    play_url = build_play_url(item_id, episode_id)
    payload["urls"] = [add_play_action(url, play_url) for url in payload.get("urls") or []]
    print(
        f"abs-notify-relay: episode {episode_id or '-'} of {item_id} -> {play_url}",
        flush=True,
    )
    return payload


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    upstream = ""

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        if self.path == "/health":
            self._reply(200, b"ok", "text/plain")
        else:
            self.send_error(404)

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        if self.path != "/notify":
            self.send_error(404)
            return

        try:
            length = int(self.headers.get("Content-Length") or 0)
            payload = json.loads(self.rfile.read(length))
            if not isinstance(payload, dict):
                raise ValueError("payload must be a JSON object")
        except (ValueError, TypeError) as exc:
            self.send_error(400, f"invalid payload: {exc}")
            return

        request = urllib.request.Request(
            self.upstream,
            data=json.dumps(rewrite(payload)).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=UPSTREAM_TIMEOUT) as response:
                self._reply(response.status, response.read(), "application/json")
        except urllib.error.HTTPError as exc:
            # Surface Apprise's rejection so ABS counts the attempt as failed.
            self._reply(exc.code, exc.read(), "application/json")
        except OSError as exc:
            self.send_error(502, f"apprise unreachable: {exc}")

    def _reply(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt: str, *args: object) -> None:
        print(f"abs-notify-relay: {fmt % args}", flush=True)


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: abs-notify-relay.py <port> <apprise-api-url>",
            file=sys.stderr,
        )
        return 2

    port, upstream = int(sys.argv[1]), sys.argv[2]
    Handler.upstream = upstream
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"abs-notify-relay: 127.0.0.1:{port} -> {upstream}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
