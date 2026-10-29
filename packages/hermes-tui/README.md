# hermes-tui

A ratatui front end for the Hermes agent HTTP API: **conversations**, tracked
threads and live jobs in one terminal dashboard.

```bash
hermes-tui            # open the dashboard
hermes-tui --version
```

Configuration is shared with the Python CLI and bridge:
`~/.config/hermes/client.env`

```text
HERMES_API_URL=https://hermes.house.flakm.com
HERMES_API_TOKEN_FILE=/run/user/1000/secrets/hermes_api_token
```

`HERMES_API_URL`, `HERMES_API_TOKEN` and `HERMES_API_TOKEN_FILE` in the
environment win over the file.

## The four tabs

The tab bar is always visible: `1 Chat`, `2 Today`, `3 Threads`, `4 Jobs`.
`tab` and `shift+tab` cycle; `1`–`4` jump when a list has focus.

### Chat

Chat is the default tab and the composer is focused, so **typing a message and
pressing Enter starts a new conversation thread**. The first message names the
thread. `n` (from the thread list) or `ctrl+n` (from anywhere) starts another;
`:ask <question>` starts one and sends immediately.

Follow-ups send the transcript so far as the API's `conversation` field, so
context survives across messages. Hermes' job steps stream into the transcript
and the final answer lands under them. `ctrl+x` cancels a running answer.
`:investigate` and `:draft` open a thread bound to the selection from the
Threads tab; `a` there does the same. Conversations are stored in
`~/.local/state/hermes/conversations.json` and survive restarts (pending jobs
resume by polling the job id).

### Today

All work threads with activity since local midnight, regardless of whether they
are tracked, followed or already done. It uses the same rows, detail card and
actions as Threads, and refreshes on every event. The tab count shows how many
were active today; the block title keeps your position (`1/2`).

### Threads

Two-line rows for tracked Slack/PR/Jira threads: priority badge, urgency,
waiting marker, headline, then channel · kind · age · reminder cadence. Repeated
topics collapse into one group row (`space` expands). The filter chips
`Tracked / Followed / All` switch with `[` and `]`; `/` filters the list and
`esc` clears it.

| key | action |
| --- | --- |
| `j`/`k`, `g`/`G` | move, first/last |
| `enter`/`o` | open the link (group: expand) |
| `y` | copy the link |
| `a` | new Chat thread about the selection |
| `t` | track a link (prefills `:track `) |
| `d` / `i` / `f` | done / important / follow |
| `s` / `R` | snooze / reminder cadence picker |

### Jobs

Agent runs with their steps, plus the live event feed (notifications, job
steps, thread updates). `c` cancels a running job.

## Jumping between threads (herdr / tmux style)

`ctrl+l` opens the jump picker from anywhere — including while typing a chat
message. Type part of a conversation title or thread headline, move with
`↑`/`↓`, `enter` to jump. It lists local Chat conversations and all work threads,
and switches to the right tab with the target selected.

`ctrl+b` is a herdr/tmux-style prefix. The footer turns into a `PREFIX` bar:

| prefix key | action |
| --- | --- |
| `a` / `A` | next / previous thread instance in the current list |
| `j` / `k` | same as `a` / `A` |
| `1`–`4` | Chat / Today / Threads / Jobs |
| `h` / `l` | previous / next tab |
| `g` | the jump picker |
| `c` | start a new chat thread |
| `esc` | cancel the prefix (or let it expire after 3s) |

Unsaved composer drafts are kept per conversation, so jumping away and back does
not lose what you were typing. The list title shows your position (`3/12`) and
the tab bar counts active items.

## Commands

`:` opens the command bar (from a list; press `esc` first if the composer is
focused). The words match the Slack control surface: `track`, `untrack`,
`remind`, `reminders`, `task`, `notify`, `snooze`, `done`, `important`,
`follow`, `unfollow`, `search`, `history`, `remote`, `status`, plus `new` /
`chat` and `ask` / `investigate` / `draft`. `F1` opens the full help overlay
from anywhere, including while typing.

## Building

```bash
cargo build --offline            # local
cargo test --offline             # 44 offline unit/rendering tests
```

The Nix package is `../../packages/hermes-tui.nix`; the home-manager module
installs it as `hermes-tui`.

The crate is split into `config`, `api`, `events` (reconnecting SSE),
`chat` (persistence + transcript), `model` (defensive payload normalisation),
`app` (state machine) and `ui` (ratatui rendering).
