"""Launch an e-ink PR review from a herdr popup.

You paste a review request — the message plus a link — and this sets up everything
the review needs, then hands off:

    herdr workspace create --cwd <worktree> --label "💻 <repo> PR <n>: <title>"
    herdr pane run <pane> eink-review-agent      # opencode mini, seeded with the request

The flow is deliberately conversational, because a paste can be ambiguous:

  1. parse every pull request in the message, in the order written;
  2. resolve each checkout, asking when one is missing (clone it, pick a local
     checkout, skip it) or when several checkouts match;
  3. show the plan — repo, worktree, base, agent — and wait for Enter;
  4. only then fetch, create worktrees, register workspaces and start the agent.

Nothing is created before the confirmation, and every slow step says what it is doing
and how long it took. `--dry-run` stops after printing the plan and the seed; `--yes`
skips the confirmation but still asks about missing checkouts.

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
import difflib
import json
import os
import re
import shutil
import socket as socket_lib
import subprocess
import sys
import threading
import time
from contextlib import contextmanager
from pathlib import Path

HOME = Path.home()
PROGRAMMING = HOME / "programming"
STATE = Path(os.environ.get("EINK_PR_STATE", HOME / ".local/state/eink-bridge"))
REGISTRY = Path(os.environ.get("EINK_PR_REGISTRY", STATE / "pr-reviews.json"))
SEED_DIR = STATE / "seed"
DEFAULT_MODEL = os.environ.get("EINK_REVIEW_MODEL", "opencode-go/deepseek-v4.1-flash")
# Coralogix work needs the internal tooling that only Claude Code carries, so reviews of
# those repositories run in Claude Code. Everything else uses OpenCode with a cheap model.
CLAUDE_ORGS = {o.strip() for o in os.environ.get("EINK_REVIEW_CLAUDE_ORGS", "coralogix").split(",") if o.strip()}
CLAUDE_MODEL = os.environ.get("EINK_REVIEW_CLAUDE_MODEL", "")

GH_PR = re.compile(r"(?:https?://)?github\.com/([^/\s]+)/([^/\s]+?)(?:\.git)?/pull/(\d+)")
ANY_URL = re.compile(r"https?://\S+")

_REPO_CACHE: dict[tuple[str, str], list[Path]] = {}
CLAUDE_CONFIG = (
    Path(os.environ["CLAUDE_CONFIG_DIR"]) / ".claude.json"
    if os.environ.get("CLAUDE_CONFIG_DIR")
    else HOME / ".claude.json"
)

# The output is read in a popup and often piped; line buffering keeps "what happened"
# in the order it happened instead of flushing stdout after stderr at exit.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(line_buffering=True)


# ── output ───────────────────────────────────────────────────────────────────

RESET, BOLD, DIM = "\033[0m", "\033[1m", "\033[2m"
CYAN, GREEN, YELLOW, RED = "\033[36m", "\033[32m", "\033[33m", "\033[31m"


def colors_enabled():
    if os.environ.get("NO_COLOR"):
        return False
    if os.environ.get("CLICOLOR_FORCE") == "1":
        return True
    return sys.stdout.isatty() and os.environ.get("TERM") != "dumb"


COLOR = colors_enabled()


def paint(text, code):
    return f"{code}{text}{RESET}" if COLOR else text


def bold(text):
    return paint(text, BOLD)


def dim(text):
    return paint(text, DIM)


def cyan(text):
    return paint(text, CYAN)


def green(text):
    return paint(text, GREEN)


def yellow(text):
    return paint(text, YELLOW)


def red(text):
    return paint(text, RED)


def columns():
    return shutil.get_terminal_size((100, 24)).columns


def indent(text, prefix="  "):
    return "\n".join(prefix + line if line.strip() else "" for line in text.splitlines())


def shorten(text, width):
    text = str(text)
    return text if len(text) <= width else text[: max(1, width - 1)] + "…"


def short_path(path):
    text = str(path)
    home = str(HOME)
    return "~" + text[len(home):] if text.startswith(home + "/") else text


def banner():
    print()
    print(f"  {bold('eink-pr')}  {dim('review launcher')}")
    print(f"  {dim('─' * min(columns() - 4, 52))}")


def section(title, note=""):
    suffix = f"  {dim(note)}" if note else ""
    print()
    print(f"  {bold(title)}{suffix}")
    print(f"  {dim('─' * min(columns() - 4, 52))}")


def kv(key, value, note=""):
    suffix = f"  {dim(note)}" if note else ""
    print(f"    {dim(f'{key:<9}')} {value}{suffix}")


def run(cmd, **kwargs):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    except FileNotFoundError:
        # `gh` is optional: a review without a title is still a review.
        return subprocess.CompletedProcess(cmd, 127, "", f"{cmd[0]} is not installed")


def step(message):
    print(f"\n  {cyan('▸')} {bold(message)}", flush=True)


def detail(message):
    print(f"    {message}", flush=True)


@contextmanager
def working(label):
    """One line that starts as work and ends as a result."""
    started = time.time()
    if not COLOR:
        print(f"    {dim('…')} {label}", flush=True)
        try:
            yield
        finally:
            elapsed = time.time() - started
            print(f"    {green('✓')} {label}  {dim(f'{elapsed:.1f}s')}", flush=True)
        return

    frames = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    done = threading.Event()
    tick = {"frame": 0}

    def spin():
        while not done.wait(0.08):
            frame = frames[tick["frame"] % len(frames)]
            tick["frame"] += 1
            sys.stdout.write(f"\r    {cyan(frame)} {label} …")
            sys.stdout.flush()

    sys.stdout.write(f"\r    {cyan(frames[0])} {label} …")
    sys.stdout.flush()
    spinner = threading.Thread(target=spin, daemon=True)
    spinner.start()
    try:
        yield
    finally:
        done.set()
        spinner.join(timeout=0.2)
        elapsed = time.time() - started
        sys.stdout.write(f"\r    {green('✓')} {label}  {dim(f'{elapsed:.1f}s')}\033[K\n")
        sys.stdout.flush()


def die(message, code=1):
    print(f"\n  {red('✗')} {message}", file=sys.stderr)
    return code


# ── input ────────────────────────────────────────────────────────────────────

def read_request():
    """Take the pasted request from stdin. A tty gets an explanation first."""
    if sys.stdin.isatty():
        print("  Paste the review request: the message and its GitHub pull-request link.")
        print(f"  {dim('Finish with Ctrl-D on an empty line.')}")
        print()
    return sys.stdin.read()


def interpret_choice(raw):
    """The one-word answers the launcher accepts, without guessing."""
    choice = raw.strip().lower()
    if choice in ("", "y", "yes", "start"):
        return "start"
    if choice in ("d", "dry", "plan"):
        return "dry"
    if choice in ("q", "quit", "n", "no", "cancel", "c"):
        return "quit"
    return None


def ask(prompt, choices, default=None):
    """Ask until the answer is one of `choices` (a list of (key, label))."""
    for key, label in choices:
        print(f"    {cyan(f'{key:<3}')} {label}")
    while True:
        try:
            raw = input(prompt).strip().lower()
        except EOFError:
            return None
        if not raw and default:
            return default
        for key, _ in choices:
            if raw == key:
                return key
        options = ", ".join(f"[{key}]" for key, _ in choices)
        print(f"    {red('?')} choose one of {options}")


# ── parsing (unchanged: this is the part with tests) ─────────────────────────

def pull_requests(text):
    """Every GitHub pull request in the pasted message, in the order written.

    A message often carries several: "asking for your review for:" followed by two links.
    Each one is a review of its own, and the prose around them is the brief that applies
    to all of them (or to whichever one the message names).
    """
    seen = set()
    found = []
    for match in GH_PR.finditer(text):
        owner, repo, number = match.group(1), match.group(2), match.group(3)
        key = (owner, repo, number)
        if key in seen:
            continue
        seen.add(key)
        found.append({
            "url": match.group(0),
            "owner": owner,
            "repo": repo,
            "number": number,
        })
    return found


def prose_of(text, prs):
    """The message with the links taken out: the part a person wrote."""
    prose = text
    for pr in prs:
        prose = prose.replace(pr["url"], " ")
    return "\n".join(line.rstrip() for line in prose.splitlines()).strip()


def batch_prompt(prs, prose, entries):
    """The brief for the one agent that watches a batch of pull requests.

    One agent, several reviews: it has to know where each checkout is, and it has to see
    the message the reviewer pasted -- including any instruction in it about which
    repository to keep an eye on.
    """
    lines = [
        f"Review {len(prs)} pull requests on the e-ink tablet, following the eink-pr skill.",
        "One agent runs the batch; each pull request has its own workspace already open in Neovim.",
        "Open ONE tablet note for the whole batch: one brief with a section per PR and one",
        "Interfaces section covering every contract change. Never open one note per PR.",
        "",
    ]
    for pr, entry in zip(prs, entries):
        lines += [
            f"- {pr['owner']}/{pr['repo']}#{pr['number']}: {entry['title'] or 'unknown title'}",
            f"    worktree: {entry['worktree']}",
            f"    workspace: {entry['label']}",
            f"    url: {pr['url']}",
        ]
    lines += [
        "",
        "For each one: read the diff in its workspace, run the lens reviewers in parallel,",
        "filter to the actionable findings, pass them through ihaveadhd, and set the marks.",
        "Then write the aggregated brief and deliver it to eink ONCE, for the batch. Work",
        "through the list in order, and keep going back to the later ones as answers arrive --",
        "a batch is one review session, not N sequential ones.",
        "",
        "If the request is ambiguous -- which repository matters for the interface change, what",
        "depth the reviewer wants, which PR to start with -- ask one short question in chat",
        "before starting. Do not guess and do not pad the answer with a survey.",
    ]
    if prose:
        lines += [
            "",
            "The reviewer's message (quoted, and the only statement of intent):",
            "",
            prose,
        ]
    return "\n".join(lines) + "\n"


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
        "",
        "If the request is ambiguous -- which repository matters for the interface change, what",
        "depth the reviewer wants, what to look at first -- ask one short question in chat",
        "before starting. Do not guess and do not pad the answer with a survey.",
    ]
    if context.strip():
        lines += ["", "Request from the reviewer:", "", context.strip()]
    return "\n".join(lines) + "\n"


# ── checkouts ────────────────────────────────────────────────────────────────

def local_checkouts():
    roots = []
    for pattern in ("*/*", "*/*/*"):
        for candidate in PROGRAMMING.glob(pattern):
            if (candidate / ".git").exists():
                roots.append(candidate)
    return sorted(roots, key=str)


def origin_of(path):
    return run(["git", "-C", str(path), "remote", "get-url", "origin"]).stdout.strip()


def find_repos(owner, repo):
    """Every checkout whose origin names this repository.

    Matching the origin is authoritative; a directory name alone is a guess, and guessing
    the wrong repository would review the wrong code. Name matches are checked first
    because they are the common case, and the full scan is only needed when that misses.
    """
    key = (owner.lower(), repo.lower())
    if key in _REPO_CACHE:
        return _REPO_CACHE[key]

    checkouts = local_checkouts()
    checkouts.sort(key=lambda candidate: (candidate.name != repo, str(candidate)))
    wanted = f"{owner}/{repo}".lower()
    found = []
    for candidate in checkouts:
        origin = origin_of(candidate).lower()
        if wanted in origin or f"/{repo}.git".lower() in origin or origin.endswith(f"/{repo}".lower()):
            found.append(candidate)
    _REPO_CACHE[key] = found
    return found


def named_repos(repo):
    return [candidate for candidate in local_checkouts() if candidate.name == repo]


def close_names(repo):
    names = sorted({candidate.name for candidate in local_checkouts()})
    return difflib.get_close_matches(repo, names, n=3, cutoff=0.5)


def pick_from(paths, owner, repo):
    """Numbered choice, with the origin shown so the wrong pick is visible."""
    if not paths:
        return None
    print()
    print(f"  {bold('Choose a checkout')}  {dim(f'for {owner}/{repo}')}")
    for index, path in enumerate(paths, 1):
        print(f"    {cyan(str(index).rjust(2))}  {short_path(path)}")
        print(f"        {dim(origin_of(path) or 'no origin')}")
    while True:
        try:
            raw = input(f"  {yellow('›')} 1-{len(paths)}, Enter to cancel: ").strip()
        except EOFError:
            return None
        if not raw:
            return None
        if raw.isdigit() and 1 <= int(raw) <= len(paths):
            return paths[int(raw) - 1]
        print(f"    {red('?')} enter a number between 1 and {len(paths)}")


def pick_any_checkout(owner, repo):
    """Pick from every local checkout, optionally filtered by substring."""
    checkouts = local_checkouts()
    try:
        raw = input(f"  {yellow('›')} filter by name (Enter for all): ").strip().lower()
    except EOFError:
        return None
    if raw:
        checkouts = [path for path in checkouts if raw in str(path).lower()]
    if not checkouts:
        print(f"    {yellow('!')} nothing matched")
        return None
    shown = checkouts[:40]
    if len(checkouts) > len(shown):
        print(f"    {dim(f'showing the first {len(shown)} of {len(checkouts)}')}")
    chosen = pick_from(shown, owner, repo)
    if chosen and f"{owner}/{repo}".lower() not in origin_of(chosen).lower():
        print(f"    {yellow('!')} {short_path(chosen)} does not name "
              f"{owner}/{repo} in its origin.")
        if ask(f"  {yellow('›')} Enter) use it anyway   q) cancel: ",
               [("q", "cancel")], default="start") == "quit":
            return None
    return chosen


def clone_checkout(owner, repo):
    target = PROGRAMMING / owner / repo
    target.parent.mkdir(parents=True, exist_ok=True)
    with working(f"cloning {owner}/{repo} into {target}"):
        cloned = run(["gh", "repo", "clone", f"{owner}/{repo}", str(target)])
    if cloned.returncode == 0 and (target / ".git").exists():
        detail(f"cloned into {target}")
        _REPO_CACHE.pop((owner.lower(), repo.lower()), None)
        return target
    print(f"    {red('✗')} clone failed: {(cloned.stderr or cloned.stdout).strip()[:400]}")
    if target.exists() and any(target.iterdir()):
        print(f"    {yellow('!')} {short_path(target)} is not empty; move it aside "
              f"or pick an existing checkout")
    return None


def resolve_checkout(owner, repo, dry=False):
    """Find, clone, pick, or skip the checkout for one pull request.

    Returns a Path, or the string "skip" when the reviewer chose to leave this PR out,
    or None when the whole run was cancelled. A dry run never creates anything, including
    a clone: it names the directory the clone would use.
    """
    with working(f"locating {owner}/{repo}"):
        matches = find_repos(owner, repo)
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        if dry:
            detail(f"several checkouts name {owner}/{repo}; would ask which one")
            return matches[0]
        detail(f"several checkouts name {owner}/{repo}")
        chosen = pick_from(matches, owner, repo)
        return chosen if chosen else None

    # No origin match. A directory with the right name is a strong hint, but its origin
    # is the truth; offer it rather than using it silently.
    named = named_repos(repo)
    print()
    print(f"  {yellow('!')} {bold(f'No checkout of {owner}/{repo}')}")
    print(f"    under {short_path(PROGRAMMING)}")
    if dry:
        target = PROGRAMMING / owner / repo
        print(f"    {dim('dry run would clone it into')} {short_path(target)}")
        return target
    if not sys.stdin.isatty():
        print(f"    clone it with: gh repo clone {owner}/{repo} {short_path(PROGRAMMING / owner / repo)}")
        return None
    if named:
        print(f"    {dim('a directory with that name:')} {short_path(named[0])}")
        print(f"    {dim('origin:')} {origin_of(named[0]) or '(none)'}")
    close = close_names(repo)
    if close:
        print(f"    {dim('closest names:')} {', '.join(close)}")

    target = PROGRAMMING / owner / repo
    while True:
        print()
        print(f"    {cyan('Enter')} clone it to {short_path(target)}")
        print(f"    {cyan('p')}     pick an existing checkout")
        if named:
            print(f"    {cyan('u')}     use {short_path(named[0])}")
        print(f"    {cyan('s')}     skip this PR")
        print(f"    {cyan('q')}     cancel")
        try:
            raw = input(f"  {yellow('›')} ").strip().lower()
        except EOFError:
            return None
        if raw in ("", "c", "clone"):
            cloned = clone_checkout(owner, repo)
            if cloned:
                return cloned
        elif raw in ("p", "pick"):
            chosen = pick_any_checkout(owner, repo)
            if chosen:
                return chosen
        elif raw in ("s", "skip"):
            return "skip"
        elif raw in ("q", "quit", "cancel", "n", "no"):
            return None
        elif named and raw in ("u", "use", "y", "yes"):
            chosen = named[0]
            print(f"    {dim('origin:')} {origin_of(chosen) or '(none)'}")
            if ask(f"  {yellow('›')} Enter) use it   q) cancel: ",
                   [("q", "cancel")], default="start") == "start":
                return chosen
        else:
            print(f"    {red('?')} choose Enter, p, s, or q")


# ── plan and side effects ────────────────────────────────────────────────────

def repo_owner(repo_root):
    """The owner from the checkout's origin, which is more trustworthy than the URL."""
    if not (repo_root / ".git").exists():
        return ""
    origin = origin_of(repo_root)
    match = re.search(r"[:/]([^/:]+)/([^/]+?)(?:\.git)?$", origin)
    return match.group(1) if match else ""


