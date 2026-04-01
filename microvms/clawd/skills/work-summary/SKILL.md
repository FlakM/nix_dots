---
name: work-summary
description: "Summarize Maciek's recent work across Jira and GitHub. Use when asked: 'what did I do today/this week', 'standup summary', 'work summary', 'weekly report', 'what have I been working on'. Combines Jira issue activity with GitHub PR/commit history for a unified view."
metadata:
  openclaw:
    emoji: "📊"
    requires:
      bins: [jira, gh]
---

# Work Summary Skill

Summarize recent work by querying Jira (coralogix.atlassian.net) and GitHub.

## Identity

- Jira user: maciej.flak@coralogix.com
- GitHub user: FlakM

## Gathering Data

### Jira — recent issues

```bash
# Issues updated in the last 7 days assigned to me
jira issue list --assignee maciej.flak@coralogix.com --updated -7d --plain --columns key,summary,status,type --no-headers

# Details for a specific issue
jira issue view ISSUE-KEY --plain
```

Adjust `--updated` flag for the requested period: `-1d` for today, `-7d` for this week, `-14d` for two weeks.

### GitHub — recent PRs and commits

```bash
# PRs authored in the last 7 days across all Coralogix repos
gh search prs --author=FlakM --updated=">$(date -d '7 days ago' +%Y-%m-%d)" --json repository,title,state,url,updatedAt --limit 30

# Recent commits by me in a specific repo
gh api "/repos/{owner}/{repo}/commits?author=FlakM&since=$(date -d '7 days ago' --iso-8601=seconds)" --jq '.[].commit | "\(.committer.date) \(.message | split("\n")[0])"'
```

## Output Format

Structure the summary as:

1. **In Progress** — issues/PRs actively being worked on
2. **Completed** — issues moved to Done / PRs merged this period
3. **Reviews** — PRs where I'm a reviewer (if relevant)

Keep it concise. Group related Jira issues and PRs together when they reference the same work. Use bullet points, not tables.
