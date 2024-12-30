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
  ];


  sops = {
    # It's also possible to use a ssh key, but only when it has no password:
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    defaultSopsFile = ../secrets/secrets.yaml;

    secrets = {
      "work_npmrc" = {
        path = "${config.home.homeDirectory}/.npmrc";
      };
    };
  };


  home = {
    username = "flakm";
    homeDirectory = "/Users/flakm";
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
    '';
  };

  # Ensure homebrew and cargo tools are in the PATH
  home.sessionPath = [
    "/opt/homebrew/bin/"
    "~/.cargo/bin"
  ];



  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

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
