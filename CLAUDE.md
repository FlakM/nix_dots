# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with Maciek's NixOS configuration repository.

## Repository Overview

A comprehensive NixOS/nix-darwin flake configuration for multiple machines with home-manager integration. Uses nixpkgs 25.11 stable with unstable/master overlays for select packages.

### Core Architecture:
- **Multi-channel setup**: stable (25.11), unstable, and master nixpkgs channels
- **Flake inputs**: Hyprland (latest git), fenix (Rust), sops-nix, darwin, home-manager
- **Cross-platform**: NixOS (Linux) + nix-darwin (macOS) with shared modules
- **Secrets management**: SOPS with Yubikey integration

### Host Configuration:
- **amd-pc**: Primary Linux workstation (x86_64-linux) - main development machine
- **dell-xps**: Laptop Linux system (x86_64-linux)
- **odroid**: Server/homelab system (x86_64-linux) - self-hosted services
- **air**: macOS laptop (aarch64-darwin)
- **work**: macOS work machine (aarch64-darwin)

### Directory Structure:
- `flake.nix` - Main flake with multi-channel inputs and outputs
- `hosts/*/` - Per-host NixOS/darwin system configurations  
- `home-manager/*/` - Per-host user environment configurations
- `home-manager/modules/` - Modular application configurations (40+ modules)
- `modules/` - Reusable NixOS system modules
- `secrets/` - SOPS-encrypted secrets (requires Yubikey)

## Development Commands

### Building and Switching Systems

#### NixOS (Linux):
```bash
# Local switch on current host (e.g., amd-pc)
sudo nixos-rebuild switch --flake ~/programming/flakm/nix_dots#amd-pc

# Remote build and switch (e.g., odroid)
nixos-rebuild switch --target-host flakm@odroid --use-remote-sudo --flake ~/programming/flakm/nix_dots#odroid
```

#### macOS (nix-darwin):
```bash
# Local switch on the Mac itself
sudo darwin-rebuild switch --flake ~/programming/flakm/nix_dots

# Remote deploy from amd-pc (requires SSH access + NOPASSWD sudo on target)
rsync -av --exclude='.git' --exclude='result' ~/programming/flakm/nix_dots/ flakm@<host>:~/programming/flakm/nix_dots/
ssh flakm@<host> "cd ~/programming/flakm/nix_dots && sudo darwin-rebuild switch --flake ."
```

#### Home-manager:
Home-manager is wired into the system module on all hosts — `nixos-rebuild switch` (Linux) or `darwin-rebuild switch` (macOS) rebuilds both system and user config. No separate `home-manager switch` needed.

**Note:** sops-nix HM module hangs under `sudo darwin-rebuild` on macOS. macOS hosts use the darwin system-level sops module to decrypt secrets (via SSH host key → age), then home-manager symlinks them from `/run/secrets/<name>` into `~`.

### Formatting and Linting:
```bash
# Format nix files
nix fmt
```

### Secrets Management:
```bash
# Edit encrypted secrets (requires yubikey)
nix-shell -p sops --run "sops secrets/secrets.yaml"
```

## Application Configuration

The setup uses a consistent set of applications across all hosts:

### Core Applications:
- **Window Management**: Hyprland (Linux), AeroSpace (macOS)
- **Terminal**: Kitty with tmux sessions
- **Editor**: Neovim with extensive LSP configuration
- **Shell**: zsh with atuin, zoxide, starship

### Key Configuration Files:
- `home-manager/modules/nvim/` - Neovim configuration with language-specific setups
- `home-manager/modules/tmux.nix` - tmux configuration
- `home-manager/modules/aerospace/` - macOS window manager config
- `home-manager/modules/hyprland.nix` - Linux window manager config

## Language-Specific Configurations:

The neovim configuration includes specialized setups for:
- Rust (`rust-config.lua`)
- Golang (`golang.lua`) 
- Python (`python.lua`)
- Scala/Metals (`metals-config.lua`)
- Node.js (`node.lua`)
- Databases (`databases.lua`)

## Architecture Patterns:

1. **Multi-platform**: Single flake supporting both NixOS and nix-darwin
2. **Per-host customization**: Each machine has its own configuration while sharing common modules
3. **Overlay system**: Uses multiple nixpkgs channels (stable, unstable, master) with overlays
4. **Secret management**: SOPS-nix integration for encrypted secrets
5. **Development environments**: Direnv integration for per-project development shells

## Auto-upgrade:
- **amd-pc**: daily at 02:00 (± 45min jitter), updates nixpkgs input
- **odroid**: daily at 03:00 (± 45min jitter), updates nixpkgs input
- **dell-xps**: daily at 02:00 (existing)
- Uses `system.autoUpgrade` with `allowReboot = false` (default)
- Home-manager is rebuilt as part of the system switch

## Special Features:
- ZFS replication setup on amd-pc and odroid
- Self-hosted services on odroid (Jellyfin, Nextcloud, Calibre, etc.)
- Yubikey/GPG integration for authentication
- Cross-platform keybinding consistency (important design principle)