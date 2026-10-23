"""``hermes-tui`` — textual dashboard for tracked threads and running jobs.

Left: tracked threads (priority, age, cadence, kind, waiting-on-you).
Right: the selected thread's detail plus job steps streamed over SSE.
Bottom: the same command words as the Slack control surface.

Everything network-facing runs off the UI thread; when the API is down the app
shows a reconnect banner, retries every few seconds and never raises.
"""

from __future__ import annotations

import subprocess
import sys
import threading
import time
from typing import Any

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.screen import ModalScreen
from textual.widgets import DataTable, Footer, Header, Input, RichLog, Static

from . import __version__
from .client import HermesClient, HermesError, HermesUnreachable
from .commands import HELP_TEXT, Result, run_command
from .config import ConfigError, load_config
from .format import job_status, step_line, thread_view

REFRESH_SECONDS = 5.0


def _escape(value: object) -> str:
    """Escape Rich markup without importing rich directly.

    ``textual`` vendors rich and its log/static widgets read rich markup;
    a backslash before the bracket is the documented way to keep user text
    (Slack titles are full of [brackets]) literal.
    """
    return str(value).replace("[", "\\[")


CSS = """
Screen {
    background: #0b1016;
    color: #d7e3e0;
}
Header {
    background: #101815;
    color: #72e4ae;
}
Footer {
    background: #101815;
    color: #8ca098;
}
#body {
    height: 1fr;
}
#left {
    width: 46%;
    border-right: solid #2f3d42;
}
#right {
    width: 1fr;
}
#left-title, #right-title {
    height: 1;
    padding: 0 1;
    color: #72e4ae;
    text-style: bold;
}
#threads {
    height: 1fr;
    background: #0e1512;
}
#threads > .datatable--cursor {
    background: #1f3a30;
    color: #f3f8f5;
}
#threads > .datatable--header {
    background: #16211c;
    color: #9bb5aa;
}
#banner {
    height: auto;
    padding: 0 1;
    color: #ff7b86;
    background: #2a1418;
}
#status {
    height: auto;
    padding: 0 1;
    color: #8ca098;
    background: #101815;
}
#detail {
    height: auto;
    max-height: 16;
    padding: 1 2;
    background: #101815;
    border-bottom: solid #2f3d42;
}
#steps {
    height: 1fr;
    padding: 0 1;
    background: #0b1016;
}
#command {
    dock: bottom;
    background: #16211c;
    border-top: solid #3f6b58;
    color: #f3f8f5;
}
#command:focus {
    border-top: solid #72e4ae;
}
#help {
    padding: 2 4;
    width: 78;
    height: auto;
    max-height: 90%;
    background: #101815;
    border: solid #3f6b58;
    color: #d7e3e0;
}
HelpScreen {
    align: center middle;
    background: #9905080e;
}
"""


class HelpScreen(ModalScreen):
    """The ``?`` overlay."""

    BINDINGS = [Binding("escape,q,question_mark,enter", "dismiss", "Close")]

    def compose(self) -> ComposeResult:
        yield Static(HELP_TEXT, id="help", markup=False)

    def action_dismiss(self) -> None:
        self.app.pop_screen()


