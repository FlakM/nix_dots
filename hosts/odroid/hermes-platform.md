# Hermes platform: tracking, API, TUI, Vikunja, remote builds

Operational notes for the features added on 2026-10-23. **Full capability
index with examples (for you and for agents)**:
[`nix-coralogix-private/modules/hermes-agent/README.md`](https://github.com/FlakM/nix-coralogix-private/blob/main/modules/hermes-agent/README.md).
Design and contracts: `PLATFORM.md` in the same module.

## What runs where

| Piece | Host | Notes |
| --- | --- | --- |
| agent + HTTP API + reminders + mirror | odroid | `hermes-agent.service`, API on `127.0.0.1:8790` |
| `hermes`, `hermes-tui`, `hermes-bridge` | amd-pc | bridge is a systemd **user** service |
| quickshell panel | amd-pc | `ALT + H` or the bar icon |
| heavy jobs / nix builds | amd-pc | over SSH as `flakm@192.168.0.249` |

The agent never depends on amd-pc: if it is off, reminders still post to Slack and
the API still answers; only toasts, the TUI and remote jobs pause.

## Tracking a thread

"Tracked" means **explicitly added by Maciej** (a `track`, a `remind`, or a
natural-language request). Hermes still auto-follows ~120 recent threads and
notifies on activity, but those are *not* tracked: they do not show up in the
panel/TUI "tracked" list and take no Vikunja space.

In the control Slack channel (`#general`) or the TUI, either the command form:

```
track https://coralogix-dev.slack.com/archives/C03K13XKV6G/p1792741470105999 every 6h
track https://github.com/coralogix/sso-service/pull/226 every 1d
track https://coralogix.atlassian.net/browse/AAA-123 every 1d
untrack <key|url>
remind 6h            # this thread (opt-in timed reminders)
remind off
reminders 1d         # global default for newly tracked threads
```

or plain language in any message (Slack / TUI / API):

```
śledź ten wątek i przypominaj co 2 dni
dawaj znać o tym co 6 godzin
przestań mi o tym przypominać
wszystkie wątki przypominaj co 3 dni
dodaj zadanie: kup taśmę malarską jutro
```

Polish and English, including `co drugi dzień`, `codziennie`, `co tydzień`,
`every other day`; unusual phrasing falls back to one cheap model call inside a
tracked thread. Questions are left alone and answered normally.

* Reminders are **opt-in**: the auto-followed threads only notify on activity.
* A reminder fires when `now >= next_at` **and** nothing happened since the last
  one; new activity slides the window instead. Quiet hours: 22:00–08:00
  (`agent.tracking.quietHours`), max 5 per cycle.
* Text: `⏰ Still waiting · <summary> — <link> (last activity 3d ago)`, posted in
  the thread's card and pushed to the desktop as an event.

## Vikunja

* `track`ed threads are mirrored to **26 Coralogix - pilne** (title, priority
  P1→5 … P4→1, description with permalink + `Hermes-Key:` marker).
  Completing the task in Vikunja marks the thread done (and un-completing reopens
  it); marking done in Hermes completes the task. Auto-followed threads are
  never mirrored, so the ALT+T panel only ever holds real work.
* Natural language tasks go to **27 Dom · tydzień (Maciek)** by default:

```
task kup taśmę malarską jutro rano, pilne
task "review the auth RFC on Friday" --project coralogix
```

The model returns `{title, description, project, due_date, priority, labels}`;
on failure the text becomes the title in the personal project. Identical titles
created within an hour are deduplicated. Tasks appear in the quickshell panel
immediately (it reads the Vikunja API directly).

Plain-language creation works in any message — no command word needed:

```
Add to the Coralogix project: Clean up my Jira tasks
dodaj do projektu Coralogix: posprzątaj stare flagi
add task to the Inbox project: file the taxes
```

Projects are resolved by alias (`Coralogix`/`praca` → 26, `dom`/`personal` →
27) or by name/id (`Inbox`, `14`). An unknown explicit project is reported
instead of silently falling back to the personal one.

Token: `hermes_vikunja_token` (sops), scopes on projects 14/26/27, **expires
2027-10-23** — recreate with `PUT /api/v1/tokens` and update sops before then.

## Jira

Hermes can also create Jira issues on demand in `https://coralogix.atlassian.net`
(default project **CX**, default type **Task**):

```
utwórz jira ticket: posprzątaj stare feature flagi
create a jira issue in project CX: fix the redirect
jira: rotate the API token
jira CX: fix login loop
```

The project can be given as `CX:` at the start, `w projekcie CX` / `in project
CX` anywhere in the note; `bug`/`story`/`epic` in the request selects the issue
type. A second line becomes the description; the reply links to the issue.
Credentials: `jira_coralogix_token` (sops, read via `JIRA_TOKEN_FILE`) plus
`JIRA_EMAIL`. The pinned health card shows `jira credentials` and `jira auth` —
if the token is rejected, create a fresh API token at
<https://id.atlassian.com/manage-profile/security/api-tokens>, update
`jira_coralogix_token` in `secrets/secrets.yaml`, and redeploy.
The model-facing reference is `skills/tasks.md` in the agent module.

## Auto-cleanup

Threads disappear from the tracked/followed list when they stop needing
attention (`agent.tracking.autoClose`):

| rule | when |
| --- | --- |
| `merged` | every PR linked from the thread (or the tracked PR itself) is merged/closed — immediate |
| `review expired` | AI urgency ≥ 60 (review/decision requested) and idle ≥ 2 days |
| `stale` | anything else idle ≥ 4 days |

Starred (`important`) threads survive unless their PR is merged; snoozed threads
and threads without a known activity timestamp are never auto-closed. Closed
items are **not deleted**: they stay under `filter=done`
(`hermes list --filter done`), the detail shows `closed  <reason> · <date>`, and
their mirrored Vikunja task is completed. Bring one back with `follow`/`track`.

## amd-pc clients

```bash
hermes status                 # health, counts, cadence, unread
hermes list --json
hermes ask "what is waiting on me?"
hermes ask --mode investigate --thread <key>   # deep dive
hermes ask --mode draft --thread <key>         # suggested reply
hermes track <url> every 6h
hermes remind 6h --thread <key>
hermes reminders 6h
hermes task "kup mleko jutro"
hermes jira "fix the login loop" --project CX
hermes remote "nix build .#foo"   # runs on amd-pc, steps streamed
hermes notify "build finished"    # desktop toast via the bridge
hermes jobs [--cancel <id>]
hermes watch                  # raw event stream (scripting)
hermes-tui                    # full interactive client
```

`hermes-tui` (ALT+H): two-line rows with priority badges, AI headline, urgency
score and a waiting marker; repeated topics collapse into one row (`space`
expands, `enter` opens); `/` filters the list with a plain query (esc cancels);
`tab` switches tracked → followed → all; `j/k` move, `g/G` jump; `o` open,
`y` copy the link; `d` done, `i` important, `f` follow/unfollow; `s` snooze and
`R` remind open pickers; `t` track a link, `a` ask, `/` search, `i` command
line, `?` keys, `q` quit. The header shows connection, shown/waiting counts,
unread notifications, running jobs and the active filter. Same command words as
Slack, plus `notify`.

`hermes-bridge` subscribes to `/api/events`, sends `notify-send -a Hermes` and
writes `~/.cache/hermes/bridge.json` (`unread`, `events`, `jobs`, `threads`,
`connection`) which the quickshell panel polls every 5 s. First start adopts the
newest event id instead of toasting history.

Client config: `~/.config/hermes/client.env` (`HERMES_API_URL`,
`HERMES_API_TOKEN_FILE`), generated by home-manager from
`sops.secrets.hermes_api_token`.

## HTTP API

`https://hermes.house.flakm.com/api/…`, bearer token (`hermes_api_token`),
LAN/tailnet only.

```
GET  /api/health | /api/state | /api/usage | /api/jobs
GET  /api/threads?filter=tracked|followed|all|done   (tracked = explicitly added)
POST /api/threads | /api/tasks | /api/ask | /api/notify | /api/reminders | /api/remote/run
PATCH/DELETE /api/threads/{key}
POST /api/jobs/{id}/cancel
GET  /api/events?since=N&format=sse|json
```

`POST /api/ask` accepts `mode: ask|investigate|draft` (the latter two need a
`thread_key`). SSE frames are `id: N` + `data: {…}` with 20 s keepalives.

## Remote builds

`agent.remote.offload` allowlist: `nix build|run|develop`, `cargo build|test`,
`pytest`. Anything else is rejected before `ssh` runs. Key:
`/run/secrets/hermes_remote_ssh_key` (sops, also authorised on amd-pc).
`nix.settings.trusted-users = [ "flakm" ]` is set on amd-pc, so it can also act
as a nix build machine if `nix.buildMachines` is added later.

## Secrets (sops)

| Secret | Used by |
| --- | --- |
| `hermes_api_token` | API (odroid) + clients (amd-pc) |
| `hermes_vikunja_token` | Vikunja client (odroid), expires 2027-10-23 |
| `hermes_remote_ssh_key` | remote jobs (odroid → amd-pc) |

## Ops

* Health check covers `cx`, Slack, both models, codex sandbox, `nix run`,
  `gh`, `tracking`, `enrich`, `vikunja`, `api`, `remote` — and it is now a
  **single status card**: the same Slack message is edited in place every run
  and pinned once (`state["healthMessage"]`). If the log says
  `pin failed (missing_scope pins:write)`, add the `pins:write` bot scope to the
  control app and reinstall it; until then the card is still updated in place.
* **AI enrichment** (`enrich.py`) gives every thread a short `headline`, a stable
  `topic` slug and 0-100 `urgency` / `relevance`, using batched DeepSeek calls
  (8 threads per call, 16 per cycle, cached against `latest_ts`). The TUI shows
  the headline and score, collapses threads that share a topic into one row
  (`space` expands) and sorts by urgency.
* Logs: `journalctl -u hermes-agent -f` (odroid),
  `journalctl --user -u hermes-bridge -f` (amd-pc).
* Deploy odroid: push `nix_dots` + `nix flake update coralogix-private`, then
  `ssh flakm@192.168.0.102 'sudo systemctl start --no-block nixos-upgrade.service'`.
* Deploy amd-pc: `sudo nixos-rebuild switch --flake .#amd-pc`.
* If amd-pc's LAN address changes, update `agent.remote.host` (currently
  `192.168.0.249`; Tailscale SSH needs an interactive check, so LAN is used).