def choose_agent(owner, override=None):
    if override:
        return override
    return "claude" if owner.lower() in {o.lower() for o in CLAUDE_ORGS} else "opencode"


def worktree_path(repo_root, number):
    return repo_root.parent / "worktrees" / f"pr-{number}" / repo_root.name


def pr_title(url, slug):
    if not slug:
        return None, None
    if shutil.which("gh") is None:
        detail("gh is not installed; the title and base will be unknown")
        return None, None
    with working("looking up the pull request title"):
        view = run(["gh", "pr", "view", url, "--json", "title,baseRefName"])
    if view.returncode != 0:
        first = (view.stderr or view.stdout).strip().splitlines()
        detail(first[0] if first else "the title lookup failed")
        return None, None
    try:
        data = json.loads(view.stdout)
        return data.get("title"), data.get("baseRefName")
    except json.JSONDecodeError:
        return None, None


def prepare_worktree(repo_root, number, dry=False):
    """Check the PR head out into a worktree, reusing one that already exists.

    The fetched commit is resolved to a SHA in the *main* checkout and passed by SHA.
    `FETCH_HEAD` inside a linked worktree is a different file, often left over from when
    the worktree was created: checking that out silently reused an older PR (the reader saw
    a brief about code the checkout did not contain). Every step is checked, and a failure
    stops the launch instead of leaving a stale tree looking ready.
    """
    head = f"refs/pull/{number}/head"
    target = worktree_path(repo_root, number)
    if dry:
        return target, "would fetch and check out"

    with working(f"fetching PR #{number} head"):
        fetched = run(["git", "-C", str(repo_root), "fetch", "origin", head])
    if fetched.returncode == 0:
        source = "origin"
        expected = run(
            ["git", "-C", str(repo_root), "rev-parse", "FETCH_HEAD"]
        ).stdout.strip()
    else:
        # Offline or a synthetic PR: fall back to a local ref of the same name so the
        # flow stays testable without touching a server.
        local = run(
            ["git", "-C", str(repo_root), "rev-parse", "--verify", f"{head}^{{commit}}"]
        )
        if local.returncode != 0:
            raise RuntimeError(
                f"cannot fetch PR #{number}: {(fetched.stderr or fetched.stdout).strip()}"
            )
        source = "local ref"
        expected = local.stdout.strip()
    if not expected:
        raise RuntimeError(f"PR #{number}: the fetched head has no commit")

    if (target / ".git").exists():
        with working(f"updating the existing worktree for PR #{number}"):
            checked_out = run(
                ["git", "-C", str(target), "checkout", "--detach", expected]
            )
        if checked_out.returncode != 0:
            raise RuntimeError(
                f"PR #{number}: cannot check out {expected[:12]} in {target}: "
                f"{(checked_out.stderr or checked_out.stdout).strip()}"
            )
        actual = run(["git", "-C", str(target), "rev-parse", "HEAD"]).stdout.strip()
        if actual != expected:
            raise RuntimeError(
                f"PR #{number}: the worktree is at {actual[:12]}, expected {expected[:12]}"
            )
        return target, f"reused existing worktree ({source})"

    target.parent.mkdir(parents=True, exist_ok=True)
    with working(f"creating the worktree for PR #{number}"):
        created = run(
            ["git", "-C", str(repo_root), "worktree", "add", "--detach", str(target), expected]
        )
    if created.returncode != 0:
        raise RuntimeError(
            f"PR #{number}: cannot create the worktree: "
            f"{(created.stderr or created.stdout).strip()}"
        )
    actual = run(["git", "-C", str(target), "rev-parse", "HEAD"]).stdout.strip()
    if actual != expected:
        raise RuntimeError(
            f"PR #{number}: the worktree is at {actual[:12]}, expected {expected[:12]}"
        )
    return target, f"created worktree ({source})"


