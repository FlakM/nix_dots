"""Offline tests: no network, no real config, no notify-send."""

from __future__ import annotations

import json
import os
import tempfile
import unittest

import httpx

from hermes_client import store
from hermes_client.client import HermesClient, HermesError, _iter_sse
from hermes_client.commands import parse_track_spec, run_command, slack_ts_from_permalink
from hermes_client.format import fmt_duration, parse_duration, thread_view


def make_client(handler) -> HermesClient:
    return HermesClient("https://hermes.test", "token", transport=httpx.MockTransport(handler))


class FormatTest(unittest.TestCase):
    def test_thread_view_flat(self) -> None:
        view = thread_view(
            {
                "key": "C1:1790929532.923549",
                "summary": "  hello   world ",
                "priority": 2,
                "important": True,
                "cadence_label": "6h",
                "idle_seconds": 7200,
                "waiting_on_you": True,
                "kind": "slack",
                "link": "https://x.slack.com/archives/C1/p1790929532923549",
            }
        )
        self.assertEqual(view["summary"], "hello world")
        self.assertEqual(view["priority_label"], "P2")
        self.assertTrue(view["importance"])
        self.assertTrue(view["waiting"])
        self.assertEqual(view["age"], "2h")
        self.assertEqual(view["cadence"], "6h")

    def test_thread_view_legacy_cadence_seconds(self) -> None:
        view = thread_view({"key": "k", "reminder": {"interval": 86400}})
        self.assertEqual(view["cadence"], "1d")
        self.assertEqual(view["priority_label"], "-")

    def test_durations(self) -> None:
        self.assertEqual(parse_duration("6h"), 21600)
        self.assertEqual(parse_duration("off"), 0)
        self.assertIsNone(parse_duration("default"))
        self.assertAlmostEqual(fmt_duration(86400), "1d")
        with self.assertRaises(ValueError):
            parse_duration("soon")


class SpecTest(unittest.TestCase):
    def test_slack_permalink(self) -> None:
        payload = parse_track_spec("https://x.slack.com/archives/C03K13XKV6G/p1790929532923549")
        self.assertEqual(payload["kind"], "slack")
        self.assertEqual(payload["channel"], "C03K13XKV6G")
        self.assertEqual(payload["thread_ts"], "1790929532.923549")

    def test_slack_key(self) -> None:
        payload = parse_track_spec("C03K13XKV6G:1790929532.923549")
        self.assertEqual(payload, {"kind": "slack", "channel": "C03K13XKV6G", "thread_ts": "1790929532.923549"})

    def test_other_kinds(self) -> None:
        self.assertEqual(parse_track_spec("https://acme.atlassian.net/browse/CX-42")["kind"], "jira")
        self.assertEqual(parse_track_spec("https://github.com/o/r/pull/7")["kind"], "pr")
        with self.assertRaises(ValueError):
            parse_track_spec("C03K13XKV6G")

    def test_slack_ts(self) -> None:
        self.assertEqual(slack_ts_from_permalink("1790929532923549"), "1790929532.923549")
        self.assertEqual(slack_ts_from_permalink("1790929532.923549"), "1790929532.923549")


