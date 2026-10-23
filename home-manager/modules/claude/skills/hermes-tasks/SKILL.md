---
name: hermes-tasks
description: Create work items on demand — Vikunja tasks and Jira issues — through Hermes, including from a read-only workspace. Use when asked to "add this to the Coralogix project", "dodaj taska", "utwórz jira ticket", "create a Jira issue", or when a task should land in Vikunja/Jira without editing files.
---

# Creating tasks through Hermes

Hermes (the Slack triage agent on the odroid) exposes task creation as an HTTP
API, so it works even where the local workspace is read-only and the usual CLI
cannot write its JWT cache.

## Vikunja

```bash
hermes task "kup taśmę malarską jutro rano, pilne"
hermes task "review the auth RFC on Friday" --project coralogix
hermes task "file the taxes" --project 14
```

In Slack (control workspace) the same thing works as a plain message:

```
dodaj zadanie kup mleko jutro
add task to the Inbox project: file the taxes
Add to the Coralogix project: Clean up my Jira tasks
```

Projects: `Coralogix`/`praca`/`work` → 26, `dom`/`personal` → 27, or any name
(`Inbox`) / numeric id. Titles created twice within an hour are deduplicated.
The CLI prints the task URL.

## Jira

```bash
hermes jira "fix the login loop" --project CX
```

```
utwórz jira ticket: posprzątaj stare feature flagi
create a jira issue in project CX: fix the redirect
jira: rotate the API token
```

Default project `CX`, default type `Task`; `bug`/`story`/`epic` selects the
type. The reply contains the issue key and browse URL. If the health card shows
`jira auth` red, the API token in sops (`jira_coralogix_token`) is rejected —
create a fresh one at <https://id.atlassian.com/manage-profile/security/api-tokens>
and update `secrets/secrets.yaml`.

## If the API is not reachable

`vikunja-cli` still works on the amd-pc (the `vikunja` skill); Hermes lives at
`https://hermes.house.flakm.com` behind the bearer token in
`~/.config/hermes/client.env`. State: `/var/lib/hermes-agent/state.json`.
