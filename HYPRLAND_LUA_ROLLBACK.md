# Hyprland lua cutover — rollback

This repo migrated Hyprland from the legacy `hyprland.conf` format to the new
lua config introduced in v0.55. Use this document if anything in the new
config misbehaves and you need to get back to a known-working state.

## Tags

| Tag                    | Commit | Meaning |
|------------------------|--------|---------|
| `pre-hyprland-lua`     | a356ae2 | Last good state on Hyprland 0.54 + `hyprland.conf`. The rollback target. |
| `hyprland-lua-cutover` | 325ab1e | The cutover commit. Bumps to 0.55 and adds the lua config. |

`git show <tag>` to inspect either.

## What the cutover did

- `flake.lock`: Hyprland 0.54.0 → 0.55.0 (+ aquamarine, hyprutils, hyprwire, xdph bumps).
- `home-manager/modules/hyprland.nix`:
  - dropped the `hyprland-fixed` `overrideAttrs` (upstream CMake now installs `hyprland.lua`, so the `touch example/hyprland.conf` workaround is obsolete);
  - added `xdg.configFile."hypr/hyprland.lua"` — the active config;
  - **kept** `wayland.windowManager.hyprland.extraConfig` — `hyprland.conf` is still written to disk as a fallback.

Hyprland prefers `hyprland.lua` over `hyprland.conf` at startup
(`src/config/supplementary/jeremy/Jeremy.cpp`). The choice is made **only at
startup**: `hyprctl reload` does not switch managers, you must log out and back in.

## Rollback procedures

Pick the lightest tier that fixes the symptom.

### Tier 1 — Hyprland boots, something is wrong (fastest, no rebuild)

Disable the lua file; Hyprland falls back to the still-present `hyprland.conf`.

```sh
rm ~/.config/hypr/hyprland.lua
hyprctl dispatch exit          # logs you out of Hyprland
# log back in — you're now running the legacy hyprland.conf
```

The next `nixos-rebuild switch` will recreate the symlink (home-manager
re-applies the file). This buys you time to debug without rebuilding.

### Tier 2 — Hyprland fails to start, you're stuck at SDDM or a TTY

Same fix, run it from a TTY (`Ctrl+Alt+F2`, log in as `flakm`):

```sh
rm ~/.config/hypr/hyprland.lua
# log back into Hyprland (Ctrl+Alt+F1 or via SDDM) — uses hyprland.conf
```

### Tier 3 — even hyprland.conf is broken

Boot Hyprland in safe mode from a TTY; it loads
`/tmp/hypr/<instance>/recoverycfg.conf` (auto-generated minimal config):

```sh
HYPRLAND_SAFE=1 Hyprland
```

You'll get a barebones session — enough to open a terminal and fix things.

### Tier 4 — permanent revert via git

After Tier 1/2 unblocks you, undo the change properly:

```sh
cd ~/programming/flakm/nix_dots

# Option A: reset main to the rollback tag (rewrites the cutover commit out).
#   Safe because the cutover is the only commit on top of pre-hyprland-lua,
#   and nothing has been pushed to origin/main yet.
git reset --hard pre-hyprland-lua

# Option B: keep the cutover commit in history but add an inverse commit.
git revert hyprland-lua-cutover

# Re-apply the system
sudo nixos-rebuild switch --flake .#amd-pc
```

Then log out / back in. You're back on Hyprland 0.54 + `hyprland.conf`.

## Verifying which manager is active

```sh
journalctl --user -u hyprland-session.target -b | grep '\[cfg\]' | tail -5
# Lua active:    [cfg] Using lua config found at /home/flakm/.config/hypr/hyprland.lua
# Conf fallback: [cfg] Lua config not found, using legacy config at .../hyprland.conf
```

## When to remove this safety net

Once the lua config has been stable for ~1 week across normal usage
(workspace launches, locks, theme switch, screenshots, audio/brightness keys),
delete the `wayland.windowManager.hyprland.extraConfig = ''…''` block from
`home-manager/modules/hyprland.nix` and this file. The `hyprland.conf`
symlink will disappear on the next rebuild, leaving lua as the single source
of truth.
