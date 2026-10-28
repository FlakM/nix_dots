#!/usr/bin/env python3
"""Tests for the paste parsing in `eink-pr-launch.py`.

Run: python3 eink-pr-launch_test.py

The batch case is the one worth testing: a paste with several links has to become one
workspace per pull request and a single agent, and the words around the links have to reach
that agent -- they are the only statement of intent the reviewer gives, and they are where
"keep an eye on identity-service" lives (as in the real message below).
"""
import importlib.util
import json
import pathlib
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("eink_pr_launch", HERE / "eink-pr-launch.py")
launch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launch)

REAL_MESSAGE = """as we spoke on sync, im going to merge it, asking for your review for:

https://github.com/coralogix/cx-web-workspace/pull/23938
https://github.com/coralogix/identity-service/pull/453
"""

failures = []


def check(condition, message):
    if condition:
        print(f"  ok   {message}")
    else:
        print(f"  FAIL {message}")
        failures.append(message)


def test_parses_every_pull_request_in_the_order_written():
    prs = launch.pull_requests(REAL_MESSAGE)
    check(len(prs) == 2, "both links are found")
    check(
        [(pr["owner"], pr["repo"], pr["number"]) for pr in prs]
        == [("coralogix", "cx-web-workspace", "23938"), ("coralogix", "identity-service", "453")],
        "they are in the order written, with the right repo and number",
    )
    check(prs[0]["url"].startswith("https://github.com/"), "the whole URL is kept, scheme included")


def test_one_link_is_not_a_batch():
    check(len(launch.pull_requests("see https://github.com/a/b/pull/1 thanks")) == 1,
          "a single link stays the single-review path")


def test_a_repeated_link_is_not_two_reviews():
    text = "https://github.com/a/b/pull/7 and again https://github.com/a/b/pull/7"
    check(len(launch.pull_requests(text)) == 1, "the same pull request twice is still one review")


def test_non_pull_request_links_are_ignored():
    text = "see https://github.com/a/b/issues/3 and https://example.com/x"
    check(launch.pull_requests(text) == [], "issues and other links are not pull requests")


def test_the_prose_survives_without_the_links():
    prose = launch.prose_of(REAL_MESSAGE, launch.pull_requests(REAL_MESSAGE))
    check("as we spoke on sync" in prose, "the reviewer's words are kept")
    check("review for" in prose, "including the sentence that introduces the links")
    check("http" not in prose and "github.com" not in prose,
          f"and the links are gone, with no scheme left behind: {prose!r}")


def test_the_batch_brief_names_every_review_and_quotes_the_message():
    prs = launch.pull_requests(REAL_MESSAGE)
    entries = [
        {"title": "Labels JWT and per-workspace scoping",
         "worktree": "/w/pr-23938/cx-web-workspace", "label": "PR 23938: Labels JWT"},
        {"title": "Rotate signing keys on demand",
         "worktree": "/w/pr-453/identity-service", "label": "PR 453: Rotate signing keys"},
    ]
    brief = launch.batch_prompt(prs, launch.prose_of(REAL_MESSAGE, prs), entries)
    check("Review 2 pull requests" in brief, "the brief says how many")
    check("One agent runs the batch" in brief, "and that one agent runs them")
    check("Open ONE tablet note" in brief, "the batch is one tablet note")
    check("Never open one note per PR" in brief, "not one note per pull request")
    for entry in entries:
        check(entry["worktree"] in brief, f"the brief names {entry['worktree']}")
    check("as we spoke on sync" in brief, "the reviewer's message is quoted verbatim")
    check(brief.index("cx-web-workspace#23938") < brief.index("identity-service#453"),
          "the reviews are listed in the order pasted")


def test_choice_interpretation_is_explicit():
    check(launch.interpret_choice("") == "start", "Enter starts")
    check(launch.interpret_choice("d") == "dry", "d shows the plan")
    check(launch.interpret_choice("q") == "quit", "q cancels")
    check(launch.interpret_choice("maybe") is None, "an unknown answer asks again")


def test_a_new_worktree_is_trusted_for_claude_without_losing_the_others():
    with tempfile.TemporaryDirectory() as directory:
        config = pathlib.Path(directory) / ".claude.json"
        config.write_text('{"projects": {"/old": {"hasTrustDialogAccepted": true}}, "other": 1}')
        check(launch.ensure_claude_trust("/w/pr-1/repo", config=config),
              "the new worktree is accepted")
        data = json.loads(config.read_text())
        check(data["projects"]["/w/pr-1/repo"]["hasTrustDialogAccepted"] is True,
              "the worktree is marked trusted")
        check(data["projects"]["/old"]["hasTrustDialogAccepted"] is True,
              "existing projects are preserved")
        check(data["other"] == 1, "unrelated config is preserved")
        check(launch.ensure_claude_trust("/w/pr-1/repo", config=config),
              "trusting twice is harmless")

    with tempfile.TemporaryDirectory() as directory:
        broken = pathlib.Path(directory) / ".claude.json"
        broken.write_text("not json")
        check(launch.ensure_claude_trust("/w/x", config=broken) is False,
              "a corrupt config is reported, not overwritten")
        check(broken.read_text() == "not json", "and is left untouched")


