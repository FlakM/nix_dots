# clawd — NixOS MicroVM on amd-pc

A lightweight KVM-accelerated NixOS guest, network-isolated via a NAT bridge.

## Quick Access

```bash
ssh clawd          # → flakm@192.168.100.10
ping clawd         # resolves via /etc/hosts
```

The `ssh clawd` shortcut is configured in `/etc/ssh/ssh_config` on the host
(via `programs.ssh.extraConfig` in `microvm.nix`).

---

## Architecture

```
amd-pc (host)
│
├─ microbr0  192.168.100.1/24          ← bridge, NAT to enp14s0
│   └─ tap   vm-clawd                  ← VM's tap interface
│
└─ microvm@clawd.service               ← QEMU/KVM process (user: microvm)
    ├─ /nix/store        → erofs (read-only, immutable NixOS store)
    ├─ /var              → ext4 image   clawd-var.img   (4 GB, persistent)
    └─ rootfs            → tmpfs (in-memory, rebuilt every boot)
```

### ZFS Storage

The VM's data lives on a dedicated ZFS dataset:

| ZFS dataset                   | Mount point (host)         | Purpose               |
|-------------------------------|----------------------------|-----------------------|
| `rpool/nixos/microvms/clawd`  | `/var/lib/microvms/clawd`  | VM working directory  |

Inside that dataset:

```
/var/lib/microvms/clawd/
  clawd-var.img    ← 4 GB raw ext4, mounted as /var inside the VM
  current          ← symlink → current microvm store build
  booted           ← symlink → last-booted build (used for shutdown)
  toplevel         ← symlink → NixOS system closure
  clawd.sock       ← QEMU monitor socket
```

The dataset has `mountpoint=legacy` and is mounted via the host's
`fileSystems` option with `nofail` — a missing dataset will not prevent boot.

**Snapshots & replication:** sanoid snapshots `rpool/nixos/microvms/clawd`
on the same schedule as the home dataset (hourly × 36, daily × 30, monthly × 3).
syncoid replicates it to odroid alongside other datasets.

### Networking

```
VM  192.168.100.10
Host bridge  192.168.100.1
Internet  → NAT via enp14s0
```

The host's firewall is unchanged; the VM can initiate outbound connections.
Inbound connections from outside the host are not possible without explicit
port-forwarding rules.

---

## Security

### What is isolated

- **No host Claude session sharing**: the VM does not mount the host `~/.claude`
  directory or inherit Claude OAuth state.
- **KVM isolation**: QEMU runs as the unprivileged `microvm` system user
  (gid `kvm`), not root.
- **NAT network**: the VM cannot reach other hosts on the LAN directly;
  all traffic is masqueraded through the host.
- **SSH hardened**: no root login, no password auth, key-only access.

### What is shared intentionally

- **Bot and GitHub secrets only**: the VM receives `nextcloud_talk_bot_secret`
  and `github_token` via a dedicated read-only `9p` mount at `/run/host-secrets`.
- **Persistent user state**: `/home/flakm` is a symlink to `/var/home/flakm`, so
  shell history, OpenClaw auth, and user config survive VM restarts.

### What is NOT isolated (known limitations)

- **QEMU process on host**: a VM escape would give access to the `microvm`
  user account and the KVM device. No additional seccomp sandbox is
  configured beyond the NixOS defaults.
- **Bridge traffic**: multiple VMs on `microbr0` can communicate directly
  with each other. Currently only `clawd` is on the bridge.

### VM kernel hardening (sysctl)

```
kernel.kptr_restrict  = 2   # hide kernel pointers
kernel.dmesg_restrict = 1   # unprivileged dmesg blocked
net.ipv4.conf.*.rp_filter = 1  # strict reverse-path filtering
```

---

## Service management

```bash
# Status
systemctl status microvm@clawd.service

# Restart (graceful — sends SIGTERM to QEMU, VM shuts down cleanly)
sudo systemctl restart microvm@clawd.service

# Stop / Start
sudo systemctl stop  microvm@clawd.service
sudo systemctl start microvm@clawd.service

# Reset rate-limit after repeated failures
sudo systemctl reset-failed microvm@clawd.service
```

The service has `StartLimitIntervalSec=0` so systemd never permanently gives
up restarting after transient failures.

---

## Maintenance

### Update the VM NixOS config

Edit `microvms/clawd/default.nix`, then rebuild the host:

```bash
sudo nixos-rebuild switch --flake ~/programming/flakm/nix_dots#amd-pc
```

The new config takes effect on the next VM restart (microvm uses a boot-time
switch, not live switch).

### One-time ZFS dataset creation (only needed on a fresh install)

