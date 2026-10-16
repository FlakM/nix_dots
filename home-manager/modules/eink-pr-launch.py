"""Launch an e-ink PR review from a herdr popup.

You paste a review request — the message plus a link — and this sets up everything
the review needs, then hands off:

    herdr workspace create --cwd <worktree> --label "PR <n>: <title>"
    herdr pane run <pane> eink-review-agent      # opencode mini, seeded with the request

Design rules, so the two entry points (this widget, and `/eink-pr` in an existing
agent session) do not fight each other:

  * one workspace per review, keyed by PR number; re-running reuses it;
  * worktrees live at ~/programming/<org>/worktrees/pr-<n>/<repo>, matching the
    layout already used for ticket work;
  * the handoff prompt is written to a file and passed by environment variable, so
    no shell quoting can corrupt a pasted message;
  * the review is recorded in the same registry the skill reads.

Safe by default: `--dry-run` prints the plan and touches nothing.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
PROGRAMMING = HOME / "programming"
STATE = Path(os.environ.get("EINK_PR_STATE", HOME / ".local/state/eink-bridge"))
REGISTRY = Path(os.environ.get("EINK_PR_REGISTRY", STATE / "pr-reviews.json"))
SEED_DIR = STATE / "seed"
LAST_REPO_HINT = ""
DEFAULT_MODEL = os.environ.get("EINK_REVIEW_MODEL", "opencode-go/deepseek-v4.1-flash")
# Coralogix work needs the internal tooling that only Claude Code carries, so reviews of
# those repositories run in Claude Code. Everything else uses OpenCode with a cheap model.
CLAUDE_ORGS = {o.strip() for o in os.environ.get("EINK_REVIEW_CLAUDE_ORGS", "coralogix").split(",") if o.strip()}
CLAUDE_MODEL = os.environ.get("EINK_REVIEW_CLAUDE_MODEL", "")

GH_PR = re.compile(r"github\.com/([^/\s]+)/([^/\s]+?)(?:\.git)?/pull/(\d+)")
ANY_URL = re.compile(r"https?://\S+")


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def die(message, code=1):
    print(f"error: {message}", file=sys.stderr)
    return code


def read_request():
    """Take the pasted request from stdin. A tty gets a prompt first."""
    if sys.stdin.isatty():
        print("Paste the review request (message + link), then press Ctrl-D:\n")
    return sys.stdin.read()


def repo_slug(url):
    match = GH_PR.search(url)
    if not match:
        return None
    owner, repo, number = match.group(1), match.group(2), int(match.group(3))
    return {"owner": owner, "repo": repo, "number": number}


def find_repo(owner, repo):
    """Locate the checkout on disk.

    Matching the git origin is authoritative; a directory name alone is a guess, and
    guessing the wrong repository would review the wrong code. Local names differ from
    remote ones (cx-web-workspace vs web-workspace), so name closeness is only used to
    suggest candidates in the error message.
    """
    roots = []
    for pattern in ("*/*", "*/*/*"):
        for candidate in PROGRAMMING.glob(pattern):
            if (candidate / ".git").exists():
                roots.append(candidate)

    wanted = f"{owner}/{repo}"
    for candidate in roots:
        origin = run(["git", "-C", str(candidate), "remote", "get-url", "origin"]).stdout.strip()
        if wanted in origin or f"{repo}.git" in origin:
            return candidate

    for candidate in roots:
        if candidate.name == repo:
            return candidate

    import difflib
    names = sorted({candidate.name for candidate in roots})
    close = difflib.get_close_matches(repo, names, n=3, cutoff=0.5)
    global LAST_REPO_HINT
    LAST_REPO_HINT = f" closest local names: {', '.join(close)}" if close else ""
    return None


def repo_owner(repo_root):
    """The owner from the checkout's origin, which is more trustworthy than the URL."""
    origin = run(["git", "-C", str(repo_root), "remote", "get-url", "origin"]).stdout.strip()
    match = re.search(r"[:/]([^/:]+)/([^/]+?)(?:\.git)?$", origin)
    return match.group(1) if match else ""


def choose_agent(owner, override=None):
    if override:
        return override
    return "claude" if owner.lower() in {o.lower() for o in CLAUDE_ORGS} else "opencode"


