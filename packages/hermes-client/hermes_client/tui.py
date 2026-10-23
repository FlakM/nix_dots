"""``hermes-tui`` — a readable dashboard for tracked threads and live jobs.

Left: two-line thread rows (priority badge, waiting marker, channel, age,
cadence). Right: a detail card for the selection and the live event/step log.
Bottom: the same command words as the Slack control surface plus one-key actions.

Everything network-facing runs off the UI thread; when the API is down the app
shows a slim reconnect banner, retries every few seconds and never raises.
"""

from __future__ import annotations

import subprocess
import sys
import textwrap
import threading
import time
from typing import Any

from rich.text import Text
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.screen import ModalScreen
from textual.widgets import Footer, Input, ListItem, ListView, OptionList, RichLog, Static

from . import __version__, store
from .client import HermesClient, HermesError, HermesUnreachable
from .commands import HELP_TEXT, Result, run_command
from .config import ConfigError, load_config
from .format import job_status, step_line, thread_view

REFRESH_SECONDS = 5.0
SPINNER = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

INK = "#d7e3e0"
MUTED = "#7d8f8a"
FAINT = "#4b5b57"
ACCENT = "#72e4ae"
BLUE = "#72d7ff"
AMBER = "#f6c177"
RED = "#ff7b86"
PURPLE = "#c3a6ff"

ACTION_VERBS = {
    "done",
    "important",
    "follow",
    "unfollow",
    "snooze",
    "remind",
    "reminders",
    "track",
    "untrack",
    "task",
    "notify",
}
FILTERS = ("tracked", "followed", "all")
FILTER_LABEL = {"tracked": "TRACKED", "followed": "FOLLOWED", "all": "ALL THREADS"}
PRIORITY_COLOUR = {1: RED, 2: AMBER, 3: BLUE, 4: MUTED, 0: FAINT}
KIND_COLOUR = {"slack": BLUE, "pr": PURPLE, "jira": AMBER}

SNOOZE_CHOICES = [
    ("1h", "in an hour"),
    ("4h", "in four hours"),
    ("1d", "tomorrow"),
    ("3d", "in three days"),
    ("off", "clear the snooze"),
]
REMIND_CHOICES = [
    ("1h", "hourly"),
    ("6h", "every six hours"),
    ("1d", "daily"),
    ("3d", "every three days"),
    ("off", "no timed reminders"),
]

CSS = f"""
Screen {{
    background: #090d11;
    color: {INK};
}}
#topbar {{
    height: 1;
    padding: 0 1;
    background: #0e141a;
    color: {MUTED};
}}
#banner {{
    height: 1;
    padding: 0 1;
    background: #261317;
    color: {RED};
    display: none;
}}
#main {{ height: 1fr; }}
#left {{
    width: 56%;
    border-right: solid #1c262d;
}}
#right {{ width: 1fr; }}
#list-title, #live-title {{
    height: 2;
    padding: 1 1 0 1;
    background: #0e141a;
    color: {ACCENT};
    text-style: bold;
}}
#threads {{
    height: 1fr;
    background: #090d11;
    scrollbar-size-vertical: 1;
}}
ThreadRow {{ height: 2; }}
ListItem {{
    height: 2;
    padding: 0 1;
    background: #090d11;
}}
ListItem.-highlight {{
    background: #14221c;
}}
ListView:focus ListItem.-highlight {{
    background: #182b22;
}}
#empty {{
    padding: 2 3;
    height: 1fr;
    color: {MUTED};
}}
#detail {{
    height: auto;
    max-height: 14;
    padding: 1 2 0 2;
    background: #090d11;
}}
#actions {{
    height: auto;
    max-height: 2;
    padding: 0 2;
    color: {FAINT};
    background: #090d11;
}}
#live-hint {{
    height: auto;
    padding: 1 2;
    color: {MUTED};
}}
#live {{
    height: 1fr;
    padding: 0 1;
    background: #090d11;
    scrollbar-size-vertical: 1;
}}
#command {{
    dock: bottom;
    height: 1;
    background: #0e141a;
    border: none;
    padding: 0 1;
    color: #f3f8f5;
}}
#command:focus {{ background: #121c23; }}
Footer {{
    background: #0e141a;
    color: {MUTED};
}}
HelpScreen {{ align: center middle; background: #9905080e; }}
#help {{
    width: 84;
    height: auto;
    max-height: 92%;
    padding: 1 2;
    background: #0e141a;
    border: round #2c4a3e;
}}
ChoiceScreen {{ align: center middle; background: #9905080e; }}
#choice {{
    width: 44;
    height: auto;
    padding: 1 2;
    background: #0e141a;
    border: round #2c4a3e;
}}
#choice-title {{ height: 1; text-style: bold; color: {ACCENT}; }}
"""