class ClientTest(unittest.TestCase):
    def test_endpoints(self) -> None:
        calls = []

        def handler(request: httpx.Request) -> httpx.Response:
            calls.append(request)
            if request.url.path == "/api/threads":
                return httpx.Response(200, json={"threads": [{"key": "k"}]})
            if request.url.path == "/api/ask":
                self.assertEqual(json.loads(request.content)["question"], "why")
                return httpx.Response(200, json={"job_id": "j1"})
            if request.url.path.startswith("/api/threads/"):
                return httpx.Response(200, json={"key": "C1:1", "summary": "s"})
            return httpx.Response(200, json={})

        client = make_client(handler)
        self.assertEqual(client.threads()[0]["key"], "k")
        self.assertEqual(client.ask("why")["job_id"], "j1")
        self.assertEqual(client.job_id({"id": 3}), "3")
        self.assertEqual(client.thread("C1:1")["summary"], "s")
        # the key is percent-encoded into the path
        self.assertTrue(any("%3A" in str(call.url) for call in calls))
        client.close()

    def test_error_message(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(401, json={"error": "bad token"})

        client = make_client(handler)
        with self.assertRaises(HermesError) as caught:
            client.health()
        self.assertIn("bad token", str(caught.exception))
        self.assertEqual(caught.exception.status, 401)

    def test_sse_parser(self) -> None:
        events = list(
            _iter_sse(
                [
                    ": keepalive",
                    "id: 7",
                    'data: {"id": 7, "type": "notify", "payload": {"title": "hi"}}',
                    "",
                    "id: 8",
                    'data: {"id": 8, "type": "job.step",',
                    'data: "payload": {"job_id": "j", "label": "go"}}',
                    "",
                ]
            )
        )
        self.assertEqual(len(events), 2)
        self.assertEqual(events[0]["id"], 7)
        self.assertEqual(events[1]["payload"]["label"], "go")


class FakeApi:
    """Minimal stand-in for HermesClient used by run_command tests."""

    def __init__(self) -> None:
        self.calls = []

    def create_thread(self, **fields):
        self.calls.append(("create", fields))
        return {"key": "C1:1", "summary": "tracked"}

    def delete_thread(self, key):
        self.calls.append(("delete", key))

    def patch_thread(self, key, **changes):
        self.calls.append(("patch", key, changes))
        return {"key": key}

    def thread(self, key):
        return {"key": key, "cadence_label": "1d", "important": False}

    def state(self):
        return {"cadence": {"seconds": 86400, "label": "1d"}}

    def set_global_cadence(self, label):
        self.calls.append(("post", "/api/reminders", {"cadence": label}))
        return {}

    def ask(self, question, thread_key=None, mode="ask"):
        self.calls.append(("ask", question, thread_key, mode))
        return {"job_id": "j1"}

    def notify(self, body, title="Hermes", urgency="normal"):
        self.calls.append(("post", "/api/notify", {"title": title, "body": body, "urgency": urgency}))
        return {"ok": True}

    def job_id(self, data):
        return "j1"

    def jobs(self):
        return []

    def health(self):
        return {"ok": True, "version": "1"}

    def threads(self, filter="tracked", limit=50):  # noqa: A002
        return [{"key": "C1:1", "summary": "tracked"}]


class CommandTest(unittest.TestCase):
    def test_track(self) -> None:
        api = FakeApi()
        result = run_command(api, "track https://x.slack.com/archives/C1/p1790929532923549 every 6h")
        self.assertFalse(result.error, result.output)
        self.assertIn("tracked", result.output)
        kind, fields = api.calls[0]
        self.assertEqual(kind, "create")
        self.assertEqual(fields["cadence"], "6h")
        self.assertEqual(fields["thread_ts"], "1790929532.923549")

    def test_thread_commands_use_selection(self) -> None:
        api = FakeApi()
        result = run_command(api, "remind 6h", current_key="C1:1")
        self.assertFalse(result.error, result.output)
        self.assertEqual(api.calls[-1], ("patch", "C1:1", {"cadence": "6h"}))

        result = run_command(api, "done", current_key="C1:1")
        self.assertFalse(result.error, result.output)
        self.assertEqual(api.calls[-1], ("patch", "C1:1", {"done": True}))

    def test_missing_selection_is_an_error(self) -> None:
        result = run_command(FakeApi(), "done")
        self.assertTrue(result.error)
        self.assertIn("no thread selected", result.output)

    def test_unknown_command(self) -> None:
        result = run_command(FakeApi(), "frobnicate")
        self.assertTrue(result.error)
        self.assertIn("unknown command", result.output)

    def test_ask_returns_job(self) -> None:
        api = FakeApi()
        result = run_command(api, "ask what broke?", current_key="C1:1")
        self.assertEqual(result.job_id, "j1")
        self.assertEqual(api.calls[-1], ("ask", "what broke?", "C1:1", "ask"))

    def test_investigate_uses_the_selected_thread_and_mode(self) -> None:
        api = FakeApi()
        result = run_command(api, "investigate", current_key="C1:1")
        self.assertFalse(result.error, result.output)
        self.assertEqual(result.job_id, "j1")
        self.assertEqual(api.calls[-1], ("ask", "", "C1:1", "investigate"))

    def test_investigate_without_a_thread_is_rejected(self) -> None:
        result = run_command(FakeApi(), "investigate")
        self.assertTrue(result.error)
        self.assertIn("selected thread", result.output)

    def test_notify_sends_a_desktop_notification(self) -> None:
        api = FakeApi()
        result = run_command(api, "notify build finished")
        self.assertFalse(result.error, result.output)
        self.assertEqual(
            api.calls[-1],
            ("post", "/api/notify", {"title": "Hermes", "body": "build finished", "urgency": "normal"}),
        )

    def test_global_reminders(self) -> None:
        api = FakeApi()
        result = run_command(api, "reminders 6h")
        self.assertFalse(result.error, result.output)
        self.assertEqual(api.calls[-1], ("post", "/api/reminders", {"cadence": "6h"}))

    def test_empty_search_clears_the_filter(self) -> None:
        result = run_command(FakeApi(), "search")
        self.assertFalse(result.error, result.output)
        self.assertEqual(result.search, "")


class BridgeTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self._old_cache = os.environ.get("XDG_CACHE_HOME")
        os.environ["XDG_CACHE_HOME"] = self._tmp.name

    def tearDown(self) -> None:
        if self._old_cache is None:
            os.environ.pop("XDG_CACHE_HOME", None)
        else:
            os.environ["XDG_CACHE_HOME"] = self._old_cache
        self._tmp.cleanup()

    def test_notify_event_is_persisted_and_deduped(self) -> None:
        from hermes_client.bridge import Bridge

        bridge = Bridge(object(), verbose=False)  # client unused for notify events
        bridge.notify_available = False  # never touch the desktop in tests
        event = {"id": 5, "type": "notify", "ts": 1.0, "payload": {"title": "T", "body": "B"}}
        bridge.handle_event(event)
        bridge.handle_event(event)  # duplicate id must be ignored

        data = json.loads(store.bridge_path().read_text())
        self.assertEqual(data["unread"], 1)
        self.assertEqual(len(data["events"]), 1)
        self.assertEqual(data["events"][0]["title"], "T")
        self.assertEqual(store.load_last_event_id(), 5)

    def test_read_clears_the_badge_even_for_a_running_bridge(self) -> None:
        from hermes_client.bridge import Bridge

        bridge = Bridge(object(), verbose=False)
        bridge.notify_available = False
        bridge.handle_event({"id": 1, "type": "notify", "payload": {"title": "a"}})
        bridge.handle_event({"id": 2, "type": "notify", "payload": {"title": "b"}})
        store.mark_read()
        bridge.handle_event({"id": 3, "type": "notify", "payload": {"title": "c"}})
        self.assertEqual(store.load_bridge()["unread"], 1)

    def test_job_events_are_collected(self) -> None:
        from hermes_client.bridge import Bridge

        bridge = Bridge(object(), verbose=False)
        bridge.notify_available = False
        bridge.handle_event({"id": 1, "type": "job.step", "payload": {"job_id": "j1", "label": "thinking"}})
        bridge.handle_event({"id": 2, "type": "job.done", "payload": {"job_id": "j1", "ok": True, "result": "ok"}})
        data = json.loads(store.bridge_path().read_text())
        self.assertEqual(data["jobs"][0]["id"], "j1")
        self.assertEqual(data["jobs"][0]["status"], "done")
        self.assertEqual(data["jobs"][0]["steps"][0]["label"], "thinking")


class StoreTest(unittest.TestCase):
    def test_atomic_roundtrip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            old_cache = os.environ.get("XDG_CACHE_HOME")
            os.environ["XDG_CACHE_HOME"] = tmp
            try:
                path = store.bridge_path()
                store.atomic_write_json(path, {"unread": 2, "events": []})
                self.assertEqual(json.loads(path.read_text())["unread"], 2)
                self.assertFalse(path.with_name(path.name + ".tmp").exists())
                bridge = store.load_bridge()
                self.assertEqual(bridge["unread"], 2)
                self.assertIn("updated", bridge)
                store.mark_read()
                self.assertEqual(store.load_bridge()["unread"], 0)
                store.save_last_event_id(42)
                self.assertEqual(store.load_last_event_id(), 42)
            finally:
                if old_cache is None:
                    os.environ.pop("XDG_CACHE_HOME", None)
                else:
                    os.environ["XDG_CACHE_HOME"] = old_cache


if __name__ == "__main__":
    unittest.main()