class HermesTUI(App):
    TITLE = "Hermes"
    SUB_TITLE = "tracked threads · jobs · remote"
    CSS = CSS
    BINDINGS = [
        Binding("q", "quit_app", "Quit"),
        Binding("ctrl+q", "quit_app", "Quit", show=False),
        Binding("question_mark", "help", "Help"),
        Binding("r", "refresh", "Refresh"),
        Binding("i", "focus_command", "Command"),
        Binding("slash", "focus_command", "Command", show=False),
        Binding("o", "open_link", "Open"),
        Binding("escape", "blur_command", "", show=False),
    ]

    def __init__(self) -> None:
        super().__init__()
        self.client: HermesClient | None = None
        self._client_lock = threading.Lock()
        self._refreshing = False
        self._stopping = False
        self._stream: Any = None
        self.last_event_id = 0
        self.threads: list[dict[str, Any]] = []
        self.views: list[dict[str, Any]] = []
        self.row_keys: list[str] = []
        self.current_key: str | None = None
        self.search_query = ""
        self.active_job: str | None = None
        self.jobs: dict[str, dict[str, Any]] = {}
        self.config_error = ""

    # -- layout -----------------------------------------------------------

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        with Horizontal(id="body"):
            with Vertical(id="left"):
                yield Static("TRACKED THREADS", id="left-title")
                yield DataTable(id="threads")
                yield Static("", id="banner", markup=False)
                yield Static("starting…", id="status", markup=False)
            with Vertical(id="right"):
                yield Static("DETAIL · LIVE JOB STEPS", id="right-title")
                yield Static("", id="detail", markup=True)
                yield RichLog(id="steps", highlight=False, markup=True, wrap=True)
        yield Input(placeholder="command — track/ask/remind/… · ? for help", id="command")
        yield Footer()

    def on_mount(self) -> None:
        table = self.query_one("#threads", DataTable)
        table.cursor_type = "row"
        table.zebra_stripes = True
        table.add_columns("P", "Thread", "Age", "Cadence", "Kind", "W")
        table.focus()
        self.request_refresh()
        self.set_interval(REFRESH_SECONDS, self.request_refresh)
        threading.Thread(target=self._stream_thread, name="hermes-sse", daemon=True).start()

    def on_unmount(self) -> None:
        self._stopping = True
        if self._stream is not None:
            try:
                self._stream.stop()
            except Exception:
                pass

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
        except Exception:
            pass

    # -- SSE --------------------------------------------------------------

    def _stream_thread(self) -> None:
        while not self._stopping:
            client = self.ensure_client()
            if client is None:
                self._safe_call(self.set_banner, f"not configured: {self.config_error}", True)
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
            except Exception as exc:  # EventStream swallows, this is belt and braces
                self._safe_call(self.set_banner, f"event stream error: {exc}", True)
            finally:
                stream.stop()
                self._stream = None
            if self._stopping:
                break
            time.sleep(2)

    def apply_stream_state(self, state: dict[str, Any]) -> None:
        self.last_event_id = max(self.last_event_id, int(state.get("since") or 0))
        if state.get("connected"):
            self.set_banner("", False)
        else:
            self.set_banner(f"API unreachable — retrying: {state.get('error') or 'offline'}", True)

    def set_banner(self, text: str, visible: bool) -> None:
        banner = self.query_one("#banner", Static)
        banner.update(text or "")
        banner.styles.display = "block" if visible and text else "none"

    def set_status(self, text: str) -> None:
        self.query_one("#status", Static).update(text)

    # -- thread list ------------------------------------------------------

    def request_refresh(self) -> None:
        if self._refreshing:
            return
        self._refreshing = True
        threading.Thread(target=self._refresh_worker, name="hermes-threads", daemon=True).start()

    def _refresh_worker(self) -> None:
        try:
            client = self.ensure_client()
            if client is None:
                self._safe_call(self.set_banner, f"not configured: {self.config_error}", True)
                return
            threads = client.threads("tracked", limit=100)
            self._safe_call(self.apply_threads, threads)
        except HermesUnreachable as exc:
            self._safe_call(self.set_banner, f"API unreachable — retrying: {exc}", True)
            self._safe_call(self.set_status, "no thread data — API unreachable")
        except HermesError as exc:
            self._safe_call(self.set_banner, f"API error: {exc}", True)
            self._safe_call(self.set_status, "no thread data — API error")
        except Exception as exc:
            self._safe_call(self.set_banner, f"refresh failed: {exc.__class__.__name__}: {exc}", True)
            self._safe_call(self.set_status, "no thread data — refresh failed")
        finally:
            self._refreshing = False

    def apply_threads(self, threads: list[dict[str, Any]]) -> None:
        self.threads = threads
        views = [thread_view(thread) for thread in threads]
        if self.search_query:
            needle = self.search_query.lower()
            views = [
                view
                for view in views
                if needle
                in " ".join(
                    [
                        view["summary"],
                        view["key"],
                        view["kind"],
                        view["note"],
                        view["channel_name"],
                    ]
                ).lower()
            ]
        views.sort(
            key=lambda view: (
                not view["waiting"],
                -float(view["priority"] or 0),
                view["age_seconds"] if view["age_seconds"] is not None else 1e12,
            )
        )
        self.views = views
        table = self.query_one("#threads", DataTable)
        previous = self.current_key
        table.clear(columns=False)
        self.row_keys = []
        for view in views:
            summary = view["summary"]
            if len(summary) > 70:
                summary = summary[:69] + "…"
            table.add_row(
                view["priority_label"] + ("!" if view["importance"] else ""),
                summary,
                view["age"],
                view["cadence"],
                view["kind"],
                "●" if view["waiting"] else "·",
                key=view["key"],
            )
            self.row_keys.append(view["key"])

        if previous in self.row_keys:
            table.move_cursor(row=self.row_keys.index(previous))
        elif self.row_keys:
            table.move_cursor(row=0)
        else:
            self.current_key = None
            self.show_detail(None)

        waiting = sum(1 for view in views if view["waiting"])
        jobs_running = sum(1 for job in self.jobs.values() if job_status(job) in {"running", "pending", "queued"})
        suffix = f" · filter {self.search_query!r}" if self.search_query else ""
        self.set_status(
            f"{len(views)} tracked · {waiting} waiting · {jobs_running} job(s) running{suffix}"
        )
        if views:
            self.set_banner("", False)
        if self.row_keys:
            if self.current_key not in self.row_keys:
                self.current_key = self.row_keys[0]
            self.show_detail(self.current_key)

    def show_detail(self, key: str | None) -> None:
        detail = self.query_one("#detail", Static)
        view = next((item for item in self.views if item["key"] == key), None)
        if view is None:
            detail.update("[#8ca098]Select a tracked thread.  [b]i[/b] opens the command line, [b]?[/b] the help.[/#8ca098]")
            return
        lines = [
            f"[b #f3f8f5]{_escape(view['summary'])}[/]",
            f"[#8ca098]{_escape(view['key'])}[/]",
        ]
        meta = [
            f"prio {view['priority_label']}",
            f"age {view['age']}",
            f"cadence {view['cadence']}",
            f"kind {view['kind']}",
            "WAITING ON YOU" if view["waiting"] else "waiting on them",
        ]
        if view["importance"]:
            meta.append("important")
        lines.append("[#72d7ff]" + _escape(" · ".join(meta)) + "[/]")
        if view["status"]:
            lines.append(f"[#9bb5aa]status[/] {_escape(view['status'])}")
        if view["link"]:
            lines.append(f"[#9bb5aa]link[/]   {_escape(view['link'])}")
        if view["note"]:
            lines.append(f"[#9bb5aa]note[/]   {_escape(view['note'])}")
        lines.append(
            "[#67827a]o open · remind/snooze/done/important/follow act on this thread[/#67827a]"
        )
        detail.update("\n".join(lines))

    def on_data_table_row_highlighted(self, event: DataTable.RowHighlighted) -> None:
        index = event.cursor_row
        if 0 <= index < len(self.row_keys):
            self.current_key = self.row_keys[index]
            self.show_detail(self.current_key)

    def on_data_table_row_selected(self, event: DataTable.RowSelected) -> None:
        self.action_open_link()

    # -- events -----------------------------------------------------------

    def handle_event(self, event: dict[str, Any]) -> None:
        event_type = str(event.get("type") or "")
        payload = event.get("payload") if isinstance(event.get("payload"), dict) else {}
        log = self.query_one("#steps", RichLog)

        if event_type in {"notify", "reminder"}:
            title = str(payload.get("title") or "Still waiting")
            body = str(payload.get("body") or payload.get("summary") or "")
            log.write(f"[#72e4ae]● {_escape(title)}[/] {_escape(body)}")
            try:
                self.notify(body or title, title=title, timeout=8)
            except Exception:
                pass

        elif event_type == "job.step":
            job_id = str(payload.get("job_id") or "")
            line = step_line(payload)
            log.write(f"[#72d7ff]→[/] {_escape(line)}")
            if job_id:
                job = self.jobs.setdefault(job_id, {"id": job_id, "steps": []})
                job.setdefault("steps", []).append({"label": line})
                job["status"] = "running"
                if self.active_job is None:
                    self.active_job = job_id

        elif event_type == "job.done":
            job_id = str(payload.get("job_id") or "")
            ok = payload.get("ok", True)
            result = payload.get("result")
            error = payload.get("error")
            colour = "#72e4ae" if ok else "#ff7b86"
            label = "done" if ok else "failed"
            log.write(f"[{colour}]■ job {_escape(job_id or '?')} {label}[/]")
            if result:
                log.write(_escape(str(result)))
            if error:
                log.write(f"[#ff7b86]{_escape(str(error))}[/]")
            if job_id:
                self.jobs.setdefault(job_id, {"id": job_id}).update(
                    {"status": "done" if ok else "error", "result": result, "error": error}
                )
                if self.active_job == job_id:
                    self.active_job = None
            self.request_refresh()

        elif event_type == "thread.update":
            key = str(payload.get("key") or "")
            if key:
                log.write(f"[#8ca098]thread {_escape(key)} {_escape(str(payload.get('status') or 'updated'))}[/]")
            self.request_refresh()

        if isinstance(event.get("id"), int):
            self.last_event_id = max(self.last_event_id, int(event["id"]))

    # -- commands ---------------------------------------------------------

    def on_input_submitted(self, event: Input.Submitted) -> None:
        line = event.value.strip()
        event.input.value = ""
        self.query_one("#threads", DataTable).focus()
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
            self._safe_call(self.apply_result, line, Result(output=f"error: {self.config_error}", error=True))
            return
        try:
            result = run_command(client, line, current_key=current_key)
        except Exception as exc:
            result = Result(output=f"error: {exc.__class__.__name__}: {exc}", error=True)
        self._safe_call(self.apply_result, line, result)

    def apply_result(self, line: str, result: Result) -> None:
        log = self.query_one("#steps", RichLog)
        if line:
            log.write(f"[#3f6b58]› {_escape(line)}[/]")
        if result.output:
            colour = "#ff7b86" if result.error else "#d7e3e0"
            for chunk in result.output.splitlines() or [""]:
                log.write(f"[{colour}]{_escape(chunk)}[/]")
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
            log.write(f"[#72d7ff]■ job {_escape(str(result.job_id))} streaming…[/]")
        if result.refresh:
            self.request_refresh()

    # -- actions ----------------------------------------------------------

    def action_quit_app(self) -> None:
        self.exit()

    def action_help(self) -> None:
        self.push_screen(HelpScreen())

    def action_refresh(self) -> None:
        self.request_refresh()

    def action_focus_command(self) -> None:
        self.query_one("#command", Input).focus()

    def action_blur_command(self) -> None:
        command = self.query_one("#command", Input)
        if command.has_focus:
            self.query_one("#threads", DataTable).focus()

    def action_open_link(self) -> None:
        view = next((item for item in self.views if item["key"] == self.current_key), None)
        if not view or not view["link"]:
            self.notify("Selected thread has no link", severity="warning")
            return
        try:
            subprocess.Popen(
                ["xdg-open", view["link"]],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError as exc:
            self.notify(f"cannot open link: {exc}", severity="error")


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
