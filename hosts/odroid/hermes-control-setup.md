# Hermes control workspace setup

Hermes escalates into a **separate Slack workspace** instead of Telegram. Each
alert becomes its own Slack thread; replying in that thread is how you talk
about it and ask for more (summarize, investigate, draft, snooze, history…).

This is a one-time, human setup — the NixOS config is already wired and stays
inert until the secrets below exist.

## 1. Create the workspace

1. Create a new Slack workspace (e.g. `hermes-flakm`). Invite only yourself.
2. Set a recognizable name/icon for the workspace so notifications are obvious.

## 2. Create the app

1. <https://api.slack.com/apps> → **Create New App** → **From scratch**.
2. Pick the **new** workspace from step 1. Name it `Hermes`.
3. **OAuth & Permissions → Bot Token Scopes:**
   - `chat:write` – post/update cards and replies
   - `im:history`, `im:read`, `im:write` – read DMs and open the conversation
   - `channels:history` – read replies in the control channel
   - `channels:read`, `channels:manage` – look up / create the control channel
   - `app_mentions:read` – answer `@Hermes` mentions
   - `commands` – the `/hermes` slash command
   - `users:read` – name resolution in cards
   - `files:write` – forward thread attachments into the channel
4. **Install App to Workspace**, then copy the **Bot User OAuth Token**
   (`xoxb-…`).
5. **Basic Information → App-Level Tokens** → create one with scope
   `connections:write`. Copy it (`xapp-…`).
6. **Socket Mode** → toggle **on** (required: this is how Hermes receives your
   replies and button presses).
7. **Event Subscriptions → Subscribe to bot events:**
   - `message.channels` (replies in the control channel)
   - `message.im` (DMs)
   - `app_mention`
8. **Interactivity & Shortcuts** → toggle **on**.
9. **Slash Commands** → create `/hermes` (description "Ask Hermes about a
   thread"). No request URL needed with Socket Mode.
10. Nothing else: with `channels:manage`, Hermes creates the `#general` channel
    in the control workspace on first run. (Or create it yourself and
    `/invite @Hermes`.)

## 3. Find your user id in the new workspace

Profile → **⋯ → Copy member ID** (looks like `U0…`). It is **not** your work
workspace id.

## 4. Add the secrets

The config activates automatically once these keys exist (they are read with
`lib.hasInfix` at evaluation time; run `sops` on the odroid or wherever you
manage the file):

```bash
sops secrets/secrets.yaml   # edit, then:
# hermes_control_slack_bot_token: xoxb-…
# hermes_control_slack_app_token: xapp-…
# hermes_control_slack_user_id:   U0…
```

They are mounted as `*_FILE` into `hermes-agent.service` and restart it on
change. `escalation.slackControl.enable` flips on as soon as
`hermes_control_slack_bot_token` is present.

## 5. Deploy and verify

The new client lives in the `coralogix-private` flake input
(`modules/hermes-agent`). Push the `hermes-control-slack` branch (or merge it),
then bump the input so the odroid builds from it:

```bash
# in nix_dots, after the module repo is pushed:
nix flake update coralogix-private
```

Then deploy:

```bash
sudo nixos-rebuild switch --flake .#odroid
systemctl status hermes-agent
journalctl -u hermes-agent -f
```

- `control socket error` / `apps.connections.open failed` → check the
  app-level token and that Socket Mode is on.
- `Slack control enabled but CONTROL_SLACK_BOT_TOKEN is missing` → the secret
  did not land; check `systemctl show -p Environment hermes-agent`.
- No messages arrive → Hermes posts to `#general` in the control workspace. It
  creates that channel if `channels:manage` is granted; otherwise create it
  yourself, `/invite @Hermes`, and set `escalation.slackControl.channelName`.
- Bot can post but never sees your replies → add the `channels:history` scope
  and the `message.channels` event, then reinstall the app.

### How the odroid fetches the module

The odroid builds `github:FlakM/nix_dots#odroid`, whose lock pins
`coralogix-private`. Because that repo is private and the odroid has no
interactive GitHub access, it uses a **read-only SSH deploy key** on `root`:

```bash
sudo ssh-keygen -t ed25519 -f /root/.ssh/github_deploy -N "" -C "odroid-nix-deploy"
sudo tee -a /root/.ssh/config >/dev/null <<'EOF'
Host github.com
  IdentityFile /root/.ssh/github_deploy
  IdentitiesOnly yes
EOF
sudo cat /root/.ssh/github_deploy.pub   # add as a read-only Deploy Key:
# https://github.com/FlakM/nix-coralogix-private/settings/keys
```

Once the key is added, `sudo ssh -T git@github.com` succeeds and the 03:00
autoUpgrade fetches new module revisions automatically. Do **not** re-add a
`--override-input coralogix-private path:…` to `system.autoUpgrade.flags`: it is
baked into the unit when the *current* system is built, so it would pin the
previous module and new versions would never arrive.

If you ever need to deploy a local (uncommitted) module revision without the
key, stage it and rebuild with a temporary CLI override — run it in a login
shell with a real `PATH` (a plain `systemd-run` unit fails activation with
`[Errno 2] ... 'test'`):

```bash
git -C ~/programming/flakm/nix-coralogix-private archive main \
  | ssh flakm@odroid 'rm -rf ~/hermes-module && mkdir -p ~/hermes-module && tar -x -C ~/hermes-module'
ssh flakm@odroid "sudo bash -lc '
  export PATH=/run/current-system/sw/bin:/run/wrappers/bin
  nixos-rebuild switch --flake github:FlakM/nix_dots#odroid -L \
    --override-input coralogix-private path:/home/flakm/hermes-module'"
```

## What you can send

Reply in any alert thread (or DM Hermes):

| Message | Effect |
| --- | --- |
| `list` / `status` | tracked + followed threads |
| `history <query>` | search Hermes's own history of past threads |
| `important` · `follow` · `unfollow` · `done` | toggle thread state |
| `snooze 2h` (also `30m`, `1d`, `tomorrow`) | mute the thread |
| `investigate` | read-only `cx` / repo investigation |
| `draft` | suggested reply for the thread |
| anything else | a question about the thread — Hermes decides whether to use `cx`, the repos, or its history database |

Buttons on each card mirror these actions.

## Notes

- The **work workspace** stays read-only: Hermes keeps triaging the watched
  channels there; only the control surface moved to the new workspace.
- History lives in a SQLite DB at `<memoryDir>/history.db`
  (`/home/flakm/.local/share/hermes-agent/memory/history.db`), recording every
  thread Hermes has seen, whether or not it escalated. `sqlite3` is on the
  service `PATH` so the agent can query it during an `ask`.
- Telegram is disabled (`escalation.telegram.enable = false`) but the code and
  secrets remain, so flipping it back on is a one-line change.
