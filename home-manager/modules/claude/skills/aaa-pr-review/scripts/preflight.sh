#!/usr/bin/env bash
# Usage: bash preflight.sh <pr-number> [--checkout]
# Stdout: one JSON object {repo, pr, baseSha, blockers, ci, branch, changed}.
# On failure: exit 1 with {error:true, reason, hint?}.
set -uo pipefail

die() { jq -nc --arg r "$1" --arg h "${2:-}" '{error:true, reason:$r} + (if $h == "" then {} else {hint:$h} end)'; exit 1; }

pr="${1:-}"
[[ "$pr" =~ ^[0-9]+$ ]] || die "usage: preflight.sh <pr-number> [--checkout]"
checkout=false
[[ "${2:-}" == "--checkout" ]] && checkout=true

command -v gh >/dev/null || die "gh not installed" "install the GitHub CLI"
gh auth status >/dev/null 2>&1 || die "gh not authenticated" "run: gh auth login"

repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || die "could not resolve repo from origin"

meta=$(gh pr view "$pr" --repo "$repo" --json number,title,state,isDraft,author,headRefName,baseRefName,labels,url 2>&1) \
  || die "gh pr view failed: ${meta%%$'\n'*}"
baseSha=$(gh api "repos/$repo/pulls/$pr" --jq .base.sha 2>&1) || die "could not fetch base sha: $baseSha"

blockers=$(jq -c '[(if .isDraft then "draft" else empty end), (if any(.labels[]?; .name == "dont-review") then "dont-review" else empty end)]' <<<"$meta")

if checks=$(gh pr checks "$pr" --repo "$repo" --json name,bucket 2>/dev/null); then
  ci=$(jq -c '{total: length,
    passed: map(select(.bucket == "pass")) | length,
    failed: map(select(.bucket == "fail")) | length,
    pending: map(select(.bucket == "pending")) | length,
    other: map(select(.bucket != "pass" and .bucket != "fail" and .bucket != "pending")) | length,
    failing: map(select(.bucket == "fail") | .name)}' <<<"$checks")
else
  ci='{"available":false,"reason":"gh pr checks failed or no checks"}'
fi

original=$(git branch --show-current)
head=$(jq -r .headRefName <<<"$meta")
existed=false
git show-ref --verify --quiet "refs/heads/$head" && existed=true

if $checkout; then
  [[ -z "$(git status --porcelain)" ]] || die "working tree is dirty" "commit or stash, then re-run"
  out=$(gh pr checkout "$pr" --repo "$repo" 2>&1) || die "checkout failed: ${out%%$'\n'*}"
fi

git cat-file -e "$baseSha" 2>/dev/null || git fetch -q origin "$baseSha" 2>/dev/null || true

files=$(git diff --name-status -M "$baseSha"...HEAD | jq -Rsc 'split("\n") | map(select(length > 0) | split("\t") | {status: .[0][0:1], path: .[-1]} + (if length > 2 then {oldPath: .[1]} else {} end))')
lines=$(git diff --numstat "$baseSha"...HEAD | awk '$1 != "-" {s += $1 + $2} END {print s + 0}')

jq -nc --arg repo "$repo" --argjson pr "$meta" --arg baseSha "$baseSha" --argjson blockers "$blockers" \
  --argjson ci "$ci" --arg original "$original" --argjson existed "$existed" --argjson files "$files" --argjson lines "$lines" \
  '{repo:$repo, pr:($pr | {number, title, state, url, author: .author.login, headRefName, baseRefName}), baseSha:$baseSha,
    blockers:$blockers, ci:$ci, branch:{original:$original, existedLocally:$existed},
    changed:{files:$files, lines:$lines}}'