def worktree_path(repo_root, number):
    return repo_root.parent / "worktrees" / f"pr-{number}" / repo_root.name


def prepare_worktree(repo_root, number, dry=False):
    """Check the PR head out into a worktree, reusing one that already exists."""
    head = f"refs/pull/{number}/head"
    target = worktree_path(repo_root, number)
    if dry:
        return target, "would fetch and check out"
    source = "origin"
    fetched = run(["git", "-C", str(repo_root), "fetch", "origin", head])
    if fetched.returncode != 0:
        # Offline or a synthetic PR: fall back to a local ref of the same name so the
        # flow stays testable without touching a server.
        local = run(["git", "-C", str(repo_root), "rev-parse", "--verify", f"{head}^{{commit}}"])
        if local.returncode != 0:
            return target, f"fetch failed: {fetched.stderr.strip()}"
        source = "local ref"
    ref = "FETCH_HEAD" if source == "origin" else f"refs/pull/{number}/head"
    if (target / ".git").exists():
        run(["git", "-C", str(target), "checkout", "--detach", ref])
        return target, f"reused existing worktree ({source})"
    target.parent.mkdir(parents=True, exist_ok=True)
    created = run(["git", "-C", str(repo_root), "worktree", "add", "--detach", str(target), ref])
    if created.returncode != 0:
        return target, f"worktree add failed: {created.stderr.strip()}"
    return target, f"created worktree ({source})"


def pr_title(url, slug):
    if not slug:
        return None
    view = run(["gh", "pr", "view", url, "--json", "title,baseRefName"])
    if view.returncode == 0:
        try:
            data = json.loads(view.stdout)
            return data.get("title"), data.get("baseRefName")
        except json.JSONDecodeError:
            return None, None
    return None, None


def seed_prompt(url, slug, worktree, context, repo_root, title):
    number = slug["number"] if slug else "unknown"
    lines = [
        f"Review {url} on the e-ink tablet, following the eink-pr skill.",
        "",
        f"- repository checkout: {repo_root}",
        f"- review worktree: {worktree}",
        f"- pull request: {title or 'unknown title'} (#{number})",
        "",
        "This workspace was created for the review, so the worktree already exists.",
        "Follow the skill: open the diff in Neovim, run the lens reviewers in parallel,",
        "filter to the actionable findings, pass them through ihaveadhd, then deliver the",
        "brief to eink and set the marks.",
    ]
    if context.strip():
        lines += ["", "Request from the reviewer:", "", context.strip()]
    return "\n".join(lines) + "\n"


def herdr(*args):
    result = run(["herdr", *args])
    if result.returncode != 0:
        raise RuntimeError(f"herdr {' '.join(args)} failed: {result.stderr.strip()}")
    return json.loads(result.stdout or "{}")