def _colour_for_priority(view: dict[str, Any]) -> str:
    try:
        priority = int(view.get("priority") or 0)
    except (TypeError, ValueError):
        priority = 0
    return PRIORITY_COLOUR.get(priority, MUTED)


def _short(value: str, width: int) -> str:
    value = " ".join(value.split())
    if width > 4 and len(value) > width:
        return value[: width - 1] + "…"
    return value


def _fit(line: Text, width: int) -> Text:
    if width > 0 and line.cell_len > width:
        line.truncate(width, overflow="ellipsis")
    return line


class ThreadRow(Static):
    """Two-line row: priority/title, then channel · kind · age · cadence."""

    def __init__(self, view: dict[str, Any]) -> None:
        super().__init__()
        self.view = view

    def set_view(self, view: dict[str, Any]) -> None:
        self.view = view
        self.refresh(layout=True)

    def render(self) -> Text:
        view = self.view
        width = max(20, (self.size.width or 80) - 1)
        priority_colour = _colour_for_priority(view)
        waiting = bool(view.get("waiting"))

        head = Text()
        head.append("▌ ", style=AMBER if waiting else "#182b22")
        label = str(view.get("priority_label") or "-")
        if label in {"-", ""}:
            head.append(" · ", style=FAINT)
        else:
            head.append(f"{label:>2} ", style=f"bold {priority_colour}")
        if view.get("importance"):
            head.append("★ ", style=f"bold {AMBER}")
        else:
            head.append("  ")
        if waiting:
            head.append("⏳ ", style=f"bold {AMBER}")
        head.append(str(view.get("summary") or ""), style=INK)

        meta = Text()
        meta.append("     ")
        channel = str(view.get("channel_name") or "")
        if channel:
            meta.append(channel, style=BLUE)
            meta.append("  ·  ", style=FAINT)
        kind = str(view.get("kind") or "slack")
        meta.append(kind, style=KIND_COLOUR.get(kind, MUTED))
        meta.append("  ·  ", style=FAINT)
        meta.append(str(view.get("age") or "-"), style=MUTED)
        meta.append("  ·  ", style=FAINT)
        cadence = view.get("cadence")
        if cadence in (None, "", "-"):
            cadence_text = "activity"
        elif str(cadence) == "off":
            cadence_text = "no reminders"
        else:
            cadence_text = "every " + str(cadence)
        meta.append(cadence_text, style=MUTED)
        if view.get("snoozed"):
            meta.append("  ·  ", style=FAINT)
            meta.append("snoozed", style=FAINT)

        return _fit(head, width) + Text("\n") + _fit(meta, width)


class ThreadItem(ListItem):
    def __init__(self, view: dict[str, Any]) -> None:
        super().__init__(ThreadRow(view))
        self.key = str(view.get("key") or "")

    @property
    def row(self) -> ThreadRow:
        return self.query_one(ThreadRow)

    def set_view(self, view: dict[str, Any]) -> None:
        self.key = str(view.get("key") or "")
        self.row.set_view(view)


class HelpScreen(ModalScreen):
    """The ``?`` overlay."""

    BINDINGS = [Binding("escape,q,question_mark,enter", "dismiss", "Close")]

    def compose(self) -> ComposeResult:
        yield Static(HELP_TEXT, id="help", markup=False)

    def action_dismiss(self) -> None:
        self.app.pop_screen()


