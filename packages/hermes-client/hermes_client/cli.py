"""``hermes`` — the non-interactive CLI.

Every command understands ``--json``.  Exit codes:

0   success
1   the API answered with an error
2   usage error (argparse)
3   the API is unreachable
4   configuration/token problem
130 interrupted
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import sys
import time
from dataclasses import replace
from typing import Any, Iterable, Sequence

from . import __version__, store
from .client import EventStream, HermesClient, HermesError, HermesUnreachable
from .commands import parse_track_command, parse_track_spec
from .config import ConfigError, load_config, normalize_url
from .format import (
    cadence_text,
    fmt_duration,
    fmt_epoch,
    job_status,
    job_steps,
    job_title,
    parse_duration,
    step_line,
    thread_view,
)

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_UNREACHABLE = 3
EXIT_CONFIG = 4


def eprint(*args: Any) -> None:
    print(*args, file=sys.stderr)


def emit_json(payload: Any) -> None:
    print(json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False, default=str))


def human_table(headers: Sequence[str], rows: Iterable[Sequence[str]], gap: int = 2) -> str:
    rows = [[str(cell) for cell in row] for row in rows]
    if not rows:
        return ""
    widths = [len(header) for header in headers]
    for row in rows:
        for index, cell in enumerate(row[: len(widths)]):
            widths[index] = max(widths[index], len(cell))
    lines = [
        (" " * gap).join(header.ljust(widths[index]) for index, header in enumerate(headers)).rstrip()
    ]
    for row in rows:
        lines.append(
            (" " * gap)
            .join(cell.ljust(widths[index]) for index, cell in enumerate(row[: len(widths)])).rstrip()
        )
    return "\n".join(lines)


def thread_rows(threads: list[dict[str, Any]]) -> str:
    views = [thread_view(thread) for thread in threads]
    if not views:
        return "no tracked threads"
    rows = []
    for view in views:
        key = view["key"]
        if len(key) > 30:
            key = f"…{key[-29:]}"
        flags = "!"
        if view["importance"]:
            flags += "*"
        else:
            flags = flags.strip() or " "
        waiting = "●" if view["waiting"] else "·"
        summary = view["summary"]
        if len(summary) > 96:
            summary = summary[:95] + "…"
        rows.append(
            [
                key,
                view["priority_label"],
                view["age"],
                view["cadence"],
                view["kind"],
                flags,
                waiting,
                summary,
            ]
        )
    return human_table(["KEY", "P", "AGE", "CAD", "KIND", "*", "W", "SUMMARY"], rows)


def job_rows(jobs: list[dict[str, Any]]) -> str:
    if not jobs:
        return "no jobs"
    rows = []
    for job in jobs:
        job_id = str(job.get("id") or job.get("job_id") or "?")
        started = job.get("started") or job.get("created")
        started_text = time.strftime("%H:%M", time.localtime(float(started))) if started else "-"
        title = job_title(job)
        if len(title) > 88:
            title = title[:87] + "…"
        rows.append([job_id, job_status(job), started_text, title])
    return human_table(["ID", "STATUS", "START", "TITLE"], rows)


def render_job(job: dict[str, Any]) -> str:
    lines = [
        f"job      {job.get('id') or job.get('job_id') or '?'}",
        f"status   {job_status(job)}",
        f"title    {job_title(job)}",
        f"started  {fmt_epoch(job.get('started') or job.get('created'))}",
        f"finished {fmt_epoch(job.get('finished'))}",
    ]
    steps = job_steps(job)
    if steps:
        lines.append("steps")
        for step in steps:
            lines.append(f"  · {step_line(step)}")
    if job.get("result"):
        lines.append("result")
        lines.append(str(job["result"]))
    if job.get("error"):
        lines.append("error")
        lines.append(str(job["error"]))
    return "\n".join(lines)


def make_client(args: argparse.Namespace) -> HermesClient:
    config = load_config()
    if getattr(args, "api_url", None):
        config = replace(config, api_url=normalize_url(args.api_url))
    if getattr(args, "token_file", None):
        token_path = os.path.expanduser(args.token_file)
        try:
            with open(token_path, encoding="utf-8") as handle:
                token = handle.read().strip()
        except OSError as exc:
            raise ConfigError(f"cannot read token file {token_path}: {exc.strerror or exc}") from exc
        if not token:
            raise ConfigError(f"token file {token_path} is empty")
        config = replace(config, token=token, token_file=token_path)
    return HermesClient.from_config(config)


# -- command handlers -----------------------------------------------------


def cmd_ask(api: HermesClient, args: argparse.Namespace) -> int:
    if not args.question:
        eprint("hermes: ask needs a question")
        return 2
    question = " ".join(args.question)
    created = api.ask(
        question,
        thread_key=args.thread,
        conversation=args.conversation or None,
        mode=getattr(args, "mode", "ask"),
    )
    job_id = api.job_id(created)
    if not job_id:
        if args.json:
            emit_json(created)
        else:
            eprint("hermes: the server did not return a job id")
        return EXIT_ERROR
    if args.json and args.wait:
        job = api.wait_for_job(job_id, timeout=args.timeout)
        emit_json(job)
        return EXIT_OK
    if args.json or not args.wait:
        if args.json:
            emit_json({"job_id": job_id})
        else:
            print(job_id)
        return EXIT_OK

    def report(step: dict[str, Any]) -> None:
        print(f"· {step_line(step)}", flush=True)

    job = api.wait_for_job(job_id, on_step=report, timeout=args.timeout)
    status = job_status(job)
    if job.get("result"):
        print(str(job["result"]).rstrip())
    elif job.get("error"):
        eprint(f"hermes: job {job_id} {status}: {job['error']}")
    return EXIT_OK if status not in {"error", "failed", "cancelled", "canceled"} else EXIT_ERROR


def cmd_list(api: HermesClient, args: argparse.Namespace) -> int:
    threads = api.threads(args.filter, limit=args.limit)
    if args.json:
        emit_json(threads)
    else:
        print(thread_rows(threads))
    return EXIT_OK


def cmd_track(api: HermesClient, args: argparse.Namespace) -> int:
    spec, cadence = parse_track_command(" ".join(args.spec))
    if args.cadence:
        cadence = args.cadence
    payload = parse_track_spec(spec)
    if cadence:
        payload["cadence"] = cadence
    if args.important:
        payload["important"] = True
    if args.note:
        payload["note"] = args.note
    if args.title:
        payload["title"] = args.title
    created = api.create_thread(**payload)
    if args.json:
        emit_json(created)
    else:
        view = thread_view(created if isinstance(created, dict) else {})
        key = view["key"] or created.get("key") or spec
        print(f"tracked {key}" + (f" every {cadence}" if cadence else ""))
        if view["link"]:
            print(view["link"])
    return EXIT_OK


def cmd_untrack(api: HermesClient, args: argparse.Namespace) -> int:
    api.delete_thread(args.key)
    if args.json:
        emit_json({"key": args.key, "tracked": False})
    else:
        print(f"untracked {args.key}")
    return EXIT_OK


def cmd_remind(api: HermesClient, args: argparse.Namespace) -> int:
    if args.thread:
        if not args.value:
            view = thread_view(api.thread(args.thread))
            if args.json:
                emit_json({"key": args.thread, "cadence": view["cadence"]})
            else:
                print(f"{args.thread}: reminders every {view['cadence']}")
            return EXIT_OK
        label = _cadence_label(args.value)
        updated = api.patch_thread(args.thread, cadence=label)
        if args.json:
            emit_json(updated)
        else:
            print(f"{args.thread}: reminders every {label}")
        return EXIT_OK

    if not args.value:
        state = api.state()
        default = state.get("cadence") or state.get("default_cadence")
        if args.json:
            emit_json({"default": default})
        else:
            print(f"default reminder cadence: {cadence_text(default)}")
        return EXIT_OK
    label = _cadence_label(args.value)
    try:
        result = api.set_global_cadence(label)
    except HermesError as exc:
        if exc.status in (404, 405):
            eprint(
                "hermes: the server has no global cadence endpoint yet; "
                "use `hermes remind --thread <key> <value>`"
            )
            return EXIT_ERROR
        raise
    if args.json:
        emit_json(result or {"cadence": label})
    else:
        print(f"default reminder cadence set to {label}")
    return EXIT_OK


def _cadence_label(value: str) -> str:
    seconds = parse_duration(value)
    if seconds is None:
        return "default"
    return "off" if seconds == 0 else fmt_duration(seconds)


def cmd_task(api: HermesClient, args: argparse.Namespace) -> int:
    text = " ".join(args.text)
    created = api.create_task(text, project=args.project)
    if args.json:
        emit_json(created)
    else:
        title = created.get("title") or created.get("summary") or text
        url = created.get("url") or created.get("link") or ""
        print(f"task created: {title}")
        if url:
            print(url)
    return EXIT_OK


def cmd_jira(api: HermesClient, args: argparse.Namespace) -> int:
    text = " ".join(args.text)
    created = api.create_task(text, project=args.project, kind="jira")
    if args.json:
        emit_json(created)
    else:
        key = created.get("key") or ""
        url = created.get("url") or ""
        print(f"jira issue created: {key}".strip())
        if url:
            print(url)
    return EXIT_OK


def cmd_status(api: HermesClient, args: argparse.Namespace) -> int:
    health = api.health()
    state = api.state()
    tracked = api.threads("tracked", limit=100)
    bridge = store.load_bridge()
    waiting = sum(1 for thread in tracked if thread_view(thread)["waiting"])
    default_cadence = cadence_text(
        state.get("cadence") or state.get("default_cadence") or state.get("cadence_defaults")
    )
    payload = {
        "health": health,
        "state": state,
        "tracked": len(tracked),
        "waiting": waiting,
        "default_cadence": default_cadence,
        "unread": bridge.get("unread", 0),
    }
    if args.json:
        emit_json(payload)
        return EXIT_OK
    uptime = health.get("uptime_seconds")
    state_age = health.get("state_age")
    print(f"hermes   {health.get('version') or '-'}   ok={health.get('ok', '?')}")
    print(f"api      {api.api_url}")
    print(f"uptime   {fmt_duration(uptime) if isinstance(uptime, (int, float)) else '-'}")
    state_text = f"{int(state_age)}s old" if isinstance(state_age, (int, float)) else "-"
    print(f"state    {state_text}")
    print(f"tracked  {len(tracked)} threads · {waiting} waiting on you")
    print(f"cadence  {default_cadence}")
    print(f"unread   {bridge.get('unread', 0)} notifications")
    return EXIT_OK


def cmd_jobs(api: HermesClient, args: argparse.Namespace) -> int:
    if args.cancel:
        if not args.job:
            eprint("hermes: jobs --cancel needs a job id")
            return 2
        api.cancel_job(args.job)
        if args.json:
            emit_json({"id": args.job, "cancelled": True})
        else:
            print(f"cancelled {args.job}")
        return EXIT_OK
    if args.job:
        job = api.job(args.job)
        if args.json:
            emit_json(job)
        else:
            print(render_job(job))
        return EXIT_OK
    jobs = api.jobs()
    if args.json:
        emit_json(jobs)
    else:
        print(job_rows(jobs))
    return EXIT_OK


def cmd_remote(api: HermesClient, args: argparse.Namespace) -> int:
    command = " ".join(args.command)
    created = api.remote_run(command, timeout=args.timeout)
    job_id = api.job_id(created)
    if args.json:
        if job_id and args.wait:
            emit_json(api.wait_for_job(job_id, timeout=args.timeout or 900.0))
        else:
            emit_json(created)
        return EXIT_OK
    output = created.get("output") if isinstance(created, dict) else None
    if output:
        print(str(output).rstrip())
        return EXIT_OK
    if not job_id:
        eprint("hermes: remote request returned neither output nor a job id")
        return EXIT_ERROR
    if not args.wait:
        print(job_id)
        return EXIT_OK

    def report(step: dict[str, Any]) -> None:
        print(f"· {step_line(step)}", flush=True)

    job = api.wait_for_job(job_id, on_step=report, timeout=args.timeout or 900.0)
    if job.get("result"):
        print(str(job["result"]).rstrip())
    if job.get("error"):
        eprint(f"hermes: remote job {job_id} failed: {job['error']}")
        return EXIT_ERROR
    return EXIT_OK


def cmd_notify(api: HermesClient, args: argparse.Namespace) -> int:
    api.notify(" ".join(args.text), title=args.title, urgency=args.urgency)
    if args.json:
        emit_json({"ok": True})
    else:
        print("notification sent")
    return EXIT_OK


def cmd_watch(api: HermesClient, args: argparse.Namespace) -> int:
    stop = EventStream(api, since=args.since, max_backoff=30.0)
    connected_once = False
    failed = False

    def on_state(state: dict[str, Any]) -> None:
        nonlocal connected_once, failed
        if state.get("connected"):
            connected_once = True
        elif not connected_once and not failed:
            failed = True
            eprint(f"hermes: {state.get('error') or 'cannot reach the API'}")
            stop.stop()

    stop.set_state_callback(on_state)
    code = EXIT_OK
    try:
        for event in stop:
            if not connected_once:
                connected_once = True
            if args.json:
                print(json.dumps(event, ensure_ascii=False, default=str), flush=True)
                continue
            event_id = event.get("id", "?")
            event_type = event.get("type", "?")
            payload = event.get("payload") or {}
            print(f"[{event_id}] {event_type}  {json.dumps(payload, ensure_ascii=False, default=str)}", flush=True)
    except KeyboardInterrupt:
        pass
    finally:
        stop.stop()
    if failed:
        code = EXIT_UNREACHABLE
    return code


def cmd_read(args: argparse.Namespace) -> int:
    bridge = store.mark_read()
    if args.json:
        emit_json({"unread": bridge.get("unread", 0)})
    else:
        print("unread cleared")
    return EXIT_OK


# -- parser ---------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true", default=argparse.SUPPRESS, help="machine-readable output")

    parser = argparse.ArgumentParser(
        prog="hermes",
        description="Talk to the Hermes agent on the odroid (tracking, jobs, remote builds).",
        epilog="Commands mirror the Slack control surface; `hermes-tui` is the interactive version.",
    )
    parser.add_argument("--version", action="version", version=f"hermes {__version__}")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument("--api-url", help="override HERMES_API_URL")
    parser.add_argument("--token-file", help="override HERMES_API_TOKEN_FILE")
    sub = parser.add_subparsers(dest="command", required=True)

    ask = sub.add_parser("ask", parents=[common], help="ask the agent (job steps streamed)")
    ask.add_argument("question", nargs="+")
    ask.add_argument("--thread", help="thread key to attach the conversation to")
    ask.add_argument("--conversation", help="continue an existing conversation id")
    ask.add_argument(
        "--mode",
        choices=["ask", "investigate", "draft"],
        default="ask",
        help="deep dive or draft a reply for --thread",
    )
    ask.add_argument("--no-wait", dest="wait", action="store_false", help="print the job id and exit")
    ask.add_argument("--timeout", type=float, default=900.0)
    ask.set_defaults(handler=cmd_ask, wait=True)

    listing = sub.add_parser("list", parents=[common], help="list threads")
    listing.add_argument(
        "--filter", choices=["tracked", "followed", "all", "done"], default="tracked"
    )
    listing.add_argument("--limit", type=int, default=50)
    listing.set_defaults(handler=cmd_list)

    track = sub.add_parser("track", parents=[common], help="track a Slack/Jira/PR thread")
    track.add_argument("spec", nargs="+", help="URL or <channel>:<thread_ts> [every 1d]")
    track.add_argument("--cadence", help="reminder cadence, e.g. 6h or off")
    track.add_argument("--important", action="store_true")
    track.add_argument("--note")
    track.add_argument("--title")
    track.set_defaults(handler=cmd_track)

    untrack = sub.add_parser("untrack", parents=[common], help="stop tracking a thread")
    untrack.add_argument("key")
    untrack.set_defaults(handler=cmd_untrack)

    remind = sub.add_parser("remind", parents=[common], help="per-thread or default reminder cadence")
    remind.add_argument("value", nargs="?", help="1d, 6h, off, default (bare = show)")
    remind.add_argument("--thread", help="thread key (omit to use the global default)")
    remind.set_defaults(handler=cmd_remind)

    reminders = sub.add_parser("reminders", parents=[common], help="global default reminder cadence")
    reminders.add_argument("value", nargs="?")
    reminders.set_defaults(handler=cmd_remind, thread=None)

    task = sub.add_parser("task", parents=[common], help="create a Vikunja task from text")
    task.add_argument("text", nargs="+")
    task.add_argument("--project", choices=["personal", "coralogix"])
    task.set_defaults(handler=cmd_task)

    jira = sub.add_parser("jira", parents=[common], help="create a Jira issue from text")
    jira.add_argument("text", nargs="+")
    jira.add_argument("--project", help="Jira project key (default: server config, CX)")
    jira.set_defaults(handler=cmd_jira)

    status = sub.add_parser("status", parents=[common], help="health, counts, cadence")
    status.set_defaults(handler=cmd_status)

    jobs = sub.add_parser("jobs", parents=[common], help="recent jobs or one job's steps")
    jobs.add_argument("job", nargs="?")
    jobs.add_argument("--cancel", action="store_true")
    jobs.set_defaults(handler=cmd_jobs)

    remote = sub.add_parser("remote", parents=[common], help="run a build/test on amd-pc")
    remote.add_argument("command", nargs="+")
    remote.add_argument("--timeout", type=float)
    remote.add_argument("--no-wait", dest="wait", action="store_false")
    remote.set_defaults(handler=cmd_remote, wait=True)

    watch = sub.add_parser("watch", parents=[common], help="stream events (script friendly)")
    watch.add_argument("--since", type=int, default=0)
    watch.set_defaults(handler=cmd_watch)

    notify = sub.add_parser("notify", parents=[common], help="desktop notification via the bridge")
    notify.add_argument("text", nargs="+")
    notify.add_argument("--title", default="Hermes")
    notify.add_argument("--urgency", choices=["low", "normal", "critical"], default="normal")
    notify.set_defaults(handler=cmd_notify)

    read = sub.add_parser("read", parents=[common], help="clear the bridge unread badge")
    read.set_defaults(handler=cmd_read)

    # Every subcommand also accepts the global overrides after the command name.
    for subparser in sub.choices.values():
        subparser.add_argument("--api-url", default=argparse.SUPPRESS, help=argparse.SUPPRESS)
        subparser.add_argument("--token-file", default=argparse.SUPPRESS, help=argparse.SUPPRESS)

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    # `hermes watch | head` should die quietly instead of printing a traceback
    # from the interpreter's shutdown flush.
    try:
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    except (AttributeError, ValueError, OSError):
        pass

    parser = build_parser()
    args = parser.parse_args(argv)
    handler = args.handler

    try:
        if handler is cmd_read:
            return handler(args)
        with make_client(args) as api:
            return handler(api, args)
    except ConfigError as exc:
        eprint(f"hermes: {exc}")
        return EXIT_CONFIG
    except HermesUnreachable as exc:
        eprint(f"hermes: {exc}")
        return EXIT_UNREACHABLE
    except HermesError as exc:
        eprint(f"hermes: {exc}")
        return EXIT_ERROR
    except KeyboardInterrupt:
        return 130
    except BrokenPipeError:
        return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
