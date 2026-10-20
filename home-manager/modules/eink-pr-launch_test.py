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

test_the_socket_and_editor_command_are_per_pull_request()
test_the_registry_records_where_the_editor_is()

test_the_plan_table_stays_aligned_and_elides_long_names()

print()
if failures:
    print(f"{len(failures)} failed")
    sys.exit(1)
print("all checks passed")
