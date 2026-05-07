{ config, lib, pkgs, ... }:

{
  imports = [
    ./modules/home-manager.nix
    ./modules/common.nix

    # todo uncomment when i fix it
    ./modules/nvim/neovim.nix
    ./modules/rust.nix
    ./modules/tmux.nix
    ./modules/git.nix
    ./modules/gpg_home.nix

    ./modules/productivity.nix

    ./modules/yubikey.nix

    ./modules/atuin.nix
    ./modules/kitty.nix
    ./modules/starship.nix
    ./modules/zsh.nix

    ./modules/scala.nix
    ./modules/pw-play-wrapper.nix
  ];


  home = {
    username = "maciek";
    homeDirectory = "/Users/maciek";
    stateVersion = "24.05";
  };


  # Disable the default ~/Applications/Home Manager Apps symlink directory —
  # Launch Services follows the symlinks into /nix/store and registers the
  # store paths, producing duplicate launcher entries that compete with the
  # signed trampolines below. The trampolines fully replace it.
  targets.darwin.linkApps.enable = false;

  # copied from https://github.com/LnL7/nix-darwin/issues/214#issuecomment-2050027696
  # to enable trampolines for home-manager
  home.activation = {
    rsync-home-manager-applications = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      rsyncArgs="--archive --checksum --chmod=-w --copy-unsafe-links --delete"
      apps_source="$genProfilePath/home-path/Applications"
      moniker="Home Manager Trampolines"
      app_target_base="${config.home.homeDirectory}/Applications"
      app_target="$app_target_base/$moniker"
      mkdir -p "$app_target"
      ${pkgs.rsync}/bin/rsync $rsyncArgs "$apps_source/" "$app_target" || true
      # Nix wraps binaries inside .app/Contents/MacOS, replacing the originally
      # signed executable and breaking the bundle's resource seal. Without a valid
      # signature macOS won't surface the app in Spotlight. Re-sign with ad-hoc.
      for app in "$app_target"/*.app; do
        [ -d "$app" ] || continue
        if /usr/bin/codesign -v "$app" >/dev/null 2>&1; then
          continue
        fi
        chmod -R u+w "$app" 2>/dev/null || true
        /usr/bin/codesign --force --deep --sign - "$app" || true
      done
    '';
  };


}