def herdr(*args):
    result = run(["herdr", *args])
    if result.returncode != 0:
        raise RuntimeError(f"herdr {' '.join(args)} failed: {result.stderr.strip()}")
    return json.loads(result.stdout or "{}")


def socket_path(number, repo):
    """One socket per pull request, not per repository.

    Two PRs of the same repository are reviewed side by side; `jump-<repo>.sock` made the
    second editor unreachable (and would let marks land in the first one's buffer).
    """
    return f"/run/user/{os.getuid()}/jump-pr-{number}-{repo}.sock"


def diff_range(worktree, base):
    """`merge-base(base, HEAD)..HEAD`, so unrelated upstream commits stay out."""
    for ref in [f"origin/{base}" if base else None, "origin/HEAD", "HEAD^"]:
        if not ref:
            continue
        merged = run(["git", "-C", str(worktree), "merge-base", ref, "HEAD"]).stdout.strip()
        if merged:
            return f"{merged}..HEAD"
    return "HEAD"


def nvim_command(socket, range_):
    # One shell string: herdr sends a command to the pane's shell, and the single quotes
    # keep `DiffviewOpen <a>..<b>` one argument.
    return f"nvim --listen {socket} -c 'DiffviewOpen {range_}'"


def registry_entry(number, slug, worktree, session="", socket="", pane="", title="", sha=""):
    try:
        payload = json.loads(REGISTRY.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        payload = {"reviews": []}
    key = str(number)
    rows = [row for row in payload.get("reviews", []) if row.get("key") != key]
    rows.append({
        "key": key,
        "pr": key,
        "sha": sha,
        "worktree": str(worktree),
        "socket": socket or socket_path(number, worktree.name),
        "tab_label": f"PR {number}",
        "title": title,
        "session": session,
        "tab_id": "",
        "pane_id": pane,
    })
    REGISTRY.parent.mkdir(parents=True, exist_ok=True)
    REGISTRY.write_text(json.dumps({"reviews": rows}, indent=2) + "\n")


def existing_workspace(label):
    workspaces = herdr("workspace", "list").get("result", {}).get("workspaces", [])
    for workspace in workspaces:
        if workspace.get("label") == label:
            return workspace
    # A workspace from an earlier run is the same review even when its label predates the
    # repository prefix (`PR 501: …`). Reuse it — and bring the label up to date — rather
    # than leaving two workspaces for one pull request.
    number = label_pr(label)
    if number is None:
        return None
    for workspace in workspaces:
        if not reading_label(workspace.get("label", "")):
            continue
        if label_pr(workspace["label"]) != number:
            continue
        try:
            herdr("workspace", "rename", workspace["workspace_id"], label)
        except (RuntimeError, json.JSONDecodeError) as error:
            print(f"    {yellow('!')} could not rename {workspace['label']}: {error}")
        workspace["label"] = label
        return workspace
    return None


def ensure_claude_trust(path, config=None):
    """Mark a review worktree as trusted for Claude Code.

    A new worktree is an unknown path, so Claude stops at the folder-trust dialog before
    it reads the seed; `--dangerously-skip-permissions` does not skip that dialog. The
    launcher created this worktree for this review, so it is exactly the folder the agent
    is meant to work in. The write is atomic and preserves every other project.
    """
    target = config or CLAUDE_CONFIG
    try:
        data = json.loads(target.read_text()) if target.exists() else {}
    except (OSError, json.JSONDecodeError) as error:
        print(f"    {yellow('!')} cannot read {target}: {error}; "
              f"the agent may stop at the folder-trust prompt")
        return False
    projects = data.setdefault("projects", {})
    entry = projects.setdefault(str(path), {})
    if entry.get("hasTrustDialogAccepted"):
        return True
    entry["hasTrustDialogAccepted"] = True
    temporary = target.with_name(target.name + ".eink-tmp")
    try:
        temporary.write_text(json.dumps(data, indent=2) + "\n")
        temporary.chmod(0o600)
        temporary.replace(target)
    except OSError as error:
        print(f"    {yellow('!')} cannot update {target}: {error}")
        return False
    return True


def load_registry():
    try:
        return json.loads(REGISTRY.read_text()).get("reviews", [])
    except (FileNotFoundError, json.JSONDecodeError):
        return []


def save_registry(rows):
    REGISTRY.parent.mkdir(parents=True, exist_ok=True)
    REGISTRY.write_text(json.dumps({"reviews": rows}, indent=2) + "\n")


def prune_registry(numbers):
    """Forget registry rows for workspaces/PRs that no longer exist."""
    wanted = {str(number) for number in numbers}
    rows = load_registry()
    kept = [row for row in rows if str(row.get("pr")) not in wanted]
    if len(kept) != len(rows):
        save_registry(kept)


# The reviewer's short name for a repository, so the workspace list reads
# `sts 💻 PR 501` instead of `security-token-service 💻 PR 501`. An unlisted repository is
# shortened by rule: the `cx-api-`/`cx-` prefix and the `-service`/`-workspace` suffix go.
REPO_ALIASES = {"security-token-service": "sts"}
READING_EMOJI = "💻"


def repo_label(name):
    name = (name or "").strip()
    for prefix in ("cx-api-", "cx-"):
        if name.startswith(prefix) and len(name) > len(prefix):
            name = name[len(prefix):]
    name = REPO_ALIASES.get(name, name)
    for suffix in ("-workspace", "-service"):
        if name.endswith(suffix) and len(name) > len(suffix):
            name = name[: -len(suffix)]
    return name or "pr"


def reading_label_text(repo, number, title):
    """`💻 sts PR 501: <title>` — the emoji first, so the labels line up in the sidebar.

    The emoji is what tells a workspace holding an editor from the one holding the agent,
    and putting it first keeps the repository column aligned however long a repository's
    name is. An unknown title is left off instead of becoming a trailing colon.
    """
    label = f"{READING_EMOJI} {repo or 'pr'} PR {number}"
    return f"{label}: {title}" if title else label


# Older launchers wrote `PR <n>[: title]`, then `repo 💻 PR <n>`; both are still reading
# workspaces, so an editor opened by an older run is renamed, not duplicated.
READING_LABEL = re.compile(r"^(?:💻 \S+ |\S+ 💻 )?PR (\d+)")


def reading_label(label):
    """The launcher's reading workspaces are `<repo> 💻 PR <n>[: title]`; agents are `Review…`."""
    return bool(READING_LABEL.match(label or ""))


def label_pr(label):
    match = READING_LABEL.match(label or "")
    return int(match.group(1)) if match else None


def socket_alive(path):
    """A socket file can outlive the editor; a successful connect cannot."""
    if not path:
        return False
    try:
        with socket_lib.socket(socket_lib.AF_UNIX, socket_lib.SOCK_STREAM) as probe:
            probe.settimeout(0.2)
            probe.connect(path)
        return True
    except OSError:
        return False


def select_stale(workspaces, current_sockets, registry_rows, socket_exists, current=None):
    """Reading workspaces with no live editor socket.

    A live socket means someone is working there, even if it is from an earlier review.
    A missing one means the editor is gone (or was started before `--listen` existed), and
    the workspace is only taking up room in the workspace list.

    `current` is the set of labels this launch is about to (re)open; `tidy` passes an
    empty set, because a workspace it looks at is not part of any batch being launched.
    """
    current = set(current_sockets) if current is None else set(current)
    stale = []
    for workspace in workspaces:
        label = workspace.get("label", "")
        if not reading_label(label):
            continue
        number = label_pr(label)
        row = next(
            (row for row in registry_rows if str(row.get("pr")) == str(number)),
            None,
        )
        # A current workspace may still be running an editor from the old launcher, on
        # the old socket name. Either listener means someone is working there; never
        # close a live editor because its socket does not match this run's expectation.
        candidates = [current_sockets.get(label), (row or {}).get("socket", "")]
        if any(socket and socket_exists(socket) for socket in candidates):
            continue
        socket = current_sockets.get(label) or (row or {}).get("socket", "")
        stale.append({
            "label": label,
            "workspace_id": workspace.get("workspace_id"),
            "socket": socket,
            "current": label in current,
        })
    return stale


def worktree_for_label(label):
    number = label_pr(label)
    for row in load_registry():
        if str(row.get("pr")) == str(number):
            return row.get("worktree")
    return None


def remove_worktree(path):
    """Remove a linked worktree only when it has nothing to lose."""
    dirty = run(["git", "-C", path, "status", "--porcelain"]).stdout.strip()
    if dirty:
        return False, "uncommitted changes"
    common = run(
        ["git", "-C", path, "rev-parse", "--path-format=absolute", "--git-common-dir"]
    ).stdout.strip()
    if not common:
        return False, "not a worktree"
    main = str(Path(common).parent)
    removed = run(["git", "-C", main, "worktree", "remove", path])
    if removed.returncode != 0:
        return False, (removed.stderr or removed.stdout).strip().splitlines()[0]
    return True, "removed"


def offer_cleanup(stale, assume=None):
    """One question before anything is created: close the room left by old reviews.

    `assume` is `close` or `remove` when the caller already said what to do (the `--tidy`
    command with `--yes`); otherwise the question is asked, and a non-terminal keeps them.
    """
    if not stale:
        return True
    noun = "workspace" if len(stale) == 1 else "workspaces"
    section("Cleanup", f"{len(stale)} review {noun} with no live editor")
    for item in stale:
        note = "this batch — reopens on the diff" if item["current"] else "earlier review"
        print(f"    {item['label']}  {dim(note)}")
    print()
    if assume in ("close", "remove"):
        mode = assume
    elif not sys.stdin.isatty():
        print(f"    {dim('keeping them (no terminal to ask)')}")
        return True
    else:
        print(f"    {cyan('Enter')} close them (files are kept)")
        print(f"    {cyan('w')}     close them and remove the earlier worktrees")
        print(f"    {cyan('k')}     keep them")
        print(f"    {cyan('q')}     cancel")
        mode = None
        while mode is None:
            try:
                raw = input(f"  {yellow('›')} ").strip().lower()
            except EOFError:
                return True
            if raw in ("", "c", "close"):
                mode = "close"
            elif raw in ("w", "worktree", "remove"):
                mode = "remove"
            elif raw in ("k", "keep"):
                return True
            elif raw in ("q", "quit", "cancel"):
                return False
            else:
                print(f"    {red('?')} Enter, w, k, or q")

    with working(f"closing {len(stale)} old {noun}"):
        for item in stale:
            try:
                herdr("workspace", "close", item["workspace_id"])
            except (RuntimeError, json.JSONDecodeError, KeyError) as error:
                print(f"    {yellow('!')} {item['label']}: {error}")

    earlier = [item for item in stale if not item["current"]]
    # Resolve the worktree paths before pruning: the registry is what names most of them,
    # and pruning first made "remove the earlier worktrees" silently remove nothing.
    worktrees = [
        (item, item.get("worktree") or worktree_for_label(item["label"]))
        for item in earlier
    ]
    prune_registry(label_pr(item["label"]) for item in earlier)

    if mode == "remove":
        removed, kept = 0, []
        with working("removing earlier worktrees"):
            for item, path in worktrees:
                if not path:
                    continue
                if not Path(path).exists():
                    continue
                ok, reason = remove_worktree(path)
                if ok:
                    removed += 1
                else:
                    kept.append(f"{item['label']} ({reason})")
        if removed:
            print(f"    {green('✓')} removed {removed} worktree(s)")
        for note in kept:
            print(f"    {yellow('!')} kept {note}")
    return True


def pr_table(entries, width=None):
    """One aligned row per review; long titles and repositories are elided."""
    width = width or columns()
    number_w = max(1, len(str(len(entries))))
    pr_w = max(2, max(len(str(entry["pr"]["number"])) for entry in entries))
    repo_w = min(
        max(len(f"{entry['pr']['owner']}/{entry['pr']['repo']}") for entry in entries),
        max(24, width // 2),
    )
    title_w = max(12, width - number_w - pr_w - repo_w - 10)
    lines = [
        f"  {dim('#'.rjust(number_w))}  {dim('PR'.rjust(pr_w))}  "
        f"{dim('REPOSITORY'.ljust(repo_w))}  {dim('TITLE')}"
    ]
    for index, entry in enumerate(entries, 1):
        repository = shorten(f"{entry['pr']['owner']}/{entry['pr']['repo']}", repo_w)
        title = shorten(entry["title"] or "unknown title", title_w)
        lines.append(
            f"  {cyan(str(index).rjust(number_w))}  "
            f"{str(entry['pr']['number']).rjust(pr_w)}  "
            f"{repository.ljust(repo_w)}  {title}"
        )
    return lines


def print_plan(entries, agent_kind, model):
    section("Plan", f"{len(entries)} review(s)  ·  one tablet note")
    for line in pr_table(entries):
        print(line)
    print()
    print(f"    {dim('worktrees')}")
    for entry in entries:
        note = "reuse" if entry["exists"] else "new"
        print(f"      {str(entry['pr']['number']).rjust(4)}  "
              f"{short_path(entry['worktree'])}  {dim(note)}")
    print()
    kv("agent", agent_kind + (f"  ·  {model}" if model else ""))
    kv("tablet", "one brief" + (f" for all {len(entries)}" if len(entries) > 1 else ""))
    seed = entries[0].get("seed_path") if entries else None
    kv("seed", short_path(seed) if seed else "(written after you confirm)")


def describe_plan(entries, agent_kind, model):
    lines = []
    for entry in entries:
        lines.append(f"{entry['label']}")
        lines.append(f"   repo    : {entry['repo_root']}")
        lines.append(
            f"   worktree: {entry['worktree']}  "
            f"({'reuse' if entry['exists'] else 'new'})"
        )
        lines.append(f"   base    : {entry['base'] or 'unknown'}")
    lines.append(f"agent   : {agent_kind}" + (f"  ({model})" if model else ""))
    lines.append(f"seed    : {entries[0]['seed_path'] if entries else '(none)'}")
    return lines


def confirm_plan(entries, agent_kind, model, args):
    """Show the plan, then ask. Nothing has been created at this point."""
    print_plan(entries, agent_kind, model)
    print()
    if args.dry_run:
        return "dry"
    if args.yes:
        print(f"  {dim('starting (--yes)')}")
        return "start"
    if not sys.stdin.isatty():
        # A piped paste has no way to answer, and silently creating workspaces from a
        # script is how a test run becomes a review nobody asked for.
        print(
            "stdin is not a terminal; pass --yes to create without confirmation, "
            "or --dry-run to see the plan",
            file=sys.stderr,
        )
        return "quit"
    print(f"  {dim('Enter')} start   {dim('d')} dry run   {dim('q')} cancel")
    while True:
        try:
            raw = input(f"  {yellow('›')} ")
        except EOFError:
            return "quit"
        choice = interpret_choice(raw)
        if choice:
            return choice
        print(f"  {red('?')} Enter, d, or q")


def build_plan(prs, args):
    """Resolve every checkout and title before touching anything."""
    entries = []
    for index, pr in enumerate(prs, 1):
        print(f"\n  {dim(f'{index}/{len(prs)}')}  "
              f"{bold(f'{pr['owner']}/{pr['repo']}#{pr['number']}')}")
        repo_root = resolve_checkout(pr["owner"], pr["repo"], dry=args.dry_run)
        if repo_root == "skip":
            print(f"    {yellow('skipped')} at the reviewer's request")
            continue
        if repo_root is None:
            return None
        title, base = pr_title(pr["url"], pr)
        label = reading_label_text(repo_label(pr["repo"]), pr["number"], title)
        worktree = worktree_path(repo_root, pr["number"])
        entries.append({
            "pr": pr,
            "repo_root": repo_root,
            "worktree": worktree,
            "exists": (worktree / ".git").exists(),
            "title": title,
            "base": base,
            "label": label,
            "socket": socket_path(pr["number"], worktree.name),
            "seed_path": None,
        })
        kv("repo", short_path(repo_root))
        kv("title", title or "unknown title", f"base {base or '?'}")
    return entries


# ── launch ───────────────────────────────────────────────────────────────────

def launch(prs, prose, args):
    """Plan, confirm, then create. The editor opens on the diff, not on a shell command."""
    entries = build_plan(prs, args)
    if entries is None:
        return die("cancelled; nothing was created")
    if not entries:
        return die("nothing left to review after skipping")

    owner = repo_owner(entries[0]["repo_root"]) or prs[0]["owner"]
    agent_kind = choose_agent(owner, args.agent)
    model = args.model or (CLAUDE_MODEL if agent_kind == "claude" else DEFAULT_MODEL)

    if len(entries) == 1:
        entry = entries[0]
        seed_path = SEED_DIR / f"pr-{entry['pr']['number']}.md"
        seed = seed_prompt(
            entry["pr"]["url"], entry["pr"], entry["worktree"], prose,
            entry["repo_root"], entry["title"],
        )
        agent_label = f"Review: PR {entry['pr']['number']}"
    else:
        seed_path = SEED_DIR / f"batch-{'-'.join(entry['pr']['number'] for entry in entries)}.md"
        seed = batch_prompt([entry["pr"] for entry in entries], prose, entries)
        agent_label = f"Review batch: {len(entries)} PRs"
    for entry in entries:
        entry["seed_path"] = seed_path

    action = confirm_plan(entries, agent_kind, model, args)
    if action == "quit":
        print(f"\n  {yellow('·')} cancelled; nothing was created")
        return 0
    if action == "dry":
        section("Seed prompt")
        print(indent(seed))
        print(f"\n  {dim('dry run: nothing created')}")
        return 0
    if not os.environ.get("HERDR_ENV"):
        return die(
            "not running inside a herdr pane; the plan is ready but workspaces need herdr"
        )

    current_sockets = {entry["label"]: entry["socket"] for entry in entries}
    stale = select_stale(
        herdr("workspace", "list").get("result", {}).get("workspaces", []),
        current_sockets,
        load_registry(),
        socket_alive,
    )
    if not offer_cleanup(stale):
        print(f"\n  {yellow('·')} cancelled; nothing was created")
        return 0

    # The plan is approved. Fetch, check out, and work out what each editor should show.
    for entry in entries:
        entry["worktree"], note = prepare_worktree(
            entry["repo_root"], entry["pr"]["number"], dry=args.dry_run
        )
        entry["sha"] = run(
            ["git", "-C", str(entry["worktree"]), "rev-parse", "HEAD"]
        ).stdout.strip()
        entry["range"] = diff_range(entry["worktree"], entry["base"])
        kv("worktree", short_path(entry["worktree"]), note)
        kv("diff", entry["range"])

    SEED_DIR.mkdir(parents=True, exist_ok=True)
    seed_path.write_text(seed)
    kv("seed", short_path(seed_path))

    # One reading workspace per pull request. Neovim is started *with* the diff and the
    # socket, so nothing has to be typed into it later.
    for entry in entries:
        workspace = existing_workspace(entry["label"])
        socket = entry["socket"]
        if workspace:
            created = herdr("workspace", "get", workspace["workspace_id"])
            pane = created["result"]["root_pane"]["pane_id"]
            print(f"    {green('✓')} workspace {dim('reused')}  {entry['label']}")
            previous = next(
                (row.get("socket", "") for row in load_registry()
                 if str(row.get("pr")) == str(entry["pr"]["number"])),
                "",
            )
            if not socket_alive(socket) and socket_alive(previous):
                print(f"    {yellow('!')} this editor is on an older socket; "
                      f"restart it to use {socket}")
            elif not socket_alive(socket):
                print(f"    {yellow('!')} no review socket; open :DiffviewOpen yourself, "
                      f"or close and relaunch")
        else:
            with working(f'workspace · {entry["label"]}'):
                created = herdr(
                    "workspace", "create", "--cwd", str(entry["worktree"]),
                    "--label", entry["label"], "--focus",
                    "--env", f"EINK_REVIEW_PR={entry['pr']['url']}",
                    "--env", f"EINK_PR_NUMBER={entry['pr']['number']}",
                    "--env", f"EINK_PR_SOCKET={socket}",
                    "--env", f"EINK_PR_STATE={STATE}",
                )
            pane = created["result"]["root_pane"]["pane_id"]
            if not args.no_launch:
                with working(f'editor · {entry["label"]}'):
                    herdr("pane", "run", pane, nvim_command(socket, entry["range"]))
        registry_entry(
            entry["pr"]["number"], entry["pr"], entry["worktree"],
            socket=socket, pane=pane, title=entry["title"], sha=entry["sha"],
        )

    # One agent, in a workspace of its own.
    if agent_kind == "claude" and not args.no_launch:
        ensure_claude_trust(entries[0]["worktree"])

    workspace = existing_workspace(agent_label)
    if workspace:
        created = herdr("workspace", "get", workspace["workspace_id"])
        print(f"    {green('✓')} agent workspace {dim('reused')}  {agent_label}")
    else:
        with working(f"agent workspace · {agent_label}"):
            created = herdr(
                "workspace", "create", "--cwd", str(entries[0]["worktree"]),
                "--label", agent_label, "--focus",
                "--env", f"EINK_REVIEW_SEED={seed_path}",
                "--env", f"EINK_REVIEW_AGENT={agent_kind}",
                "--env", f"EINK_REVIEW_MODEL={model}",
            )

    return start_agent(
        created["result"]["root_pane"]["pane_id"], args,
        label=agent_label, batch=len(entries) > 1,
    )


def start_agent(pane, args, label, batch=False):
    if args.no_launch:
        print(f"\n  {yellow('·')} prepared only; start the agent with:")
        print(f"    herdr pane run {pane} eink-review-agent")
        return 0

    with working(f"agent · {label}"):
        herdr("pane", "run", pane, "eink-review-agent")

    # Report what actually happened: a missing binary or a crashed agent must not be
    # announced as a started review.
    with working("waiting for the agent to come up"):
        status = wait_for_agent(pane, timeout=15)
    if status == "agent":
        print()
        print(f"  {green('✓')} {bold('Ready')}   {label}")
        if batch:
            print(f"    {dim('The agent writes one aggregated brief for the tablet.')}")
        else:
            print(f"    {dim('The agent writes the brief for the tablet.')}")
        return 0

    output = run(["herdr", "pane", "read", pane, "--source", "visible", "--lines", "6"]).stdout
    print(f"\n  {red('✗')} the agent did not start ({status})", file=sys.stderr)
    print(f"    {dim('pane output:')}", file=sys.stderr)
    print("    " + output.strip().replace("\n", "\n    "), file=sys.stderr)
    print(
        f"\n    The workspace and worktree are ready; retry with:\n"
        f"      herdr pane run {pane} eink-review-agent",
        file=sys.stderr,
    )
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
        if "Is this a project you created" in output or "trust this folder" in output:
            return "waiting for folder trust"
        if "command not found" in output or "not found" in output:
            return "command not found"
        time.sleep(0.5)
    return "timed out"


def workspace_cwd(workspace_id, panes):
    """The directory a workspace's first pane sits in, which is the review's worktree."""
    for pane in panes:
        if pane.get("workspace_id") == workspace_id and pane.get("cwd"):
            return pane["cwd"]
    return ""


def workspace_socket(workspace, panes):
    """The socket an editor in this workspace listens on, by the launcher's own rule."""
    number = label_pr(workspace.get("label", ""))
    cwd = workspace_cwd(workspace["workspace_id"], panes)
    if not number or not cwd:
        return ""
    return socket_path(number, Path(cwd).name)


def tidy(yes=False, dry=False):
    """Bring the open review workspaces up to date, then clear out the unused ones.

    A workspace is *used* while its editor still answers on its socket; the rest are
    cleanup candidates. Renaming happens before closing so a live review keeps its tabs
    and its ink -- only the label changes. `--dry-run` prints what would happen.
    """
    workspaces = herdr("workspace", "list").get("result", {}).get("workspaces", [])
    panes = herdr("pane", "list").get("result", {}).get("panes", [])
    reading = [w for w in workspaces if reading_label(w.get("label", ""))]
    if not reading:
        print(f"    {dim('no review workspaces')}")
        return 0

    section("Workspaces", f"{len(reading)} review workspace(s)")
    renames = []
    for workspace in reading:
        label = workspace["label"]
        cwd = workspace_cwd(workspace["workspace_id"], panes)
        title = label.split(": ", 1)[1] if ": " in label else ""
        want = reading_label_text(
            repo_label(Path(cwd).name), label_pr(label), title
        )
        if want == label:
            print(f"    {green('✓')} {label}")
            continue
        renames.append((workspace["workspace_id"], label, want))
        print(f"    {cyan('→')} {label}  →  {want}")

    sockets = {
        workspace["label"]: socket
        for workspace in reading
        if (socket := workspace_socket(workspace, panes))
    }
    stale = select_stale(workspaces, sockets, load_registry(), socket_alive, current=set())
    by_id = {workspace_id: want for workspace_id, _, want in renames}
    for item in stale:
        item["label"] = by_id.get(item["workspace_id"], item["label"])
        item["worktree"] = workspace_cwd(item["workspace_id"], panes)

    if dry:
        for item in stale:
            print(f"    {yellow('·')} unused: {item['label']}")
        print(f"\n    {dim('dry run: nothing renamed or closed')}")
        return 0

    for workspace_id, label, want in renames:
        try:
            herdr("workspace", "rename", workspace_id, want)
        except (RuntimeError, json.JSONDecodeError) as error:
            print(f"    {yellow('!')} {label}: {error}")

    if not offer_cleanup(stale, assume="remove" if yes else None):
        return 1
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Launch one e-ink review, or one aggregated review for a pasted batch.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "examples:\n"
            "  eink-pr-launch                 paste the request, then Ctrl-D\n"
            "  eink-pr-launch --dry-run       print the plan and the seed, create nothing\n"
            "  eink-pr-launch --link URL      skip stdin (add --context for the message)\n"
            "  eink-pr-launch --tidy --yes    rename open review workspaces, close the unused\n"
        ),
    )
    parser.add_argument("--dry-run", action="store_true", help="print the plan and seed; create nothing")
    parser.add_argument("--link", help="skip reading stdin and use this link")
    parser.add_argument("--context", default="", help="review request text")
    parser.add_argument("--model", help="override the model for the chosen agent")
    parser.add_argument("--agent", choices=["claude", "opencode"], help="force the agent kind")
    parser.add_argument("--no-launch", action="store_true", help="prepare the workspace, do not start the agent")
    parser.add_argument("--yes", "-y", action="store_true", help="skip the final confirmation")
    parser.add_argument("--tidy", action="store_true",
                        help="rename open review workspaces and close the ones with no live editor")
    args = parser.parse_args(argv)

    if args.tidy:
        return tidy(yes=args.yes, dry=args.dry_run)

    if sys.stdin.isatty():
        banner()

    # `--link` means the request is the link: reading stdin as well would make a script
    # (or a test with a pty) wait for a Ctrl-D that is never coming.
    text = args.context or args.link or read_request()
    pasted = args.link or text
    prs = pull_requests(pasted)
    if not prs:
        if not pasted.strip():
            return die("nothing was pasted")
        if not ANY_URL.search(pasted):
            return die("no link found in the request; paste the message with its URL")
        return die(f"{ANY_URL.search(pasted).group(0)} is not a GitHub pull request link")

    return launch(prs, prose_of(text, prs), args)


def finish(code):
    """Hold a failure on screen long enough to read it in a popup."""
    if code != 0 and sys.stdin.isatty() and not os.environ.get("EINK_PR_NO_PAUSE"):
        try:
            input(f"\n  {dim('Press Enter to close …')}")
        except (EOFError, KeyboardInterrupt):
            pass
    return code


if __name__ == "__main__":
    try:
        sys.exit(finish(main()))
    except KeyboardInterrupt:
        print("\ncancelled", file=sys.stderr)
        sys.exit(finish(130))
    except (RuntimeError, OSError) as error:
        sys.exit(finish(die(str(error))))
