# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Structure

This is a NixOS/nix-darwin configuration repository using flakes and home-manager for reproducible system configuration across multiple hosts (Linux and macOS).

### Key Directories:
- `flake.nix` - Main flake configuration defining system builds
- `home-manager/` - Home-manager configurations per host
- `hosts/` - Host-specific system configurations (dell-xps, amd-pc, odroid, air, work)
- `modules/` - Reusable NixOS modules
- `secrets/` - SOPS-encrypted secrets

### Host Architecture:
- **Linux hosts**: dell-xps, amd-pc, odroid (x86_64-linux)
- **macOS hosts**: air, work (aarch64-darwin using nix-darwin)

Each host has both system config in `hosts/` and user config in `home-manager/`.

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
# Switch darwin configuration
nix run nix-darwin -- switch --flake ~/programming/flakm/nix_dots
```

#### Home-manager:
```bash
# Local home-manager switch
home-manager --flake ~/programming/flakm/nix_dots#flakm@amd-pc switch

# Remote home-manager (build locally, copy, then switch)
home-manager --flake ~/programming/flakm/nix_dots#flakm@odroid build
nix copy --to ssh://flakm@odroid ./result
ssh flakm@odroid "home-manager --flake github:flakm/nix_dots#flakm@odroid switch"
```

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

## Special Features:

- ZFS replication setup on amd-pc and odroid
- Self-hosted services on odroid (Jellyfin, Nextcloud, Calibre, etc.)
- Yubikey/GPG integration for authentication
- Cross-platform keybinding consistency (important design principle)