"""Keep herdr tab labels in sync with their pane's terminal title.

Like tmux automatic-rename: a tab is auto-managed while its label is the
default number or the last title we set; a manual rename opts it out.
"""
import json
import os
import socket
import time
from pathlib import Path

SOCK = os.environ.get("HERDR_SOCKET_PATH") or str(Path.home() / ".config/herdr/herdr.sock")
STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "herdr-autoname.json"
MAX_LEN = 50
EVENTS = ["pane.updated", "pane.focused", "pane.closed", "pane.agent_detected", "tab.created", "tab.renamed"]


def call(method, **params):
    with socket.socket(socket.AF_UNIX) as s:
        s.connect(SOCK)
        s.sendall((json.dumps({"id": method, "method": method, "params": params}) + "\n").encode())
        resp = json.loads(s.makefile().readline())
    if "error" in resp:
        raise RuntimeError(resp["error"])
    return resp["result"]


def load_state():
    try:
        return json.loads(STATE.read_text())
    except (OSError, ValueError):
        return None


def save_state(auto):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(auto))


def title_for(panes):
    candidates = [p for p in panes if p.get("agent")] or [p for p in panes if p.get("focused")] or panes
    return (candidates[0].get("terminal_title_stripped") or "").strip()[:MAX_LEN] if candidates else ""


def reconcile(auto):
    tabs = call("tab.list")["tabs"]
    by_tab = {}
    for pane in call("pane.list")["panes"]:
        by_tab.setdefault(pane["tab_id"], []).append(pane)
    live = {t["tab_id"] for t in tabs}
    for tab_id in [k for k in auto if k not in live]:
        del auto[tab_id]
    for tab in tabs:
        tab_id, label = tab["tab_id"], tab["label"]
        if not label.isdigit() and auto.get(tab_id) != label:
            continue
        want = title_for(by_tab.get(tab_id, []))
        if want and want != label:
            call("tab.rename", tab_id=tab_id, label=want)
        auto[tab_id] = want or label
    save_state(auto)


def main():
    auto = load_state()
    titles = {}
    while True:
        try:
            with socket.socket(socket.AF_UNIX) as s:
                s.connect(SOCK)
                req = {"id": "autoname", "method": "events.subscribe",
                       "params": {"subscriptions": [{"type": t} for t in EVENTS]}}
                s.sendall((json.dumps(req) + "\n").encode())
                stream = s.makefile()
                stream.readline()
                if auto is None:
                    # first run: adopt every existing tab as auto-managed
                    auto = {t["tab_id"]: t["label"] for t in call("tab.list")["tabs"]}
                titles.clear()
                reconcile(auto)
                for line in stream:
                    event = json.loads(line)
                    if "error" in event:
                        break
                    pane = (event.get("data") or {}).get("pane")
                    if event.get("event") == "pane_updated" and pane:
                        title = pane.get("terminal_title_stripped")
                        if titles.get(pane["pane_id"]) == title:
                            continue
                        titles[pane["pane_id"]] = title
                    reconcile(auto)
        except (OSError, ValueError, RuntimeError, KeyError):
            pass
        time.sleep(3)


if __name__ == "__main__":
    main()