def test_the_socket_and_editor_command_are_per_pull_request():
    one = launch.socket_path(485, "security-token-service")
    two = launch.socket_path(486, "security-token-service")
    check(one != two, "two PRs of one repository cannot share an editor socket")
    check("jump-pr-485-security-token-service.sock" in one, "the socket names the PR")
    command = launch.nvim_command(one, "abc123..HEAD")
    check(command.startswith(f"nvim --listen {one} "), "the editor listens on that socket")
    check("-c 'DiffviewOpen abc123..HEAD'" in command, "and opens the merge-base range")


def test_the_plan_table_stays_aligned_and_elides_long_names():
    entries = [
        {"pr": {"number": "19", "owner": "coralogix", "repo": "cx-api-security-token-service"},
         "title": "CX-64699 Login access: a client can be closed to a whole team"},
        {"pr": {"number": "485", "owner": "coralogix", "repo": "security-token-service"},
         "title": "CX-64699 oauth client disallow all option"},
    ]
    lines = launch.pr_table(entries, width=80)
    check(len(lines) == 3, "a header and one row per review")
    check("REPOSITORY" in lines[0] and "TITLE" in lines[0], "the columns are labelled")
    check(all(len(line) <= 80 for line in lines), "the table fits the terminal")
    check("…" in lines[1], "a long repository or title is elided, not wrapped")
    check(launch.short_path(str(launch.HOME / "programming/x")).startswith("~"),
          "paths are shortened to ~")


