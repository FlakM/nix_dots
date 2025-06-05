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

  # Ensure cargo tools are in the PATH
  home.sessionPath = [
    "${config.home.homeDirectory}/.cargo/bin"
  ];

  imports = [
    ./modules/home-manager.nix
    ./modules/common.nix
    ./modules/nvim/neovim.nix
    ./modules/rust.nix
    ./modules/tmux.nix
    ./modules/git.nix
    ./modules/gpg_home.nix
    ./modules/brother.nix

    ./modules/yubikey.nix


    ./modules/communication.nix

    ./modules/sql.nix

    ./modules/firefox.nix
    ./modules/productivity.nix

    ./modules/hyprland.nix
    #./modules/neomutt.nix

    ./modules/atuin.nix
    ./modules/kitty.nix
    ./modules/starship.nix
    ./modules/zsh.nix

    ./modules/zellij.nix
    ./modules/jira_cli.nix

    ./modules/scala.nix

    ./modules/aws.nix
    #./modules/ghostty.nix
  ];

  xdg.enable = true;



  wayland.windowManager.hyprland.settings = {
    # Monitor settings
    monitor = [ ",highres,auto,1.066667" "headless,highres,auto,1.6" ];
    master = {
      orientation = "center";
      slave_count_for_center_master = 0;
      mfact = 0.55;
    };

    general = {
      layout = "master";
    };
  };

  #config = {
  #  hyprland-local = {
  #    scale = 1.5;
  #  };
  #};

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
    write-env-file
    use-standard-socket
    default-cache-ttl 600
    max-cache-ttl 7200
    pinentry-program ${pkgs.pinentry-tty}/bin/pinentry-tty
  '';


  home.packages = with pkgs; [
    openrgb-with-all-plugins
  ];



}
