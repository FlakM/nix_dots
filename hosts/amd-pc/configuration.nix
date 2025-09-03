# configuration in this file only applies to amd-pc host.

{ pkgs, inputs, lib, pkgs-unstable, pkgs-master, config, ... }:

let
  fenix = inputs.fenix.packages.${pkgs.system}.stable;
in

{
  imports = [
    ../../shared/wireguard.nix
    ../../shared/gpg.nix
    #../../shared/k3s/server.nix
    ../../shared/syncthing.nix
    ./zfs_replication.nix
    ./postgres.nix
    ./grafana.nix
    ./performance.nix
    #./clickhouse.nix
  ];

  nix.package = pkgs.nixVersions.latest;

  systemd.services.mount-atuin = {
    description = "Mount Atuin ZFS Volume";
    wantedBy = [ "multi-user.target" ];
    after = [ "zfs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.utillinux}/bin/mount /dev/zvol/rpool/nixos/atuin /home/flakm/.local/share/atuin";
      User = "root";
    };
  };


  services.ollama = {
    enable = true;
    package = pkgs-unstable.ollama;
  };

  networking.extraHosts =
    ''
      127.0.0.1 modivo.local
      fdf3:e1c5:2572::f:9:1 eobuwie-db.local
    '';


  #boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  #boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;
  programs.hyprland = {
    enable = true;
    systemd.setPath.enable = true;
    withUWSM = true;
  };

  services.redis.servers."".enable = false;


  # networking.hostName = "nixos"; # Define your hostname.
  networking.networkmanager.enable = lib.mkForce false;

  networking.hostName = "amd-pc";

  time.timeZone = "Europe/Warsaw";

  # Sops secrets configuration
  sops.defaultSopsFile = ../../secrets/secrets.yaml;
  sops.secrets = {
    coralogix_blog_send_key = {
      path = "/var/secrets/coralogix_send_key";
      mode = "0440";
      owner = "flakm";
      group = "users";
    };
  };

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  #networking.useDHCP = false;
  #networking.interfaces.enp14s0.useDHCP = false;
  #networking.interfaces.eth0.useDHCP = true;

  programs.dconf.enable = true;


  security.rtkit.enable = true;
  security.pam.services.hyprlock = { }; # allow hyprlock to authenticate

  services.blueman.enable = true;

  hardware.pulseaudio.enable = false;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    audio.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
    jack.enable = true;

    # Configure default HDMI audio for LG monitor
    wireplumber.configPackages = [
      (pkgs.writeTextDir "share/wireplumber/main.lua.d/51-hdmi-audio.lua" ''
        -- Force HDMI card profile to be active
        rule = {
          matches = {
            {
              { "device.name", "equals", "alsa_card.pci-0000_18_00.1" },
            },
          },
          apply_properties = {
            ["device.profile"] = "output:hdmi-stereo-extra2",
            ["api.acp.auto-profile"] = "false",
          },
        }
        table.insert(alsa_monitor.rules, rule)

        -- Set HDMI as default sink with high priority
        default_sink_rule = {
          matches = {
            {
              { "node.name", "equals", "alsa_output.pci-0000_18_00.1.hdmi-stereo-extra2" },
            },
          },
          apply_properties = {
            ["node.priority.driver"] = 2000,
            ["node.priority.session"] = 2000,
          },
        }
        table.insert(alsa_monitor.rules, default_sink_rule)
      '')
    ];
  };

  services.libinput.enable = true;

  services.xserver.displayManager.gdm = {
    enable = true;
    wayland = true;
  };


  services.xserver = {
    enable = false; # might need it for xwayland
    #xkb.options = "lv3:lalt_switch caps:swapescape";
    xkb.options = "caps:swapescape";
  };



  # Configure keymap in X11
  #services.xserver.layout = "pl";
  # services.xserver.xkb.options = "eurosign:e";
  i18n.defaultLocale = "en_US.UTF-8";


  services.fwupd.enable = true;
  services.dbus.enable = true;


  boot.kernelParams = [
    "video=DP-1:5120x1440@144"
  ];

  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
      #package = pkgs-unstable.mesa;
      #package32 = pkgs-unstable.pkgsi686Linux.mesa;
    };
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
  };

  virtualisation.podman = {
    enable = false;
    #   defaultNetwork.settings.dns_enabled = true;
  };

  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      bip = "172.26.0.1/16";
      default-address-pools = [
        {
          base = "172.26.0.1/16";
          size = 24;
        }
      ];
    };
  };

  # enable the tailscale daemon; this will do a variety of tasks:
  # 1. create the TUN network device
  # 2. setup some IP routes to route through the TUN
  services.tailscale.enable = false;

  users.groups.plugdev = { };


  services.flatpak.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.flakm = {
    extraGroups = [ "wheel" "docker" "audio" "input" "video" "users" "dip" "bluetooth" "plugdev" ]; # Enable ‘sudo’ for the user.
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDh6bzSNqVZ1Ba0Uyp/EqThvDdbaAjsJ4GvYN40f/p9Wl4LcW/MQP8EYLvBTqTluAwRXqFa6fVpa0Y9Hq4kyNG62HiMoQRjujt6d3b+GU/pq7NN8+Oed9rCF6TxhtLdcvJWHTbcq9qIGs2s3eYDlMy+9koTEJ7Jnux0eGxObUaGteQUS1cOZ5k9PQg+WX5ncWa3QvqJNxx446+OzVoHgzZytvXeJMg91gKN9wAhKgfibJ4SpQYDHYcTrOILm7DLVghrcU2aFqLKVTrHSWSugfLkqeorRadHckRDr2VUzm5eXjcs4ESjrG6viKMKmlF1wxHoBrtfKzJ1nR8TGWWeH9NwXJtQ+qRzAhnQaHZyCZ6q4HvPlxxXOmgE+JuU6BCt6YPXAmNEMdMhkqYis4xSzxwWHvko79NnKY72pOIS2GgS6Xon0OxLOJ0mb66yhhZB4hUBb02CpvCMlKSLtvnS+2IcSGeSQBnwBw/wgp1uhr9ieUO/wY5K78w2kYFhR6Iet55gutbikSqDgxzTmuX3Mkjq0L/MVUIRAdmOysrR2Lxlk692IrNYTtUflQLsSfzrp6VQIKPxjfrdFhHIfbPoUdfMf+H06tfwkGONgcej56/fDjFbaHouZ357wcuwDsuMGNRCdyW7QyBXF/Wi28nPq/KSeOdCy+q9KDuOYsX9n/5Rsw== flakm" # content of authorized_keys file

      # teprorary keys for pikvm and odroid if the tailscale is not working on amd
      # password is stored in the password manager
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINJ/re3ma3iPQIXyixzDjaQ7Jf7+M/byFMoCHmH9I3pj root@pikvm"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDVvK18r4EdYJOW8Ml9Dp0y0TDqnVaTQswA8AdNmHyde flakm@odroid"
      # note: ssh-copy-id will add user@clientmachine after the public key
      # but we can remove the "@clientmachine" part
    ];
  };

  environment.pathsToLink = [ "/share/zsh" ];

  security.polkit.enable = true;

  security.pam.services.swaylock = {
    text = "auth include login";
  };


  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    nix-index
    amdgpu_top
    #okular

    qemu_full
    virt-manager
    quickemu
    glib
    linuxHeaders

    xfce.xfce4-pulseaudio-plugin

    adwaita-icon-theme
    gnome-themes-extra
    gsettings-desktop-schemas
    gruvbox-dark-gtk

    pavucontrol
    docker
    wget
    curl
    xdg-utils

    #chromium
    binutils
    inotify-tools
    lm_sensors

    # vpn/rdp
    jq
    openconnect
    freerdp
    openvpn


    # media
    gimp
    vlc

    # office
    thunderbird
    gpgme
    libreoffice


    bitwarden
    bitwarden-cli

    # spelling
    aspell
    aspellDicts.pl
    aspellDicts.en
    aspellDicts.en-computers

    qt6.full

    libsForQt5.qtstyleplugins
    adwaita-qt
    adwaita-qt6

    qt5.qtwayland
    qt6.qmake
    qt6.qtwayland


    wgnord

    glibc

    kdePackages.dolphin
    lxqt.lxqt-policykit

    # fun
    spotify


    # network monitoring
    iftop


    rustup
    #(fenix.withComponents [
    #  "cargo"
    #  "clippy"
    #  "rust-src"
    #  "rustc"
    #  "rustfmt"
    #  "rust-analyzer"
    #])

    #(fenix.packages.targets.thumbv6m-unknown-unknown.withComponents [
    #  "rust-src"
    #  "rustc"
    #])


    #fenix.rust-analyzer

    calibre

    nextcloud-client
    libation

    mariadb

    flatpak

    ddcutil

  ];


  boot.extraModulePackages = [ pkgs.bcc ];

  programs.wireshark = {
    enable = true;
    package = pkgs-unstable.wireshark;
  };

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  services.openssh = {
    settings = {
      StreamLocalBindUnlink = "yes";
    };
  };

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 8096 8000 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;


  # Depending on the details of your configuration, this section might be necessary or not;
  # feel free to experiment
  #services.pcscd.enable = true;
  #environment.shellInit = ''
  #  export GPG_TTY="$(tty)"
  #  gpg-connect-agent /bye
  #  export SSH_AUTH_SOCK="/run/user/$UID/gnupg/S.gpg-agent.ssh"
  #'';

  services.printing.enable = true;
  services.printing.drivers = [ pkgs.brlaser ];

  programs = {

    gnupg = {
      dirmngr.enable = true;
      agent = {
        enableSSHSupport = true;
        pinentryPackage = pkgs.pinentry-tty;
      };
    };
    kdeconnect.enable = true;
  };




  # Let's open the UDP port with which the network is tunneled through
  networking.firewall = {
    allowedUDPPorts = [ 41641 ]; # tailscale
  };




  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.12"; # Did you read the comment?



  fonts.fontDir.enable = true;
  fonts.packages =  [
    pkgs.nerd-fonts.fira-code
  ];


  services.minio = {
    enable = true;
    region = "us-east-1";
  };



  # workaround for openforify client
  environment.etc."ppp/options".text = "ipcp-accept-remote";

  # enable browsing samba shares
  services.gvfs = {
    enable = true;
    package = lib.mkForce pkgs.gnome.gvfs;
  };

  services.udev.extraRules = ''
    KERNEL=="i2c-[0-9]*", GROUP="users", MODE="0660"
  '';

  services.udev.packages = [
    (pkgs.writeTextFile {
      name = "69-probe-rs.rules";
      text = builtins.readFile ./69-probe-rs.rules;
      destination = "/etc/udev/rules.d/69-probe-rs.rules";
    })
  ];


  # enable gnome keyring for nextcloud-client to store the password
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.gdm.enableGnomeKeyring = true;

  security.pam.services.hyprlock = {};
}
