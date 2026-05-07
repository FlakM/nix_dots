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

    ./modules/aerospace

    ./modules/aws.nix

    ./modules/k8s.nix

    #./modules/zed.nix

    ./modules/sql.nix

    ./modules/aerc.nix

    ./modules/ai.nix

    ./modules/peon-ping.nix
    ./modules/pw-play-wrapper.nix
  ];


  # Secrets are decrypted by sops-nix darwin module (system-level) using SSH host key.
  # Symlink them into the user's home directory.
  home.file.".npmrc".source = config.lib.file.mkOutOfStoreSymlink "/run/secrets/work_npmrc";
  home.file.".jfrog.env".source = config.lib.file.mkOutOfStoreSymlink "/run/secrets/jfrog_env";
  home.file.".github_personal_access_token".source =
    config.lib.file.mkOutOfStoreSymlink "/run/secrets/github_personal_access_token";


  home = {
    username = "flakm";
    homeDirectory = "/Users/flakm";
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
      ${pkgs.rsync}/bin/rsync $rsyncArgs "$apps_source/" "$app_target" 2>/dev/null || true
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

  # Ensure homebrew and cargo tools are in the PATH
  home.sessionPath = [
    "/opt/homebrew/bin"
    "${config.home.homeDirectory}/.cargo/bin"
  ];



  # ~/.gnupg/gpg-agent.conf
  xdg.configFile."/.gnupg/gpg-agent.conf".text = ''
    enable-ssh-support
    write-env-file
    use-standard-socket
    default-cache-ttl 600
    max-cache-ttl 7200
    pinentry-program ${pkgs.pinentry_mac}/bin/pinentry-mac
  '';

  # ~/.ssh/config
  xdg.configFile."/.ssh/config".text = ''
    Host github.com
        IdentitiesOnly yes
        IdentityFile ~/.ssh/id_rsa_yubikey.pub
        IdentityAgent ~/.gnupg/S.gpg-agent.ssh
  '';



  home.file.".zshrc_local".text = ''
    # docker is not installed by nix
    FPATH="$HOME/.docker/completions:$FPATH"
    autoload -Uz compinit
    compinit

    # Set correct SSH_AUTH_SOCK

    export PATH="$HOME/.cargo/bin:$PATH"
    export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
    export SHELL=/run/current-system/sw/bin/zsh
  '';



  programs.kitty.font.size = 15;


}
