---
name: vikunja
description: Manage the house Vikunja instance (tasks.house.flakm.com) — task lists, priorities, due dates, and who can access which project. Use when asked what is on the task list, to add/complete/prioritise/reschedule a task, to keep the list of most important tasks current, or to check or change project access ("kto ma dostęp", "dodaj taska", "co mam do zrobienia", "ustaw priorytet", "przenieś termin", "daj dostęp do projektu").
---

Vikunja at `tasks.house.flakm.com` (server 2.7.0, behind nginx, ipextraction xff). Three tools are on PATH with credentials already wired from sops:

- `vikunja-cli` — read and create tasks and projects. Full flag/endpoint reference: the `vikunja-cli` skill (`~/.claude/skills/vikunja-cli/references/command-reference.md`).
- `vikunja-task` — mutations (complete, priority, due, title, description, delete).
- `vikunja-acl` — project access (who can see/edit what).

## The important-task list

"Important" is the Vikunja priority field, not a separate project or label. The QuickShell dashboard's star sets priority **4** and clears it to **0**; anything with `priority >= 2` shows up in its "WAŻNE" section, ordered by priority then due date. Keep that list short — it is the answer to "what should I do next".

The **current task** ("W TOKU") is the `doing` label (`VIKUNJA_FOCUS_LABEL`), carried by at most one open task and enforced by `vikunja-task focus`: it strips the label from every other task, and `done` clears it. The dashboard's ▶ button toggles it; the bar icon switches to a play symbol while a task is focused.

## Tasks

```bash
vikunja-cli tasks list --filter "done = false" --sort due_date --order-by asc --per-page 100
vikunja-cli tasks list --filter "done = false && priority >= 2"          # the important list
vikunja-cli tasks list --project-id 15 --search "lampy"
vikunja-cli tasks create --project-id 15 --title "Zamówić router" --priority 4 --due-date "2026-10-25T18:00:00+02:00"
vikunja-cli tasks comments create --task-id 42 --comment "Czeka na dostawę<br>Zamówione 19.10"

vikunja-task get 42                                    # JSON, to check before/after
vikunja-task priority 42 4                             # promote to important (0 clears)
vikunja-task due 42 today                              # today|tomorrow|week|YYYY-MM-DD|clear
vikunja-task title 42 "Zamówić router Omada"
vikunja-task description 42 "linia 1<br>linia 2"
vikunja-task focus 42                                  # "I'm working on this now"
vikunja-task focused                                   # the current task, or null
vikunja-task unfocus                                   # clear it (or unfocus 42)
vikunja-task done 42
vikunja-task reopen 42
vikunja-task delete 42
```

- Projects: `14` Inbox, `15` Dom (the shared home pool), `21` Weekend walecznej 🐞 (maciek), `26` Coralogix - pilne (work queue), `27` Dom · tydzień (Maciek) and `28` Dom · tydzień (Patrycja) — the personal "this week" plans. Re-read with `vikunja-cli projects list` — ids and owners drift.
- Text fields need `<br>` for line breaks; plain newlines get mangled.
- Due presets resolve to 18:00 local (Europe/Warsaw) and are sent as RFC3339 with the local offset.
- The QuickShell dashboard (`quickshell-vikunja list`) renders three columns: the week plan (`VIKUNJA_WEEK_PROJECT`), the work queue (`VIKUNJA_WORK_PROJECT`) and the calendar week; the focused task sits above them. Tasks move into the week plan by being moved into that project. Toggle with **Alt+T**; the footer lists the keys (⏎ open, p focus, s important, t due, d done, r refresh, Esc close).

## Project access

```bash
vikunja-acl projects                     # id, title, owner
vikunja-acl whoami                       # which account these tools act as (bot)
vikunja-acl access 15                    # users and their rights
vikunja-acl add 15 patrycja write
vikunja-acl set 15 patrycja admin
vikunja-acl remove 15 patrycja
```

Rights: `read` = view only, `write` = view + edit tasks, `admin` = also add/remove people. Numbers `0/1/2` work too. Each user prints as one JSON object: `{"username":...,"right":...,"level":...}`.

Owner is implicit and never listed by `access`; the account `bot` owns `14` and `15` and has admin on `21`.

Under the hood (Vikunja 2.x): `GET|PUT /api/v1/projects/{id}/users`, `POST|DELETE /api/v1/projects/{id}/users/{username}`. Members are addressed by **username** — sending `user_id` returns `1005 The user does not exist`.

## Gotchas

- **Never edit a task with `vikunja-cli tasks update`.** Vikunja replaces the whole task on `POST /tasks/{id}`, and the CLI sends a body built from the flags alone, so anything you did not pass is blanked — priority, due date, description, and even assignees vanish. `vikunja-task` exists precisely for this: it reads the task, patches one field, and writes the whole object back.
- `POST /api/v1/login` is rate limited to **10/min**; the tools cache the JWT for ~9 minutes and re-login only when it expires. Do not script logins in a loop — a burst returns `429` with `retry-after`.
- Share links are disabled (`enablelinksharing = false`), so `projects shares …` returns 404. There are no teams; all access is per user.
- Delete anything you create for probing. Never leave a probe task in `Dom`/`Weekend`.

## What you are editing

Everything lives in `~/programming/flakm/nix_dots`:

- `home-manager/modules/vikunja.nix` — credentials, `vikunja-cli` wrapper, `vikunja-acl`, `vikunja-task`, `quickshell-vikunja`
- `home-manager/modules/vikunja/{lib.sh,vikunja-acl.sh,vikunja-task.sh,quickshell-vikunja.sh}`
- `home-manager/modules/quickshell/desktop/VikunjaPanel.qml`, `VikunjaTaskRow.qml`, `shell.qml` — the dashboard

Deploy after a change: `sudo nixos-rebuild switch --flake ~/programming/flakm/nix_dots#amd-pc` (home-manager is wired into the host, and the QuickShell service restarts when its QML changes).
