{ config, lib, pkgs, ... }:

{
  # Ensure cargo and go tools are in the PATH
  home.sessionPath = [
    "${config.home.homeDirectory}/.cargo/bin"
    "${config.home.homeDirectory}/go/bin"
    "/usr/local/bin"
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
    ./modules/media.nix

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

    ./modules/ai.nix

    ./modules/k8s.nix
    ./modules/front.nix
  ];

  xdg.enable = true;



  wayland.windowManager.hyprland.settings = {
    # Monitor settings
    monitor = [ "DP-1,5120x1440@144,0x0,1.0" ];
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
      name = "FiraCode";
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
      size = 48;
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

  home.file.".zshrc_local".text = ''
    # Ensure SSH uses gpg-agent socket (YubiKey)
    export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
  '';


  home.packages = with pkgs; [
    pritunl-client
  ];


  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFile = ../secrets/secrets.yaml;

    secrets = {
      "work_npmrc" = {
        path = "${config.home.homeDirectory}/.npmrc";
      };

      "dbs" = {
        sopsFile = ../secrets/dbs.yaml;
        path = "${config.home.homeDirectory}/.dbs.lua";
      };

      "jfrog_env" = {
        path = "${config.home.homeDirectory}/.jfrog.env";
      };


      "neomutt_flakm" = {
        path = "${config.home.homeDirectory}/.neomutt_flakm";
      };

      "neomutt_gmail" = {
        path = "${config.home.homeDirectory}/.neomutt_gmail";
      };
    };
  };



}
