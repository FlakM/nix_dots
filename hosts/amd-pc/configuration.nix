# configuration in this file only applies to amd-pc host.

{ pkgs, inputs, lib, ... }: {

  imports = [
    ../../shared/wireguard.nix
    ../../shared/gpg.nix
    ../../shared/k3s.nix
    ./wildcard_cert.nix
  ];


  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = (_: true);
  };


  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];
    trusted-users = [
      "root"
      "flakm"
    ];
  };


  #boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  #boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;
  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
  };

  services.redis.servers."".enable = false;


  # networking.hostName = "nixos"; # Define your hostname.
  networking.networkmanager.enable = lib.mkForce true;
  networking.wireless.iwd.enable = true;
  networking.networkmanager.wifi.backend = "iwd";
  networking.firewall.checkReversePath = "loose";

  networking.hostName = "amd-pc";

  time.timeZone = "Europe/Warsaw";

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  #networking.useDHCP = false;
  #networking.interfaces.enp14s0.useDHCP = false;
  #networking.interfaces.eth0.useDHCP = true;

  programs.dconf.enable = true;

  xdg = {
    portal = {
      enable = true;
      xdgOpenUsePortal = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
      ];
    };
  };

  security.rtkit.enable = true;

  #hardware.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;
  };




  # Use xfce as desktop manager not DE
  #services.xserver = {
  #  enable = true;
  #  # left alt should switch to 3rd level
  #  # https://nixos.wiki/wiki/Keyboard_Layout_Customization
  #  xkbOptions = "lv3:lalt_switch";
  # #   windowManager.i3.enable = true;
  #  
  #  desktopManager.plasma5.enable = true;
  #  displayManager.sddm.enable = true;
  #};
  services.xserver = {
    enable = false;
    #displayManager.gdm.enable = true;
    #displayManager.gdm.wayland = true;
    #displayManager.sessionPackages = [ inputs.hyprland.hyprland ];
    libinput.enable = true;
    xkbOptions = "lv3:lalt_switch";
  };


  boot.initrd.kernelModules = [ "amdgpu" ];
  boot.kernelParams = [ "amdgpu.sg_display=0" ];

  boot.kernelModules = [ "kvm-amd" "tun" "virtio" ];

  # Configure keymap in X11
  #services.xserver.layout = "pl";
  # services.xserver.xkbOptions = "eurosign:e";
  i18n.defaultLocale = "en_US.UTF-8";


  services.fwupd.enable = true;


  services.dbus.enable = true;

  # Enable sound.
  sound.enable = true;
  services.blueman.enable = true;

  hardware = {
    opengl = {
      enable = true;
      driSupport = true;
    };
    bluetooth.enable = true;
  };

  virtualisation.docker.enable = true;

  # enable the tailscale daemon; this will do a variety of tasks:
  # 1. create the TUN network device
  # 2. setup some IP routes to route through the TUN
  services.tailscale.enable = true;


  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.flakm = {
    extraGroups = [ "wheel" "docker" "audio" "networkmanager" "input" "video" "rtkit" "users" "dip" "bluetooth" "pipewire" ]; # Enable ‘sudo’ for the user.
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDh6bzSNqVZ1Ba0Uyp/EqThvDdbaAjsJ4GvYN40f/p9Wl4LcW/MQP8EYLvBTqTluAwRXqFa6fVpa0Y9Hq4kyNG62HiMoQRjujt6d3b+GU/pq7NN8+Oed9rCF6TxhtLdcvJWHTbcq9qIGs2s3eYDlMy+9koTEJ7Jnux0eGxObUaGteQUS1cOZ5k9PQg+WX5ncWa3QvqJNxx446+OzVoHgzZytvXeJMg91gKN9wAhKgfibJ4SpQYDHYcTrOILm7DLVghrcU2aFqLKVTrHSWSugfLkqeorRadHckRDr2VUzm5eXjcs4ESjrG6viKMKmlF1wxHoBrtfKzJ1nR8TGWWeH9NwXJtQ+qRzAhnQaHZyCZ6q4HvPlxxXOmgE+JuU6BCt6YPXAmNEMdMhkqYis4xSzxwWHvko79NnKY72pOIS2GgS6Xon0OxLOJ0mb66yhhZB4hUBb02CpvCMlKSLtvnS+2IcSGeSQBnwBw/wgp1uhr9ieUO/wY5K78w2kYFhR6Iet55gutbikSqDgxzTmuX3Mkjq0L/MVUIRAdmOysrR2Lxlk692IrNYTtUflQLsSfzrp6VQIKPxjfrdFhHIfbPoUdfMf+H06tfwkGONgcej56/fDjFbaHouZ357wcuwDsuMGNRCdyW7QyBXF/Wi28nPq/KSeOdCy+q9KDuOYsX9n/5Rsw== flakm" # content of authorized_keys file
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
    qemu_full
    virt-manager
    quickemu
    glib

    xfce.xfce4-pulseaudio-plugin

    #    polkit_gnome
    gnome.adwaita-icon-theme
    gnome.gnome-themes-extra
    gsettings-desktop-schemas
    gruvbox-dark-gtk

    pavucontrol
    docker
    wget
    curl
    #google-chrome
    #firefox
    xdg-utils

    #chromium

    dbeaver

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
    inputs.nixpkgs-unstable.legacyPackages.${pkgs.system}.thunderbird
    #unstable.thunderbird
    gpgme
    libreoffice


    inputs.nixpkgs-unstable.legacyPackages.${pkgs.system}.bitwarden
    bitwarden-cli

    # spelling
    aspell
    aspellDicts.pl
    aspellDicts.en
    aspellDicts.en-computers

    tailscale

    pkg-config
    openssl

    qt6.full

    libsForQt5.qtstyleplugins
    adwaita-qt
    adwaita-qt6

    qt5.qtwayland
    qt6.qmake
    qt6.qtwayland


    wgnord
    qbittorrent
    bpftrace

    glibc

    xfce.thunar
    lxqt.lxqt-policykit
  ];


  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 8096 ];
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
        enable = true;
        pinentryFlavor = "tty";
        enableSSHSupport = true;
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
  system.stateVersion = "23.05"; # Did you read the comment?



  fonts.fontDir.enable = true;
  fonts.fonts = with pkgs; [
    (nerdfonts.override { fonts = [ "RobotoMono" ]; })
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
    package = lib.mkForce pkgs.gnome3.gvfs;
  };
}
