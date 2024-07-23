{ config, lib, pkgs, ... }:

{
  home.activation.linkSystemd =
    let
      inherit (lib) hm;
    in
    hm.dag.entryBefore [ "reloadSystemd" ] (
      ''
        find $HOME/.config/systemd/user/ \
          -type l \
          -exec bash -c "readlink {} | grep -q $HOME/.nix-profile/share/systemd/user/" \; \
          -delete

        find $HOME/.nix-profile/share/systemd/user/ \
          -type f -o -type l \
          -exec ln -s {} $HOME/.config/systemd/user/ \;
      ''
    );


  imports = [
    ./modules/home-manager.nix
    ./modules/common.nix
    ./modules/nvim/neovim.nix
    ./modules/rust.nix
    ./modules/tmux.nix
    ./modules/git.nix
    ./modules/gpg_home.nix
    ./modules/brother.nix

    ./modules/modivo.nix
    ./modules/yubikey.nix


    ./modules/communication.nix

    ./modules/sql.nix

    ./modules/firefox.nix
    ./modules/productivity.nix

    ./modules/hyprland.nix
    ./modules/neomutt.nix

    ./modules/atuin.nix
    ./modules/kitty.nix
    ./modules/starship.nix
    ./modules/zsh.nix

    ./modules/zellij.nix
  ];

  xsession.windowManager.i3.config.fonts.size = 18.0;
  programs.alacritty.settings.font.size = 11;

  xdg.enable = true;



  wayland.windowManager.hyprland.settings = {
    # Monitor settings
    monitor = [ ",highres,auto,1.5" "headless,highres,auto,1.6" ];
  };

  #config = {
  #  hyprland-local = {
  #    scale = 1.5;
  #  };
  #};

  gtk = {
    enable = true;
    theme = {
      package = pkgs.gnome.gnome-themes-extra;
      name = "Adwaita";
    };
    iconTheme = {
      package = pkgs.gnome.adwaita-icon-theme;
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


}
