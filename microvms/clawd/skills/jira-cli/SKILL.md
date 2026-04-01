---
name: jira-cli
description: "Jira operations via the `jira` CLI (jira-cli-go): list/view/create/edit/transition issues, manage sprints, epics, and boards. Use when: (1) listing or searching Jira issues, (2) viewing issue details, (3) creating or updating issues, (4) transitioning issue status, (5) managing sprints or boards. NOT for: bulk imports, Jira admin, or webhook configuration."
metadata:
  openclaw:
    emoji: "🎫"
    requires:
      bins: [jira]
---

# Jira CLI Skill

Use the `jira` CLI (jira-cli-go) to interact with Jira Cloud at coralogix.atlassian.net.

## Identity

- Login: maciej.flak@coralogix.com
- Server: https://coralogix.atlassian.net
- Auth: `JIRA_API_TOKEN` env var (pre-configured)

## Common Commands

### List issues

```bash
# My open issues
jira issue list -a maciej.flak@coralogix.com -s "In Progress" -s "To Do" --plain --no-truncate

# Issues updated recently
jira issue list -a maciej.flak@coralogix.com --updated -7d --plain

# Search by text
jira issue list "search query" --plain

# Filter by type, priority, label
jira issue list -t Story -yHigh -lbackend --plain

# Issues in a specific project
jira issue list -p PROJ --plain
```

### View issue

```bash
jira issue view ISSUE-KEY --plain
# With comments
jira issue view ISSUE-KEY --plain --comments 10
```

### Create issue

```bash
jira issue create -t Story -s "Issue summary" -b "Description body" -p PROJ
# Interactive (will prompt for fields)
jira issue create
```

### Edit / update

```bash
# Edit summary
jira issue edit ISSUE-KEY -s "New summary"
# Add comment
jira issue comment add ISSUE-KEY -b "Comment body"
# Assign
jira issue assign ISSUE-KEY maciej.flak@coralogix.com
```

### Transition status

```bash
# Move issue to a new status
jira issue move ISSUE-KEY "In Progress"
jira issue move ISSUE-KEY "Done"
```

### Sprints

```bash
# List sprints for a board
jira sprint list --board-id <ID> --plain
# Current sprint issues
jira sprint list --board-id <ID> --state active --plain
```

### Epics

```bash
jira epic list --plain
jira epic add EPIC-KEY ISSUE-KEY
```

## Date filters

The `--created` and `--updated` flags accept:
- Relative: `today`, `week`, `month`, `year`
- Period: `-7d`, `-2w`, `-1h`
- Absolute: `2026-03-01`

## Output flags

- `--plain` — non-interactive table output (always use for scripting)
- `--no-headers` — hide table headers
- `--no-truncate` — show full field values
- `--columns key,summary,status,type,assignee` — select columns
