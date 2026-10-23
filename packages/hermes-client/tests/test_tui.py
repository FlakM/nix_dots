"""Headless tests for the textual dashboard (no network, no real client)."""

from __future__ import annotations

import time
import unittest
from unittest.mock import patch

from textual.widgets import Static

from hermes_client import tui


def make_thread(key: str, summary: str, **overrides):
    item = {
        "key": key,
        "summary": summary,
        "channel_name": "aaa-internal",
        "kind": "slack",
        "priority": 2,
        "important": False,
        "cadence_label": "1d",
        "last_activity": time.time() - 3600,
        "waiting_on_you": False,
        "status": "open",
        "followed": True,
        "link": f"https://slack.example/archives/C1/p{key.split(':')[-1].replace('.', '')}",
    }
    item.update(overrides)
    return item


class FakeApi:
    def __init__(self):
        self.calls: list[tuple] = []
        self.data = {
            "tracked": [
                make_thread("C1:1.0", "dLocal SAML login failure needs an answer", waiting_on_you=True),
                make_thread("C1:2.0", "auditor-v2 backfill review", kind="pr", priority=3),
            ],
            "followed": [make_thread("C9:1.0", "auto followed thread")],
            "all": [make_thread("C1:1.0", "dLocal SAML login failure"), make_thread("C9:1.0", "auto")],
        }

    def threads(self, filter="tracked", limit=100):  # noqa: A002
        self.calls.append(("threads", filter, limit))
        return list(self.data.get(filter, []))


class TuiTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.api = FakeApi()
        self.app = tui.HermesTUI(client=self.api, auto_stream=False)

    async def test_rows_render_and_detail_follows_the_selection(self):
        async with self.app.run_test(size=(130, 40)) as pilot:
            self.app.connected = True
            self.app.apply_threads(self.api.data["tracked"])
            await pilot.pause()
            rows = list(self.app.query(tui.ThreadRow))
            self.assertEqual(2, len(rows))
            self.assertIn("dLocal SAML", rows[0].entry["view"]["summary"])
            detail = self.app.query_one("#detail", Static).render()
            self.assertIn("WAITING ON YOU", str(detail))
            self.assertIn("dLocal SAML", str(detail))
            topbar = self.app.query_one("#topbar", Static).render()
            self.assertIn("1 waiting", str(topbar))

    async def test_tab_cycles_filters_and_refetches(self):
        async with self.app.run_test(size=(120, 36)) as pilot:
            self.app.apply_threads(self.api.data["tracked"])
            await pilot.press("tab")
            await pilot.pause()
            self.assertEqual("followed", self.app.filter_mode)
            self.assertIn(("threads", "followed", 100), self.api.calls)
            self.assertEqual(1, len(list(self.app.query(tui.ThreadRow))))
            await pilot.press("tab")
            await pilot.pause()
            self.assertEqual("all", self.app.filter_mode)

    async def test_empty_state_explains_how_to_track(self):
        async with self.app.run_test(size=(120, 36)) as pilot:
            self.app.apply_threads([])
            await pilot.pause()
            empty = self.app.query_one("#empty", Static)
            self.assertEqual("block", empty.styles.display)
            text = str(empty.render())
            self.assertIn("Nothing tracked here yet", text)
            self.assertIn("track a Slack / PR / Jira link", text)
            self.assertEqual(0, len(list(self.app.query(tui.ThreadRow))))

    async def test_search_filters_the_visible_rows(self):
        async with self.app.run_test(size=(120, 36)) as pilot:
            self.app.search_query = "auditor"
            self.app.apply_threads(self.api.data["tracked"])
            await pilot.pause()
            rows = list(self.app.query(tui.ThreadRow))
            self.assertEqual(1, len(rows))
            self.assertIn("auditor-v2", rows[0].entry["view"]["summary"])
            self.assertIn("filter: tracked", str(self.app.query_one("#topbar", Static).render()))

    async def test_command_output_lands_in_the_live_log(self):
        from hermes_client.commands import Result

        async with self.app.run_test(size=(120, 36)) as pilot:
            self.app.apply_threads(self.api.data["tracked"])
            await pilot.pause()
            with patch.object(tui, "run_command", return_value=Result(output="marked important")) as run:
                await pilot.press("i")
                await pilot.press(*"important")
                await pilot.press("enter")
                await pilot.pause()
            self.assertTrue(run.called)
            log = self.app.query_one("#live", tui.RichLog)
            rendered = "".join(str(line) for line in log.lines)
            self.assertIn("marked important", rendered)

    async def test_done_key_acts_on_the_selected_thread(self):
        async with self.app.run_test(size=(120, 36)) as pilot:
            self.app.apply_threads(self.api.data["tracked"])
            await pilot.pause()
            with patch.object(tui, "run_command", return_value=tui.Result(output="Marked done")) as run:
                await pilot.press("d")
                await pilot.pause()
            self.assertTrue(run.called)
            self.assertEqual("done", run.call_args.args[1])

    async def test_snooze_picker_opens(self):
        async with self.app.run_test(size=(120, 36)) as pilot:
            self.app.apply_threads(self.api.data["tracked"])
            await pilot.pause()
            await pilot.press("s")
            await pilot.pause()
            self.assertIsInstance(self.app.screen, tui.ChoiceScreen)
            await pilot.press("escape")
            await pilot.pause()
            self.assertNotIsInstance(self.app.screen, tui.ChoiceScreen)

    async def test_help_overlay_opens_and_closes(self):
        async with self.app.run_test(size=(120, 36)) as pilot:
            await pilot.press("question_mark")
            await pilot.pause()
            self.assertIsInstance(self.app.screen, tui.HelpScreen)
            await pilot.press("escape")
            await pilot.pause()
            self.assertNotIsInstance(self.app.screen, tui.HelpScreen)


class GroupingTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.api = FakeApi()
        threads = self._build_threads()
        self.api.data["tracked"] = threads
        self.threads = threads
        self.app = tui.HermesTUI(client=self.api, auto_stream=False)

    def _build_threads(self):
        threads = [
            make_thread(
                "C1:1.0",
                "No alert: dLocal SAML login failure for cdryden@dlocal.com",
                headline="dLocal SAML login fails — customer answer needed",
                topic="dlocal-saml-login",
                urgency=92,
                relevance=88,
                waiting_on_you=True,
            ),
            make_thread(
                "C1:2.0",
                "dLocal SAML retry: still failing for the same tenant",
                headline="dLocal SAML still failing after the config change",
                topic="dlocal-saml-login",
                urgency=74,
                relevance=85,
            ),
            make_thread(
                "C1:3.0",
                "Unrelated calendar question",
                headline="Calendar question from Marco",
                topic="calendar",
                urgency=20,
                relevance=10,
            ),
        ]
        return threads

    async def test_repeated_topics_collapse_into_one_group_row(self):
        async with self.app.run_test(size=(130, 40)) as pilot:
            await pilot.pause(0.15)
            self.app.apply_threads(self.threads)
            await pilot.pause()
            rows = list(self.app.query(tui.ThreadRow))
            self.assertEqual(2, len(rows), "two topics -> two rows")
            group = rows[0].entry
            self.assertEqual("group", group["kind"])
            self.assertEqual(2, group["count"])
            self.assertEqual("dlocal-saml-login", group["topic"])
            # the group shows its most urgent member's headline
            self.assertIn("customer answer needed", group["view"]["headline"])

    async def test_space_expands_and_collapses_a_group(self):
        async with self.app.run_test(size=(130, 40)) as pilot:
            await pilot.pause(0.15)
            self.app.apply_threads(self.threads)
            await pilot.pause()
            await pilot.press("space")
            await pilot.pause(0.1)
            rows = list(self.app.query(tui.ThreadRow))
            self.assertEqual(4, len(rows), "group + 2 children + other thread")
            self.assertTrue(rows[1].entry.get("indent"))
            await pilot.press("space")
            await pilot.pause(0.1)
            self.assertEqual(2, len(list(self.app.query(tui.ThreadRow))))

    async def test_threads_are_sorted_by_urgency(self):
        async with self.app.run_test(size=(130, 40)) as pilot:
            await pilot.pause(0.15)
            self.app.apply_threads(self.threads)
            await pilot.pause()
            rows = list(self.app.query(tui.ThreadRow))
            self.assertGreaterEqual(
                rows[0].entry["view"].get("urgency") or 0,
                rows[-1].entry["view"].get("urgency") or 0,
            )

    async def test_detail_shows_scores_and_group_count(self):
        async with self.app.run_test(size=(130, 40)) as pilot:
            await pilot.pause(0.15)
            self.app.apply_threads(self.threads)
            await pilot.pause()
            detail = str(self.app.query_one("#detail", Static).render())
            self.assertIn("urgency", detail)
            self.assertIn("relevance", detail)
            self.assertIn("2 threads · topic dlocal-saml-login", detail)
            self.assertIn("█", detail)


class SearchPromptTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.api = FakeApi()
        self.app = tui.HermesTUI(client=self.api, auto_stream=False)

    async def test_slash_prompt_filters_without_the_search_word(self):
        async with self.app.run_test(size=(130, 40)) as pilot:
            await pilot.pause(0.15)
            self.app.apply_threads(self.api.data["tracked"])
            await pilot.press("slash")
            await pilot.pause(0.05)
            await pilot.press(*"auditor")
            await pilot.press("enter")
            await pilot.pause(0.15)
            self.assertEqual("auditor", self.app.search_query)
            rows = list(self.app.query(tui.ThreadRow))
            self.assertEqual(1, len(rows))
            self.assertIn("auditor-v2", rows[0].entry["view"]["summary"])

    async def test_escape_cancels_the_search_prompt(self):
        async with self.app.run_test(size=(130, 40)) as pilot:
            await pilot.pause(0.15)
            self.app.apply_threads(self.api.data["tracked"])
            await pilot.press("slash")
            await pilot.pause(0.05)
            await pilot.press("escape")
            await pilot.pause(0.05)
            self.assertFalse(self.app.awaiting_search)
            self.assertEqual("", self.app.search_query)

    async def test_track_prefill_survives_the_focus_selection(self):
        async with self.app.run_test(size=(130, 40)) as pilot:
            await pilot.press("t")
            await pilot.pause(0.1)
            command = self.app.query_one("#command", tui.Input)
            self.assertEqual("track ", command.value)
            await pilot.press("x")
            await pilot.pause(0.05)
            self.assertEqual("track x", command.value)