```bash
sudo zfs create -o mountpoint=legacy rpool/nixos/microvms/clawd
```

### Manual snapshot / inspect ZFS

```bash
# List snapshots
sudo zfs list -t snapshot rpool/nixos/microvms/clawd

# Take a manual snapshot
sudo zfs snapshot rpool/nixos/microvms/clawd@before-experiment

# Roll back (VM must be stopped first)
sudo systemctl stop microvm@clawd.service
sudo zfs rollback rpool/nixos/microvms/clawd@before-experiment
sudo systemctl start microwd@clawd.service
```

### Debug / monitor

```bash
# Network traffic on the bridge
sudo iftop -i microbr0
sudo tcpdump -i microbr0 -n

# NAT rules
sudo nft list ruleset

# Resource usage
systemd-cgtop
systemctl show microvm@clawd | grep -E "Memory|CPU"

# VM console (QEMU monitor)
socat - unix-connect:/var/lib/microvms/clawd/clawd.sock
```

---

## OpenClaw

OpenClaw is managed declaratively via `nix-openclaw.nixosModules.openclaw-gateway`, with
runtime state stored under `/var/home/flakm/.openclaw`.

### Design goals

- Keep Nix as the source of truth for the gateway and channel config.
- Keep user auth local to the VM instead of borrowing host Claude credentials.
- Persist user state, shell history, and OpenClaw runtime data under `/var/home/flakm`.
- Allow one-time manual provider login when needed, without reintroducing host coupling.

The gateway runs as `openclaw-gateway.service` on every boot. Gateway auth is disabled
(`gateway.auth.mode = "none"`) because the VM is network-isolated. Nix writes the base
config to `/etc/openclaw/openclaw.json`, and a boot-time seeding step copies it into the
writable state dir at `/var/home/flakm/.openclaw/openclaw.json` while preserving runtime
metadata.

### First-time: login with OpenAI Pro (headless OAuth)

The VM has no browser, so use the manual redirect flow inside the VM. This auth is stored
locally in `/var/home/flakm/.openclaw` and survives reboots.

```bash
ssh clawd
openclaw models auth login --provider openai-codex
```

OpenClaw prints an auth URL. Open it in your browser on the host, log in, then copy the
full redirect URL from the address bar (it will fail to load) and paste it back in the VM.
No host `~/.claude` mount is involved.

### Secrets and defaults

- Host secrets are staged on `amd-pc` into `/run/clawd-secrets` and mounted read-only
  inside the guest at `/run/host-secrets`.
- On boot, `openclaw-seed-config` copies those files into
  `/var/home/flakm/.openclaw/secrets` and regenerates `github-env` for shells.
- The default agent model is `openai-codex/gpt-5.4`.
- WhatsApp has been removed from this VM; `nextcloud-talk` is the only configured channel.

### First-time: gh login

You should not need a manual `gh auth login` in the VM, because `GH_TOKEN` and
`GITHUB_TOKEN` are generated from the mounted host secret.

### Using OpenClaw

```bash
openclaw tui   # gateway auto-starts on boot, no manual daemon setup needed
```

If you want to verify the active model from the CLI:

```bash
openclaw agent --session-id 66c6421d-58e0-4dfb-a027-c86029368bd3 --message 'reply with ok' --json
```

That should report `openai-codex` / `gpt-5.4` in the result metadata.

### Shell state

The VM is set up so these files persist across reboots:

- `/var/home/flakm/.bash_history`
- `/var/home/flakm/.zsh_history`
- `/var/home/flakm/.config/atuin`
- `/var/home/flakm/.local/share/atuin`
- `/var/home/flakm/.openclaw`

### Testing checklist

After `nixos-rebuild switch --flake .#amd-pc` + VM restart:

- [ ] `systemctl status microvm@clawd.service` — VM running
- [ ] `ssh clawd` — SSH reachable
- [ ] `systemctl status openclaw-gateway` (inside VM) — `active (running)`
- [ ] `echo $SHELL` (inside VM) — `/run/current-system/sw/bin/zsh`
- [ ] `ls /run/host-secrets` (inside VM) — mounted `github_token` and `nextcloud_talk_bot_secret`
- [ ] `openclaw tui` (inside VM) — opens TUI without auth error
- [ ] `history | tail` and `atuin history list` still show entries after reboot
- [ ] `openclaw tui` still works after VM reboot (token persists in `/var`)
- [ ] `openclaw health` (inside VM) — `Nextcloud Talk: configured`

---

### Reset the VM disk (wipes /var)

```bash
sudo systemctl stop microvm@clawd.service
sudo rm /var/lib/microvms/clawd/clawd-var.img
sudo systemctl start microvm@clawd.service
# VM will create a fresh ext4 image on next start
```