def test_reusing_a_worktree_checks_out_the_fetched_pull_request_head():
    import subprocess

    def git(cwd, *args):
        result = subprocess.run(["git", "-C", str(cwd), *args],
                                capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        return result.stdout.strip()

    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        remote = root / "remote.git"
        main = root / "repo"
        subprocess.run(["git", "init", "--bare", str(remote)], check=True,
                       capture_output=True)
        subprocess.run(["git", "init", str(main)], check=True, capture_output=True)
        git(main, "config", "user.email", "test@example.com")
        git(main, "config", "user.name", "Test")
        (main / "a.txt").write_text("a")
        git(main, "add", ".")
        git(main, "commit", "-m", "A")
        git(main, "remote", "add", "origin", str(remote))
        git(main, "push", "origin", "HEAD:master")
        first = git(main, "rev-parse", "HEAD")

        # An earlier launcher left the worktree at the first commit.
        target = launch.worktree_path(main, 7)
        target.parent.mkdir(parents=True)
        git(main, "worktree", "add", "--detach", str(target), first)

        # The PR head moves on and is pushed where `prepare_worktree` fetches it.
        (main / "a.txt").write_text("b")
        git(main, "commit", "-am", "B")
        second = git(main, "rev-parse", "HEAD")
        git(main, "push", "origin", "HEAD:refs/pull/7/head")

        path, note = launch.prepare_worktree(main, 7)
        head = git(path, "rev-parse", "HEAD")
        check(head == second, "a reused worktree is moved to the fetched PR head")
        check("reused" in note, "and is reported as reused")


def test_a_reading_workspace_names_its_repository_first():
    label = launch.reading_label_text("sts", 501, "social login method")
    check(label == "💻 sts PR 501: social login method",
          f"the label puts the editor first, then the repository, then the PR: {label!r}")
    check(launch.reading_label_text("sts", 501, "") == "💻 sts PR 501",
          "an unknown title does not leave a trailing colon")
    check(launch.reading_label("sts 💻 PR 501: old middle format"),
          "a label from the in-between format is still a reading workspace")
    check(launch.reading_label(label), "the new label is a reading workspace")
    check(launch.label_pr(label) == 501, "and its PR number is readable")
    check(launch.label_pr("sts 💻 PR 501: fix PR 42 handling") == 501,
          "a title naming another PR does not win")
    check(launch.reading_label("PR 501: social login method"),
          "a workspace from before the rename is still a reading workspace")
    check(launch.label_pr("PR 501: social login method") == 501,
          "and keeps its number, so it is renamed instead of duplicated")
    check(not launch.reading_label("Review: PR 501"), "the agent workspace is not a reading workspace")
    check(not launch.reading_label("my notes on PR 12"), "a title mentioning a PR is not a reading workspace")


def test_repositories_are_named_the_way_the_reviewer_says_them():
    for name, want in [
        ("security-token-service", "sts"),
        ("cx-api-security-token-service", "sts"),
        ("identity-service", "identity"),
        ("sso-service", "sso"),
        ("cx-web-workspace", "web"),
        ("eink-bridge", "eink-bridge"),
    ]:
        check(launch.repo_label(name) == want, f"{name} is {want}")
    check(launch.repo_label("") == "pr", "an unnamed checkout still gets a label")


def test_stale_workspaces_are_reading_workspaces_without_a_live_editor():
    workspaces = [
        {"label": "PR 1: old", "workspace_id": "w1"},
        {"label": "💻 sts PR 2: live", "workspace_id": "w2"},
        {"label": "💻 web PR 3: mine", "workspace_id": "w3"},
        {"label": "Review batch: 2 PRs", "workspace_id": "w4"},
        {"label": "Nixos tasks", "workspace_id": "w5"},
    ]
    current = {"💻 web PR 3: mine": "/run/jump-pr-3.sock"}
    registry = [
        {"pr": "1", "socket": "/run/jump-pr-1.sock"},
        {"pr": "2", "socket": "/run/jump-pr-2.sock"},
    ]
    stale = launch.select_stale(
        workspaces, current, registry,
        lambda path: path == "/run/jump-pr-2.sock",
    )
    check([item["label"] for item in stale] == ["PR 1: old", "💻 web PR 3: mine"],
          "only workspaces without a live editor are offered")
    check(stale[0]["current"] is False, "an earlier review is marked as such")
    check(stale[1]["current"] is True, "a stale workspace of this batch is marked")
    check(not launch.reading_label("Review batch: 2 PRs"),
          "the agent workspace is not a reading workspace")


def test_pruning_the_registry_forgets_only_the_closed_reviews():
    with tempfile.TemporaryDirectory() as directory:
        saved = launch.REGISTRY
        try:
            launch.REGISTRY = pathlib.Path(directory) / "pr-reviews.json"
            launch.save_registry([{"pr": "1"}, {"pr": "2"}, {"pr": "3"}])
            launch.prune_registry([1, 3])
            check([row["pr"] for row in launch.load_registry()] == ["2"],
                  "closed reviews leave no registry rows behind")
        finally:
            launch.REGISTRY = saved


def test_the_registry_records_where_the_editor_is():
    with tempfile.TemporaryDirectory() as directory:
        saved = launch.REGISTRY
        try:
            launch.REGISTRY = pathlib.Path(directory) / "pr-reviews.json"
            launch.registry_entry(
                485, {}, pathlib.Path("/w/pr-485/security-token-service"),
                socket="/run/user/1000/jump-pr-485-security-token-service.sock",
                pane="w1:p2", title="A title", sha="abc123",
            )
            row = json.loads(launch.REGISTRY.read_text())["reviews"][0]
            check(row["pane_id"] == "w1:p2", "the pane is recorded for the skill to reuse")
            check(row["socket"].endswith("jump-pr-485-security-token-service.sock"), "the socket is recorded")
            check(row["sha"] == "abc123" and row["title"] == "A title", "the reviewed commit is recorded")
        finally:
            launch.REGISTRY = saved


def test_the_plan_names_every_review_and_marks_reuse():
    entries = [
        {"label": "PR 1: One", "repo_root": "/p/one", "worktree": "/p/worktrees/pr-1/one",
         "exists": True, "base": "main", "seed_path": "/s/pr-1.md"},
        {"label": "PR 2: Two", "repo_root": "/p/two", "worktree": "/p/worktrees/pr-2/two",
         "exists": False, "base": "release", "seed_path": "/s/batch.md"},
    ]
    text = "\n".join(launch.describe_plan(entries, "claude", "sonnet"))
    check("PR 1: One" in text and "PR 2: Two" in text, "every review is named")
    check("reuse" in text and "new" in text, "an existing worktree is marked as reused")
    check("claude" in text and "sonnet" in text, "the agent and model are shown")
    check("release" in text, "the base branch is shown")


print("paste parsing:")
test_parses_every_pull_request_in_the_order_written()
test_one_link_is_not_a_batch()
test_a_repeated_link_is_not_two_reviews()
test_non_pull_request_links_are_ignored()
test_the_prose_survives_without_the_links()
test_the_batch_brief_names_every_review_and_quotes_the_message()
test_choice_interpretation_is_explicit()
test_the_plan_names_every_review_and_marks_reuse()

test_reusing_a_worktree_checks_out_the_fetched_pull_request_head()
test_a_reading_workspace_names_its_repository_first()
test_repositories_are_named_the_way_the_reviewer_says_them()
test_stale_workspaces_are_reading_workspaces_without_a_live_editor()
test_pruning_the_registry_forgets_only_the_closed_reviews()
test_a_new_worktree_is_trusted_for_claude_without_losing_the_others()
test_the_socket_and_editor_command_are_per_pull_request()
test_the_registry_records_where_the_editor_is()

test_the_plan_table_stays_aligned_and_elides_long_names()

print()
if failures:
    print(f"{len(failures)} failed")
    sys.exit(1)
print("all checks passed")
