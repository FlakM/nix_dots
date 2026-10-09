#!/usr/bin/env bash
# Usage: bash pr-context.sh <pr-number> <repo owner/name> <out-path>
# Writes a markdown context file (description, review threads, review bodies, top-level comments).
# Stdout: {contextPath, warnings, counts, threads} — threads is a body-free index.
set -uo pipefail

pr="$1"; repo="$2"; out="$3"
owner="${repo%%/*}"; name="${repo##*/}"
bots='["coderabbitai","baz-reviewer","copilot","github-actions","chatgpt-codex-connector","claude"]'
warnings='[]'
warn() { warnings=$(jq -c --arg w "$1" '. + [$w]' <<<"$warnings"); }

query='query($owner: String!, $repo: String!, $pr: Int!, $after: String) {
  repository(owner: $owner, name: $repo) { pullRequest(number: $pr) {
    reviewThreads(first: 100, after: $after) {
      nodes { id isResolved isOutdated path line
        comments(first: 50) { totalCount nodes { body author { login } } } }
      pageInfo { hasNextPage endCursor } } } } }'

threads='[]'; after=null
for _ in $(seq 1 20); do
  res=$(jq -nc --arg q "$query" --arg o "$owner" --arg n "$name" --argjson p "$pr" --argjson a "$after" \
    '{query:$q, variables:{owner:$o, repo:$n, pr:$p, after:$a}}' | gh api graphql --input - 2>&1) \
    || { warn "review threads unavailable: ${res%%$'\n'*}"; break; }
  threads=$(jq -c --argjson t "$threads" '$t + .data.repository.pullRequest.reviewThreads.nodes' <<<"$res")
  [[ $(jq -r .data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage <<<"$res") == true ]] || break
  after=$(jq -c .data.repository.pullRequest.reviewThreads.pageInfo.endCursor <<<"$res")
done

reviews=$(gh api "repos/$repo/pulls/$pr/reviews" --paginate --jq '.[] | select(.body != "") | {author: .user.login, state, body}' 2>&1 | jq -sc .) \
  || { warn "review bodies unavailable"; reviews='[]'; }
comments=$(gh api "repos/$repo/issues/$pr/comments" --paginate --jq '.[] | select(.body != "") | {author: .user.login, body}' 2>&1 | jq -sc .) \
  || { warn "top-level comments unavailable"; comments='[]'; }
body=$(gh pr view "$pr" --repo "$repo" --json body --jq .body 2>/dev/null) || { warn "PR description unavailable"; body="**Description could not be fetched** - do not treat as no rationale."; }
[[ -n "${body// }" ]] || body="No description provided."

index=$(jq -c --argjson bots "$bots" '
  def isbot: (. // "" | ascii_downcase) as $l | ($l | endswith("[bot]")) or any($bots[]; $l == . or ($l | startswith(. + "[")));
  map({id, path: (.path // "(no path)"), line, author: .comments.nodes[0].author.login,
       isBot: (.comments.nodes[0].author.login | isbot),
       state: (if (.isResolved | not) and (.isOutdated | not) then "open"
               elif (.isResolved | not) then "outdated"
               elif (.comments.nodes[0].author.login | isbot) then "dismissedBot" else "resolved" end),
       comments: .comments.nodes})' <<<"$threads")

{
  printf '# PR Context for PR #%s\n\n## Description\n\n<!-- description:start -->\n%s\n<!-- description:end -->\n\n' "$pr" "$body"
  printf '## Review Comments\n\n'
  jq -r 'map(select(.state != "dismissedBot")) | group_by(.path)[] | "### \(.[0].path)\n" + (sort_by(.line // 0) | map("- [\(.state | ascii_upcase)] L\(.line // "?") @\(.author): \(.comments[0].body)" + (.comments[1:] | map("\n  - Reply @\(.author.login): \(.body)") | join(""))) | join("\n")) + "\n"' <<<"$index"
  printf '## Dismissed Bot Comments\n\n'
  jq -r 'map(select(.state == "dismissedBot")) | group_by(.path)[] | "### \(.[0].path)\n" + (map("- [DISMISSED] L\(.line // "?") @\(.author): \(.comments[0].body)" + (.comments[1:] | map("\n  - Reply @\(.author.login): \(.body)") | join(""))) | join("\n")) + "\n"' <<<"$index"
  printf '## Review Bodies\n\n'
  jq -r '.[] | "- @\(.author) (\(.state)): \(.body)"' <<<"$reviews"
  printf '\n## Top-Level Comments\n\n'
  jq -r '.[] | "- @\(.author): \(.body)"' <<<"$comments"
  if [[ "$warnings" != "[]" ]]; then printf '\n## Warnings\n\n'; jq -r '.[] | "- \(.)"' <<<"$warnings"; fi
} >"$out"

jq -nc --arg p "$out" --argjson w "$warnings" --argjson i "$index" --argjson r "$reviews" --argjson c "$comments" \
  '{contextPath:$p, warnings:$w,
    counts:{open: ($i | map(select(.state=="open")) | length), outdated: ($i | map(select(.state=="outdated")) | length),
            resolved: ($i | map(select(.state=="resolved")) | length), dismissedBot: ($i | map(select(.state=="dismissedBot")) | length),
            reviewBodies: ($r | length), topLevel: ($c | length)},
    threads: ($i | map(del(.comments)))}'