def registry_entry(number, slug, worktree, session=""):
    try:
        payload = json.loads(REGISTRY.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        payload = {"reviews": []}
    key = str(number)
    rows = [row for row in payload.get("reviews", []) if row.get("key") != key]
    rows.append({
        "key": key,
        "pr": key,
        "sha": "",
        "worktree": str(worktree),
        "socket": f"/run/user/{os.getuid()}/jump-{worktree.name}.sock",
        "tab_label": f"PR {number}",
        "title": "",
        "session": session,
        "tab_id": "",
        "pane_id": "",
    })
    REGISTRY.parent.mkdir(parents=True, exist_ok=True)
    REGISTRY.write_text(json.dumps({"reviews": rows}, indent=2) + "\n")


def existing_workspace(label):
    for workspace in herdr("workspace", "list").get("result", {}).get("workspaces", []):
        if workspace.get("label") == label:
            return workspace
    return None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--link", help="skip reading stdin and use this link")
    parser.add_argument("--context", default="", help="review request text")
    parser.add_argument("--model", help="override the model for the chosen agent")
    parser.add_argument("--agent", choices=["claude", "opencode"], help="force the agent kind")
    parser.add_argument("--no-launch", action="store_true", help="prepare worktree and workspace, do not start the agent")
    args = parser.parse_args(argv)

    text = args.context or read_request()
    url_match = ANY_URL.search(args.link or text)
    if not url_match:
        return die("no link found in the request; paste the message with its URL")
    url = url_match.group(0).rstrip(").,")
    slug = repo_slug(url)

    if not slug:
        return die(f"{url} is not a GitHub pull request link")
    context = text.replace(url, "").strip()

    repo_root = find_repo(slug["owner"], slug["repo"])
    if not repo_root:
        return die(f"no local checkout of {slug['owner']}/{slug['repo']} under {PROGRAMMING}.{LAST_REPO_HINT}")
    if not os.environ.get("HERDR_ENV"):
        return die("not running inside a herdr pane")

    worktree, note = prepare_worktree(repo_root, slug["number"], dry=args.dry_run)
    title, base = pr_title(url, slug)
    label = f"PR {slug['number']}: {title}" if title else f"PR {slug['number']}"

    owner = repo_owner(repo_root) or slug["owner"]
    agent_kind = choose_agent(owner, args.agent)
    if args.model:
        model = args.model
    elif agent_kind == "claude":
        model = CLAUDE_MODEL
    else:
        model = DEFAULT_MODEL

    seed_path = SEED_DIR / f"pr-{slug['number']}.md"
    seed = seed_prompt(url, slug, worktree, context, repo_root, title)

    print(f"review    : {label}")
    print(f"repo      : {repo_root}")
    print(f"worktree  : {worktree}  ({note})")
    print(f"base      : {base or 'unknown'}")
    print(f"owner     : {owner}")
    print(f"agent     : {agent_kind}")
    print(f"model     : {model or '(agent default)'}")
    print(f"seed      : {seed_path}")

    if args.dry_run:
        print("\n-- seed prompt --")
        print(seed)
        print("dry run: nothing created")
        return 0

    SEED_DIR.mkdir(parents=True, exist_ok=True)
    seed_path.write_text(seed)

    workspace = existing_workspace(label)
    if workspace:
        print(f"workspace : reusing {workspace['workspace_id']}")
        created = herdr("workspace", "get", workspace["workspace_id"])
    else:
        created = herdr("workspace", "create", "--cwd", str(worktree), "--label", label,
                        "--env", f"EINK_REVIEW_SEED={seed_path}",
                        "--env", f"EINK_REVIEW_AGENT={agent_kind}",
                        "--env", f"EINK_REVIEW_MODEL={model}", "--focus")
        print(f"workspace : {created['result']['workspace']['workspace_id']}")

    pane = created["result"]["root_pane"]["pane_id"]
    registry_entry(slug["number"], slug, worktree)

    if args.no_launch:
        print("prepared only (--no-launch); start manually with:")
        print(f"  herdr pane run {pane} eink-review-agent")
        return 0

    herdr("pane", "run", pane, "eink-review-agent")

    # Report what actually happened: a missing binary or a crashed agent must not be
    # announced as a started review.
    status = wait_for_agent(pane, timeout=15)
    if status == "agent":
        print(f"agent     : started in {pane}")
        print("\nHanded off. The agent will open the diff, review, and put the brief on the tablet.")
        return 0
    output = run(["herdr", "pane", "read", pane, "--source", "visible", "--lines", "6"]).stdout
    print(f"agent     : NOT started ({status})", file=sys.stderr)
    print("pane output:", file=sys.stderr)
    print("  " + output.strip().replace("\n", "\n  "), file=sys.stderr)
    print(f"\nThe workspace and worktree are ready; retry with:\n  herdr pane run {pane} eink-review-agent",
          file=sys.stderr)
    return 1


def wait_for_agent(pane, timeout=15):
    """Wait until herdr reports an agent in the pane, or the shell shows it failed."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            agents = herdr("agent", "list").get("result", {}).get("agents", [])
        except (RuntimeError, json.JSONDecodeError):
            agents = []
        if any(agent.get("pane_id") == pane for agent in agents):
            return "agent"
        output = run(["herdr", "pane", "read", pane, "--source", "visible", "--lines", "8"]).stdout
        if "command not found" in output or "not found" in output:
            return "command not found"
        time.sleep(0.5)
    return "timed out"


if __name__ == "__main__":
    sys.exit(main())