class ChoiceScreen(ModalScreen[str | None]):
    """A small centred picker used by snooze/remind."""

    BINDINGS = [Binding("escape,q", "cancel", "Cancel")]

    def __init__(self, title: str, choices: list[tuple[str, str]]) -> None:
        super().__init__()
        self.title_text = title
        self.choices = choices

    def compose(self) -> ComposeResult:
        with Vertical(id="choice"):
            yield Static(self.title_text, id="choice-title")
            options = OptionList(*[f"{value:<4}  {label}" for value, label in self.choices])
            yield options

    def on_mount(self) -> None:
        self.query_one(OptionList).focus()

    def on_option_list_option_selected(self, event: OptionList.OptionSelected) -> None:
        index = event.option_index
        if 0 <= index < len(self.choices):
            self.dismiss(self.choices[index][0])
        else:
            self.dismiss(None)

    def action_cancel(self) -> None:
        self.dismiss(None)


class HermesTUI(App):
    TITLE = "Hermes"
    SUB_TITLE = "tracked threads · live jobs"
    ENABLE_COMMAND_PALETTE = False
    CSS = CSS
    BINDINGS = [
        Binding("q", "quit_app", "Quit"),
        Binding("ctrl+q", "quit_app", "Quit", show=False),
        Binding("question_mark", "help", "Help"),
        Binding("j", "cursor_down", "Down", show=False),
        Binding("k", "cursor_up", "Up", show=False),
        Binding("g", "cursor_home", "Top", show=False),
        Binding("G", "cursor_end", "Bottom", show=False),
        Binding("tab", "cycle_filter", "Filter", priority=True),
        Binding("r", "refresh", "Refresh", show=False),
        Binding("i", "focus_command", "Command"),
        Binding("slash", "search", "Search"),
        Binding("o", "open_link", "Open", show=False),
        Binding("d", "done", "Done"),
        Binding("f", "follow", "Follow", show=False),
        Binding("s", "snooze", "Snooze"),
        Binding("R", "remind", "Remind"),
        Binding("t", "track", "Track"),
        Binding("a", "ask", "Ask"),
        Binding("y", "copy_link", "Copy link", show=False),
        Binding("escape", "escape", "", show=False),
    ]

    def __init__(
        self, client: HermesClient | None = None, auto_stream: bool = True
    ) -> None:
        super().__init__()
        self.client: HermesClient | None = client
        self.auto_stream = auto_stream
        self._client_lock = threading.Lock()
        self._refreshing = False
        self._stopping = False
        self._stream: Any = None
        self._spin = 0
        self.last_event_id = 0
        self.threads: list[dict[str, Any]] = []
        self.views: list[dict[str, Any]] = []
        self.row_keys: list[str] = []
        self.current_key: str | None = None
        self.search_query = ""
        self.filter_mode = "tracked"
        self.active_job: str | None = None
        self.jobs: dict[str, dict[str, Any]] = {}
        self.config_error = ""
        self.connected: bool | None = None
        self.status_note = "starting…"

    # -- layout -----------------------------------------------------------

    def compose(self) -> ComposeResult:
        yield Static("Hermes", id="topbar")
        yield Static("", id="banner", markup=False)
        with Horizontal(id="main"):
            with Vertical(id="left"):
                yield Static("TRACKED", id="list-title")
                yield ListView(id="threads")
                yield Static("", id="empty", markup=False)
            with Vertical(id="right"):
                yield Static("", id="detail")
                yield Static("", id="actions")
                yield Static("LIVE", id="live-title")
                yield Static("", id="live-hint", markup=False)
                yield RichLog(id="live", markup=False, wrap=True)
        yield Input(placeholder="❯ command — track/ask/remind/task · tab filters · ? help", id="command")
        yield Footer()

    def on_mount(self) -> None:
        self.query_one("#threads", ListView).focus()
        hint = self.query_one("#live-hint", Static)
        hint.update(
            Text.assemble(
                ("Live events and job steps land here.\n\n", f"bold {INK}"),
                ("  a  ", f"bold {ACCENT}"),
                ("ask about the selected thread\n", MUTED),
                ("  R  ", f"bold {ACCENT}"),
                ("set a reminder cadence\n", MUTED),
                ("  t  ", f"bold {ACCENT}"),
                ("track a Slack / PR / Jira link\n", MUTED),
            )
        )
        self._update_topbar()
        self.request_refresh()
        self.set_interval(REFRESH_SECONDS, self.request_refresh)
        self.set_interval(0.12, self._tick_spinner)
        if self.auto_stream:
            threading.Thread(
                target=self._stream_thread, name="hermes-sse", daemon=True
            ).start()

    def on_unmount(self) -> None:
        self._stopping = True
        if self._stream is not None:
            try:
                self._stream.stop()
            except Exception:
                pass

    # -- chrome -----------------------------------------------------------

    def _update_topbar(self) -> None:
        waiting = sum(1 for view in self.views if view.get("waiting"))
        running = sum(
            1
            for job in self.jobs.values()
            if job_status(job) in {"running", "pending", "queued"}
        )
        bar = Text()
        if self.connected is False:
            bar.append("● ", style=RED)
            bar.append("offline", style=f"bold {RED}")
        elif self.connected is None:
            bar.append("● ", style=AMBER)
            bar.append("connecting", style=AMBER)
        else:
            bar.append("● ", style=ACCENT)
            bar.append("connected", style=ACCENT)
        bar.append("   ")
        bar.append(f"{len(self.views)}", style=f"bold {INK}")
        bar.append(" shown", style=MUTED)
        bar.append("   ")
        bar.append(f"{waiting}", style=f"bold {AMBER}")
        bar.append(" waiting", style=MUTED)
        if running:
            bar.append("   ")
            bar.append(f"{SPINNER[self._spin % len(SPINNER)]} {running} job", style=BLUE)
        unread = 0
        try:
            unread = int(store.load_bridge().get("unread") or 0)
        except Exception:
            unread = 0
        if unread:
            bar.append("   ")
            bar.append(f"● {unread} new", style=f"bold {AMBER}")
        bar.append("   ")
        bar.append(f"filter: {self.filter_mode}", style=MUTED)
        if self.search_query:
            bar.append(f"   /{self.search_query}", style=BLUE)
        bar.append("   ")
        bar.append(time.strftime("%H:%M:%S"), style=FAINT)
        self.query_one("#topbar", Static).update(bar)

        title = self.query_one("#list-title", Static)
        label = FILTER_LABEL.get(self.filter_mode, "THREADS")
        title.update(
            Text.assemble(
                (f"{label}", f"bold {ACCENT}"),
                (f"  {len(self.views)}", MUTED),
                ("   tab to switch", FAINT),
            )
        )

    def _tick_spinner(self) -> None:
        running = any(
            job_status(job) in {"running", "pending", "queued"}
            for job in self.jobs.values()
        )
        if running:
            self._spin += 1
            self._update_topbar()

    def set_banner(self, text: str, visible: bool) -> None:
        banner = self.query_one("#banner", Static)
        banner.update(text or "")
        banner.styles.display = "block" if visible and text else "none"

    def set_status(self, text: str) -> None:
        self.status_note = text

    # -- client -----------------------------------------------------------

    def ensure_client(self) -> HermesClient | None:
        with self._client_lock:
            if self.client is not None:
                return self.client
            try:
                config = load_config()
            except ConfigError as exc:
                self.config_error = str(exc)
                return None
            self.client = HermesClient.from_config(config)
            self.config_error = ""
            return self.client

    def _safe_call(self, callback: Any, *args: Any) -> None:
        try:
            self.call_from_thread(callback, *args)
            return
        except RuntimeError:
            # Already on the UI thread (tests, or a synchronous timer callback).
            pass
        except Exception:
            return
        try:
            callback(*args)
        except Exception:
            pass

    # -- SSE --------------------------------------------------------------

    def _stream_thread(self) -> None:
        while not self._stopping:
            client = self.ensure_client()
            if client is None:
                self._safe_call(
                    self.set_banner, f"not configured: {self.config_error}", True
                )
                time.sleep(REFRESH_SECONDS)
                continue
            stream = client.stream(
                since=self.last_event_id,
                on_state=lambda state: self._safe_call(self.apply_stream_state, state),
            )
            self._stream = stream
            try:
                for event in stream:
                    if self._stopping:
                        break
                    self._safe_call(self.handle_event, event)
            except Exception as exc:  # EventStream swallows; belt and braces
                self._safe_call(self.set_banner, f"event stream error: {exc}", True)
            finally:
                stream.stop()
                self._stream = None
            if self._stopping:
                break
            time.sleep(2)

    def apply_stream_state(self, state: dict[str, Any]) -> None:
        self.last_event_id = max(self.last_event_id, int(state.get("since") or 0))
        self.connected = bool(state.get("connected"))
        if self.connected:
            self.set_banner("", False)
        else:
            self.set_banner(
                f"API unreachable — retrying ({state.get('error') or 'offline'})", True
            )
        self._update_topbar()

    # -- thread list ------------------------------------------------------

    def request_refresh(self) -> None:
        if self._refreshing:
            return
        self._refreshing = True
        # Capture the filter: a fetch that lands after the user pressed tab must
        # not overwrite the newer list.
        mode = self.filter_mode
        threading.Thread(
            target=self._refresh_worker, args=(mode,), name="hermes-threads", daemon=True
        ).start()

    def _refresh_worker(self, mode: str) -> None:
        try:
            client = self.ensure_client()
            if client is None:
                self._safe_call(
                    self.set_banner, f"not configured: {self.config_error}", True
                )
                return
            threads = client.threads(mode, limit=100)
            if mode != self.filter_mode:
                return
            self._safe_call(self.apply_threads, threads)
        except HermesUnreachable as exc:
            self._safe_call(self.set_banner, f"API unreachable — retrying: {exc}", True)
            self._safe_call(self.set_status, "no thread data — API unreachable")
        except HermesError as exc:
            self._safe_call(self.set_banner, f"API error: {exc}", True)
            self._safe_call(self.set_status, "no thread data — API error")
        except Exception as exc:
            self._safe_call(
                self.set_banner, f"refresh failed: {exc.__class__.__name__}: {exc}", True
            )
            self._safe_call(self.set_status, "no thread data — refresh failed")
        finally:
            self._refreshing = False

    def _visible_views(self) -> list[dict[str, Any]]:
        views = [thread_view(thread) for thread in self.threads]
        if self.search_query:
            needle = self.search_query.lower()
            views = [
                view
                for view in views
                if needle
                in " ".join(
                    [
                        str(view["summary"]),
                        str(view["key"]),
                        str(view["kind"]),
                        str(view["note"]),
                        str(view["channel_name"]),
                    ]
                ).lower()
            ]
        views.sort(
            key=lambda view: (
                not view["waiting"],
                -int(view.get("priority") or 0),
                view["age_seconds"] if view["age_seconds"] is not None else 1e12,
            )
        )
        return views

    def apply_threads(self, threads: list[dict[str, Any]]) -> None:
        self.threads = threads
        views = self._visible_views()
        self.views = views
        keys = [str(view["key"]) for view in views]
        list_view = self.query_one("#threads", ListView)

        if keys != self.row_keys:
            previous = self.current_key
            self.row_keys = keys
            list_view.clear()
            for view in views:
                list_view.append(ThreadItem(view))
            if previous in keys:
                list_view.index = keys.index(previous)
            elif keys:
                list_view.index = 0
        else:
            for item, view in zip(list_view.children, views):
                if isinstance(item, ThreadItem):
                    item.set_view(view)

        empty = self.query_one("#empty", Static)
        if views:
            empty.update("")
            empty.styles.display = "none"
            list_view.styles.display = "block"
        else:
            list_view.styles.display = "none"
            empty.styles.display = "block"
            empty.update(self._empty_state())

        if not keys:
            self.current_key = None
            self.show_detail(None)
        elif self.current_key not in keys:
            self.current_key = keys[0]
            self.show_detail(keys[0])
        else:
            self.show_detail(self.current_key)
        self._update_topbar()

    def _empty_state(self) -> Text:
        text = Text()
        if self.search_query:
            text.append(f"Nothing matches “{self.search_query}”.\n\n", style=INK)
            text.append("esc clears the filter\n", style=MUTED)
            return text
        text.append("Nothing tracked here yet.\n\n", style=f"bold {INK}")
        if self.filter_mode == "tracked":
            text.append("Add what you actually care about:\n", style=MUTED)
            text.append("  t            ", style=ACCENT)
            text.append("track a Slack / PR / Jira link\n", style=MUTED)
            text.append("  i            ", style=ACCENT)
            text.append("open the command line\n", style=MUTED)
            text.append("  tab          ", style=ACCENT)
            text.append("look at auto-followed threads\n\n", style=MUTED)
            text.append(
                "Auto-followed threads still notify you; they just are not tracked.",
                style=FAINT,
            )
        else:
            text.append("Switch with tab; press t to track a link.", style=MUTED)
        return text

    def show_detail(self, key: str | None) -> None:
        detail = self.query_one("#detail", Static)
        actions = self.query_one("#actions", Static)
        view = next((item for item in self.views if item["key"] == key), None)
        if view is None:
            detail.update(
                Text(
                    "Select a thread to see its detail, or press ? for the key map.",
                    style=MUTED,
                )
            )
            actions.update("")
            return

        text = Text()
        if view.get("waiting"):
            text.append("WAITING ON YOU", style=f"bold {AMBER}")
            text.append("   ", style=MUTED)
        if view.get("importance"):
            text.append("★ important", style=f"bold {AMBER}")
            text.append("   ", style=MUTED)
        text.append(str(view.get("status") or "open"), style=MUTED)
        text.append("\n\n")
        pane_width = max(40, (self.query_one("#detail", Static).size.width or 90) - 4)
        summary = " ".join(str(view.get("summary") or "").split())
        if len(summary) > pane_width * 3:
            summary = summary[: pane_width * 3 - 1] + "…"
        text.append(summary, style=f"bold {INK}")
        text.append("\n\n")
        meta = [
            ("priority", view.get("priority_label") or "-", _colour_for_priority(view)),
            ("channel", str(view.get("channel_name") or "-"), BLUE),
            ("kind", str(view.get("kind") or "slack"), KIND_COLOUR.get(str(view.get("kind")), MUTED)),
            ("idle", str(view.get("age") or "-"), MUTED),
            (
                "cadence",
                "no reminders"
                if str(view.get("cadence") or "") == "off"
                else (
                    str(view.get("cadence"))
                    if view.get("cadence") not in (None, "", "-")
                    else "activity"
                ),
                MUTED,
            ),
        ]
        per_line = 3 if pane_width >= 74 else 2
        for start in range(0, len(meta), per_line):
            for label, value, colour in meta[start : start + per_line]:
                text.append(f"{label:<9}", style=FAINT)
                value = str(value)
                if len(value) > 12:
                    value = value[:11] + "…"
                text.append(f"{value:<12}", style=colour)
            text.append("\n")
        if view.get("note"):
            text.append(f"{'note':<9}", style=FAINT)
            text.append(_short(str(view["note"]), pane_width - 9), style=INK)
            text.append("\n")
        if view.get("link"):
            text.append(f"{'link':<9}", style=FAINT)
            text.append(_short(str(view["link"]), pane_width - 9), style=BLUE)
        detail.update(text + Text("\n"))

        hints = Text()
        line_width = 0
        for keys, label in (
            ("o", "open"),
            ("a", "ask"),
            ("R", "remind"),
            ("s", "snooze"),
            ("d", "done"),
            ("i", "important"),
            ("f", "follow"),
            ("y", "copy"),
        ):
            chunk = f" {keys} {label} "
            if line_width and line_width + len(chunk) + 2 > pane_width:
                hints.append("\n")
                line_width = 0
            hints.append(f" {keys} ", style=f"bold {ACCENT}")
            hints.append(f"{label}  ", style=FAINT)
            line_width += len(chunk) + 2
        actions.update(hints)

    # -- list + input events ----------------------------------------------

    def on_list_view_highlighted(self, event: ListView.Highlighted) -> None:
        item = event.item
        if isinstance(item, ThreadItem):
            self.current_key = item.key
            self.show_detail(item.key)

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        self.action_open_link()

    def on_input_submitted(self, event: Input.Submitted) -> None:
        line = event.value.strip()
        event.input.value = ""
        self.query_one("#threads", ListView).focus()
        if not line:
            return
        if line.lower() in {"exit", "quit", "q"}:
            self.exit()
            return
        if line.lower() in {"help", "?"}:
            self.action_help()
            return
        threading.Thread(
            target=self._command_worker,
            args=(line, self.current_key),
            name="hermes-command",
            daemon=True,
        ).start()

    def _command_worker(self, line: str, current_key: str | None) -> None:
        client = self.ensure_client()
        if client is None:
            self._safe_call(
                self.apply_result,
                line,
                Result(output=f"error: {self.config_error}", error=True),
            )
            return
        try:
            result = run_command(client, line, current_key=current_key)
        except Exception as exc:
            result = Result(output=f"error: {exc.__class__.__name__}: {exc}", error=True)
        self._safe_call(self.apply_result, line, result)

    def apply_result(self, line: str, result: Result) -> None:
        log = self.query_one("#live", RichLog)
        self.query_one("#live-hint", Static).styles.display = "none"
        echo = Text()
        echo.append("❯ ", style=ACCENT)
        echo.append(line, style=MUTED)
        log.write(echo)
        if result.output:
            width = max(30, (log.size.width or 90) - 4)
            for chunk in result.output.splitlines() or [""]:
                for part in textwrap.wrap(chunk, width=width) or [""]:
                    body = Text("  ")
                    body.append(part, style=RED if result.error else INK)
                    log.write(body)
        if result.help:
            self.action_help()
        if result.quit:
            self.exit()
            return
        if result.search is not None:
            self.search_query = result.search.strip()
            self.request_refresh()
        if result.job_id:
            self.active_job = result.job_id
            line_text = Text()
            line_text.append("  ")
            line_text.append(f"job {result.job_id} streaming…", style=BLUE)
            log.write(line_text)
        if result.refresh:
            self.request_refresh()
        verb = line.split()[0].lower() if line.split() else ""
        if not result.error and result.output and verb in ACTION_VERBS:
            try:
                self.notify(result.output.splitlines()[0][:80], timeout=3)
            except Exception:
                pass

    def _log_body(self, head: Text, body: str, style: str = INK) -> None:
        """Write a headline and pre-wrapped body lines (RichLog does not re-wrap)."""
        log = self.query_one("#live", RichLog)
        log.write(head)
        body = " ".join(str(body or "").split())
        if not body:
            return
        width = max(30, (log.size.width or 90) - 6)
        for chunk in textwrap.wrap(body, width=width) or [body]:
            line = Text("    ")
            line.append(chunk, style=style)
            log.write(line)

    # -- events -----------------------------------------------------------

    def handle_event(self, event: dict[str, Any]) -> None:
        event_type = str(event.get("type") or "")
        payload = event.get("payload") if isinstance(event.get("payload"), dict) else {}
        log = self.query_one("#live", RichLog)
        self.query_one("#live-hint", Static).styles.display = "none"

        if event_type in {"notify", "reminder"}:
            title = str(payload.get("title") or "Still waiting")
            body = str(payload.get("body") or payload.get("summary") or "")
            line = Text()
            line.append("⏰ ", style=AMBER)
            line.append(title, style=f"bold {AMBER}")
            self._log_body(line, body, INK)
            try:
                self.notify(body or title, title=title, timeout=8)
            except Exception:
                pass

        elif event_type == "job.step":
            job_id = str(payload.get("job_id") or "")
            step = Text()
            step.append("  ✓ ", style=ACCENT)
            step.append(step_line(payload), style=MUTED)
            log.write(step)
            if job_id:
                job = self.jobs.setdefault(job_id, {"id": job_id, "steps": []})
                job.setdefault("steps", []).append({"label": step_line(payload)})
                job["status"] = "running"
                if self.active_job is None:
                    self.active_job = job_id
                self._update_topbar()

        elif event_type == "job.done":
            job_id = str(payload.get("job_id") or "")
            ok = payload.get("ok", True)
            result = payload.get("result")
            error = payload.get("error")
            line = Text()
            line.append("  ■ " if ok else "  ✗ ", style=ACCENT if ok else RED)
            line.append(f"job {job_id or '?'} {'done' if ok else 'failed'}", style=MUTED)
            log.write(line)
            if result:
                self._log_body(Text(""), str(result), INK)
            if error:
                self._log_body(Text(""), str(error), RED)
            if job_id:
                self.jobs.setdefault(job_id, {"id": job_id}).update(
                    {"status": "done" if ok else "error", "result": result, "error": error}
                )
                if self.active_job == job_id:
                    self.active_job = None
            self._update_topbar()
            self.request_refresh()

        elif event_type == "thread.update":
            key = str(payload.get("key") or "")
            if key:
                line = Text()
                line.append("  · ", style=FAINT)
                line.append(f"{key} {payload.get('status') or 'updated'}", style=FAINT)
                log.write(line)
            self.request_refresh()

        if isinstance(event.get("id"), int):
            self.last_event_id = max(self.last_event_id, int(event["id"]))

    # -- actions ----------------------------------------------------------

    def _list_view(self) -> ListView:
        return self.query_one("#threads", ListView)

    def _selected_view(self) -> dict[str, Any] | None:
        return next(
            (item for item in self.views if item["key"] == self.current_key), None
        )

    def action_quit_app(self) -> None:
        self.exit()

    def action_help(self) -> None:
        self.push_screen(HelpScreen())

    def action_refresh(self) -> None:
        self.request_refresh()

    def action_focus_command(self) -> None:
        self.query_one("#command", Input).focus()

    def action_search(self) -> None:
        command = self.query_one("#command", Input)
        command.value = "search "
        command.focus()
        command.cursor_position = len(command.value)

    def action_escape(self) -> None:
        command = self.query_one("#command", Input)
        if command.has_focus:
            if command.value:
                command.value = ""
            self._list_view().focus()
            return
        if self.search_query:
            self.search_query = ""
            self.request_refresh()
            return
        self._update_topbar()

    def action_cursor_down(self) -> None:
        self._list_view().action_cursor_down()

    def action_cursor_up(self) -> None:
        self._list_view().action_cursor_up()

    def action_cursor_home(self) -> None:
        view = self._list_view()
        if view.children:
            view.index = 0

    def action_cursor_end(self) -> None:
        view = self._list_view()
        if view.children:
            view.index = len(view.children) - 1

    def action_cycle_filter(self) -> None:
        index = FILTERS.index(self.filter_mode)
        self.filter_mode = FILTERS[(index + 1) % len(FILTERS)]
        self.row_keys = []
        self.query_one("#threads", ListView).clear()
        self.request_refresh()
        self._update_topbar()

    def action_open_link(self) -> None:
        view = self._selected_view()
        if not view or not view["link"]:
            self.notify("Selected thread has no link", severity="warning")
            return
        try:
            subprocess.Popen(
                ["xdg-open", str(view["link"])],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError as exc:
            self.notify(f"cannot open link: {exc}", severity="error")

    def action_copy_link(self) -> None:
        view = self._selected_view()
        if not view or not view["link"]:
            self.notify("Selected thread has no link", severity="warning")
            return
        self.copy_to_clipboard(str(view["link"]))
        self.notify("link copied", timeout=2)

    def _run_action(self, line: str) -> None:
        threading.Thread(
            target=self._command_worker,
            args=(line, self.current_key),
            name="hermes-action",
            daemon=True,
        ).start()

    def action_done(self) -> None:
        if self.current_key:
            self._run_action("done")

    def action_important(self) -> None:
        if self.current_key:
            self._run_action("important")

    def action_follow(self) -> None:
        view = self._selected_view()
        if view:
            self._run_action("unfollow" if view.get("followed") else "follow")

    def action_snooze(self) -> None:
        if not self.current_key:
            return

        def apply(choice: str | None) -> None:
            if choice:
                self._run_action(f"snooze {choice}")

        self.push_screen(ChoiceScreen("Snooze this thread", SNOOZE_CHOICES), apply)

    def action_remind(self) -> None:
        if not self.current_key:
            return

        def apply(choice: str | None) -> None:
            if choice:
                self._run_action(f"remind {choice}")

        self.push_screen(ChoiceScreen("Reminder cadence", REMIND_CHOICES), apply)

    def action_track(self) -> None:
        command = self.query_one("#command", Input)
        command.value = "track "
        command.focus()
        command.cursor_position = len(command.value)

    def action_ask(self) -> None:
        command = self.query_one("#command", Input)
        command.value = "ask "
        command.focus()
        command.cursor_position = len(command.value)


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if any(arg in {"-h", "--help"} for arg in args):
        print("hermes-tui — tracked threads, live job steps and the Hermes command line.")
        print("Run it in a terminal; press ? inside the app for the command and key reference.")
        return 0
    if any(arg in {"-V", "--version"} for arg in args):
        print(f"hermes-tui {__version__}")
        return 0
    app = HermesTUI()
    try:
        app.run()
    except KeyboardInterrupt:
        return 130
    except Exception as exc:
        print(f"hermes-tui: {exc.__class__.__name__}: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
