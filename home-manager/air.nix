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
      # nix wrappers replace signed binaries, breaking the .app code signatures;
      # re-sign with ad-hoc so macOS treats them as launchable apps
      for app in "$app_target"/*.app; do
        [ -d "$app" ] || continue
        chmod -R u+w "$app" || true
        /usr/bin/codesign --force --deep --sign - "$app" 2>/dev/null || true
      done
    '';
  };


}
