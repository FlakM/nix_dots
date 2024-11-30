{ config, lib, pkgs, ... }:

{
  imports = [
    ./modules/home-manager.nix
    ./modules/common.nix
    ./modules/nvim/neovim.nix
    ./modules/rust.nix
    ./modules/zsh.nix
    ./modules/tmux.nix
    ./modules/git.nix
    ./modules/gpg_home.nix
    ./modules/brother.nix

    ./modules/modivo.nix
    ./modules/yubikey.nix


    ./modules/communication.nix


    ./modules/firefox.nix
    ./modules/productivity.nix

    ./modules/neomutt.nix
    ./modules/hyprland.nix

    ./modules/atuin.nix
    ./modules/kitty.nix
    ./modules/starship.nix
  ];


  wayland.windowManager.hyprland.settings = {
    # Monitor settings
    monitor = ",highres,auto,2.0";
  };

  xdg.enable = true;

  gtk = {
    enable = true;
    theme = {
      package = pkgs.gnome-themes-extra;
      name = "Adwaita";
    };
    iconTheme = {
      package = pkgs.adwaita-icon-theme;
      name = "Adwaita";
    };
    font = {
      name = "Sans";
      size = 11;
    };
  };

  home = {
    username = "flakm";
    homeDirectory = "/home/flakm";
    pointerCursor = {
      gtk.enable = true;
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Amber";
      size = 24;
    };
    stateVersion = "23.05";
  };

  # ~/.gnupg/gpg-agent.conf
  xdg.configFile."/.gnupg/gpg-agent.conf".text = ''
    enable-ssh-support
    pinentry-program ${pkgs.pinentry-qt}/bin/pinentry
    extra-socket /run/user/1000/gnupg/S.gpg-agent.extra
  '';

  # ~/.ssh/config
  xdg.configFile."/.ssh/config".text = ''
    Host github.com
        IdentitiesOnly yes
        IdentityFile ~/.ssh/id_rsa_yubikey.pub

    Host amd-pc
        ForwardAgent yes
        RemoteForward /run/user/1000/gnupg/S.gpg-agent /run/user/1000/gnupg/S.gpg-agent.extra
        User flakm
  '';


}
