"""Launch an e-ink PR review from a herdr popup.

You paste a review request — the message plus a link — and this sets up everything
the review needs, then hands off:

    herdr workspace create --cwd <worktree> --label "PR <n>: <title>"
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

# The output is read in a popup and often piped; line buffering keeps "what happened"
# in the order it happened instead of flushing stdout after stderr at exit.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(line_buffering=True)


# ── output ───────────────────────────────────────────────────────────────────

def run(cmd, **kwargs):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    except FileNotFoundError:
        # `gh` is optional: a review without a title is still a review.
        return subprocess.CompletedProcess(cmd, 127, "", f"{cmd[0]} is not installed")


def step(message):
    print(f"-> {message}", flush=True)


def detail(message):
    print(f"   {message}", flush=True)


@contextmanager
def working(label):
    """Print a step, tick while it runs, and report how long it took."""
    started = time.time()
    if not sys.stdout.isatty():
        print(f"   {label} ...", flush=True)
        try:
            yield
        finally:
            print(f"   {label} ({time.time() - started:.1f}s)", flush=True)
        return

    print(f"   {label} ...", end="", flush=True)
    done = threading.Event()

    def tick():
        while not done.wait(0.5):
            sys.stdout.write(f"\r   {label} ... {time.time() - started:.0f}s")
            sys.stdout.flush()

    ticker = threading.Thread(target=tick, daemon=True)
    ticker.start()
    try:
        yield
    finally:
        done.set()
        ticker.join(timeout=0.2)
        sys.stdout.write(f"\r   {label} ({time.time() - started:.1f}s)\n")
        sys.stdout.flush()


def die(message, code=1):
    print(f"error: {message}", file=sys.stderr)
    return code


# ── input ────────────────────────────────────────────────────────────────────

def read_request():
    """Take the pasted request from stdin. A tty gets an explanation first."""
    if sys.stdin.isatty():
        print("Paste the review request (the message and its GitHub pull-request link).")
        print("Finish with Ctrl-D on an empty line.\n")
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
    while True:
        raw = input(prompt).strip().lower()
        if not raw and default:
            return default
        for key, _ in choices:
            if raw == key:
                return key
        print("   choose " + ", ".join(f"[{key}] {label}" for key, label in choices))


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
    print(f"   checkouts found for {owner}/{repo}:")
    for index, path in enumerate(paths, 1):
        print(f"     {index}. {path}  ({origin_of(path) or 'no origin'})")
    while True:
        raw = input(f"   pick 1-{len(paths)}, or Enter to cancel: ").strip()
        if not raw:
            return None
        if raw.isdigit() and 1 <= int(raw) <= len(paths):
            return paths[int(raw) - 1]
        print(f"   enter a number between 1 and {len(paths)}")


def pick_any_checkout(owner, repo):
    """Pick from every local checkout, optionally filtered by substring."""
    checkouts = local_checkouts()
    raw = input("   filter by name (Enter for all): ").strip().lower()
    if raw:
        checkouts = [path for path in checkouts if raw in str(path).lower()]
    if not checkouts:
        print("   nothing matched")
        return None
    shown = checkouts[:40]
    if len(checkouts) > len(shown):
        print(f"   showing the first {len(shown)} of {len(checkouts)}")
    chosen = pick_from(shown, owner, repo)
    if chosen and f"{owner}/{repo}".lower() not in origin_of(chosen).lower():
        print(f"   {chosen} does not name {owner}/{repo} in its origin.")
        if ask("   [Enter] use it anyway  [q] cancel > ", [("q", "cancel")], default="start") == "quit":
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
    print(f"   clone failed: {(cloned.stderr or cloned.stdout).strip()[:400]}")
    if target.exists() and any(target.iterdir()):
        print(f"   {target} is not empty; move it aside or pick an existing checkout")
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
    print(f"No checkout of {owner}/{repo} under {PROGRAMMING}.")
    if dry:
        target = PROGRAMMING / owner / repo
        detail(f"dry run: would clone it into {target}")
        return target
    if not sys.stdin.isatty():
        print(f"   clone it with: gh repo clone {owner}/{repo} {PROGRAMMING / owner / repo}")
        return None
    if named:
        print(f"   a directory named {repo!r} exists: {named[0]}")
        print(f"   its origin: {origin_of(named[0]) or '(none)'}")
    close = close_names(repo)
    if close:
        print(f"   closest local names: {', '.join(close)}")
    hint = "   [u] use that directory" if named else ""
    print(f"   [Enter] clone it   [p] pick an existing checkout{hint}   [s] skip this PR   [q] cancel")

    while True:
        try:
            raw = input("   > ").strip().lower()
        except EOFError:
            return None
        if raw == "":
            cloned = clone_checkout(owner, repo)
            if cloned:
                return cloned
            print("   [Enter] retry   [p] pick an existing checkout   [s] skip   [q] cancel")
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
            print(f"   {chosen} has origin {origin_of(chosen) or '(none)'}.")
            if ask("   [Enter] use it  [q] cancel > ", [("q", "cancel")], default="start") == "start":
                return chosen


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
    """Check the PR head out into a worktree, reusing one that already exists."""
    head = f"refs/pull/{number}/head"
    target = worktree_path(repo_root, number)
    if dry:
        return target, "would fetch and check out"
    source = "origin"
    with working(f"fetching PR #{number} head"):
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
        with working(f"updating the existing worktree for PR #{number}"):
            run(["git", "-C", str(target), "checkout", "--detach", ref])
        return target, f"reused existing worktree ({source})"
    target.parent.mkdir(parents=True, exist_ok=True)
    with working(f"creating the worktree for PR #{number}"):
        created = run(["git", "-C", str(repo_root), "worktree", "add", "--detach", str(target), ref])
    if created.returncode != 0:
        return target, f"worktree add failed: {created.stderr.strip()}"
    return target, f"created worktree ({source})"


def herdr(*args, announce=False):
    """Call herdr. `announce` is for the calls that create something and can be slow."""
    if announce:
        with working(f"herdr {' '.join(args[:2])}"):
            result = run(["herdr", *args])
    else:
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
    for workspace in herdr("workspace", "list").get("result", {}).get("workspaces", []):
        if workspace.get("label") == label:
            return workspace
    return None


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
    print()
    for line in describe_plan(entries, agent_kind, model):
        print(line)
    print()
    if args.dry_run:
        return "dry"
    if args.yes:
        print("starting (--yes)")
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
    print("   [Enter] start   [d] dry run (print the plan and seed)   [q] cancel")
    while True:
        choice = interpret_choice(input("   > "))
        if choice:
            return choice
        print("   press Enter, d, or q")


def build_plan(prs, args):
    """Resolve every checkout and title before touching anything."""
    entries = []
    for index, pr in enumerate(prs, 1):
        step(f"[{index}/{len(prs)}] {pr['owner']}/{pr['repo']}#{pr['number']}")
        repo_root = resolve_checkout(pr["owner"], pr["repo"], dry=args.dry_run)
        if repo_root == "skip":
            detail("skipped at the reviewer's request")
            continue
        if repo_root is None:
            return None
        title, base = pr_title(pr["url"], pr)
        label = f"PR {pr['number']}: {title}" if title else f"PR {pr['number']}"
        worktree = worktree_path(repo_root, pr["number"])
        entries.append({
            "pr": pr,
            "repo_root": repo_root,
            "worktree": worktree,
            "exists": (worktree / ".git").exists(),
            "title": title,
            "base": base,
            "label": label,
            "seed_path": None,
        })
        detail(f"repo    : {repo_root}")
        detail(f"worktree: {worktree} ({'reuse' if entries[-1]['exists'] else 'new'})")
        detail(f"pr      : {title or 'unknown title'} (base {base or '?'})")
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
        print("cancelled; nothing was created")
        return 0
    if action == "dry":
        print("\n-- seed prompt --")
        print(seed)
        print("dry run: nothing created")
        return 0
    if not os.environ.get("HERDR_ENV"):
        return die(
            "not running inside a herdr pane; the plan is ready but workspaces need herdr"
        )

    # The plan is approved. Fetch, check out, and work out what each editor should show.
    for entry in entries:
        entry["worktree"], note = prepare_worktree(
            entry["repo_root"], entry["pr"]["number"], dry=args.dry_run
        )
        entry["sha"] = run(
            ["git", "-C", str(entry["worktree"]), "rev-parse", "HEAD"]
        ).stdout.strip()
        entry["socket"] = socket_path(entry["pr"]["number"], entry["worktree"].name)
        entry["range"] = diff_range(entry["worktree"], entry["base"])
        detail(f"{entry['label']}: {note}; diff {entry['range']}")

    SEED_DIR.mkdir(parents=True, exist_ok=True)
    seed_path.write_text(seed)
    detail(f"seed: {seed_path}")

    # One reading workspace per pull request. Neovim is started *with* the diff and the
    # socket, so nothing has to be typed into it later.
    for entry in entries:
        workspace = existing_workspace(entry["label"])
        socket = entry["socket"]
        # A workspace from an older launcher has an editor without --listen and a buffer
        # full of the command that was typed into it. Offer to start clean.
        needs_recreate = workspace and not Path(socket).exists() and not args.no_launch and sys.stdin.isatty()
        if needs_recreate:
            print()
            print(f"{entry['label']} exists, but its editor has no review socket.")
            print("   [Enter] close it and open the diff   [k] keep it   [q] cancel")
            raw = input("   > ").strip().lower()
            if raw in ("q", "quit", "cancel"):
                return 0
            if raw not in ("k", "keep"):
                herdr("workspace", "close", workspace["workspace_id"])
                workspace = None
        if workspace:
            created = herdr("workspace", "get", workspace["workspace_id"])
            pane = created["result"]["root_pane"]["pane_id"]
            detail(f"workspace: reusing {workspace['workspace_id']} for {entry['label']}")
            if not Path(socket).exists():
                detail(
                    "no review socket in this workspace; open the diff manually with "
                    ":DiffviewOpen, or close the workspace and relaunch"
                )
        else:
            created = herdr(
                "workspace", "create", "--cwd", str(entry["worktree"]),
                "--label", entry["label"], "--focus",
                "--env", f"EINK_REVIEW_PR={entry['pr']['url']}",
                "--env", f"EINK_PR_NUMBER={entry['pr']['number']}",
                "--env", f"EINK_PR_SOCKET={socket}",
                "--env", f"EINK_PR_STATE={STATE}",
                announce=True,
            )
            pane = created["result"]["root_pane"]["pane_id"]
            detail(f"workspace: {created['result']['workspace']['workspace_id']} for {entry['label']}")
            if not args.no_launch:
                step(f"opening the diff in {entry['label']}")
                herdr("pane", "run", pane, nvim_command(socket, entry["range"]))
        registry_entry(
            entry["pr"]["number"], entry["pr"], entry["worktree"],
            socket=socket, pane=pane, title=entry["title"], sha=entry["sha"],
        )

    # One agent, in a workspace of its own.
    workspace = existing_workspace(agent_label)
    if workspace:
        created = herdr("workspace", "get", workspace["workspace_id"])
        detail(f"agent workspace: reusing {workspace['workspace_id']}")
    else:
        created = herdr(
            "workspace", "create", "--cwd", str(entries[0]["worktree"]),
            "--label", agent_label, "--focus",
            "--env", f"EINK_REVIEW_SEED={seed_path}",
            "--env", f"EINK_REVIEW_AGENT={agent_kind}",
            "--env", f"EINK_REVIEW_MODEL={model}",
            announce=True,
        )
        detail(f"agent workspace: {created['result']['workspace']['workspace_id']}")

    return start_agent(created["result"]["root_pane"]["pane_id"], args, label=agent_label)


def start_agent(pane, args, label):
    if args.no_launch:
        print("prepared only (--no-launch); start the agent manually with:")
        print(f"  herdr pane run {pane} eink-review-agent")
        return 0

    step(f"starting the agent for {label}")
    herdr("pane", "run", pane, "eink-review-agent")

    # Report what actually happened: a missing binary or a crashed agent must not be
    # announced as a started review.
    with working("waiting for the agent to come up"):
        status = wait_for_agent(pane, timeout=15)
    if status == "agent":
        print()
        print(f"done: {label} is ready in pane {pane}.")
        print("The agent will open the diff, review, and put the brief on the tablet.")
        return 0

    output = run(["herdr", "pane", "read", pane, "--source", "visible", "--lines", "6"]).stdout
    print(f"agent: NOT started ({status})", file=sys.stderr)
    print("pane output:", file=sys.stderr)
    print("  " + output.strip().replace("\n", "\n  "), file=sys.stderr)
    print(
        f"\nThe workspace and worktree are ready; retry with:\n"
        f"  herdr pane run {pane} eink-review-agent",
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
        if "command not found" in output or "not found" in output:
            return "command not found"
        time.sleep(0.5)
    return "timed out"


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--dry-run", action="store_true", help="print the plan and seed; create nothing")
    parser.add_argument("--link", help="skip reading stdin and use this link")
    parser.add_argument("--context", default="", help="review request text")
    parser.add_argument("--model", help="override the model for the chosen agent")
    parser.add_argument("--agent", choices=["claude", "opencode"], help="force the agent kind")
    parser.add_argument("--no-launch", action="store_true", help="prepare the workspace, do not start the agent")
    parser.add_argument("--yes", "-y", action="store_true", help="skip the final confirmation")
    args = parser.parse_args(argv)

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
            input("\nPress Enter to close ...")
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
