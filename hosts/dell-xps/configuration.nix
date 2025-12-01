# configuration in this file only applies to amd-pc host.
{ pkgs, inputs, lib, nixos-hardware, pkgs-unstable, ... }:
let
  fenix = inputs.fenix.packages.${pkgs.stdenv.hostPlatform.system}.stable;
in

{
  imports = [
    inputs.nixos-hardware.nixosModules.dell-xps-15-9570-intel
    ../../shared/gpg.nix
  ];

  system.autoUpgrade = {
    enable = true;
    flake = inputs.self.outPath;
    flags = [
      "--update-input"
      "nixpkgs"
      "-L" # print build logs
    ];
    dates = "02:00";
    randomizedDelaySec = "45min";
  };

  #nixpkgs.config = {
  #  allowUnfree = true;
  #  allowUnfreePredicate = (_: true);
  #};



  #boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  #boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;
  programs.hyprland = {
    enable = true;
    systemd.setPath.enable = true;
  };

  # networking.hostName = "nixos"; # Define your hostname.
  networking.networkmanager.enable = lib.mkForce true;
  networking.wireless.iwd.enable = true;
  networking.networkmanager.wifi.backend = "iwd";
  networking.firewall.checkReversePath = "loose";

  networking.hostName = "dell-xps";

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
      configPackages = with pkgs; [
        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];
    };
  };

  security.rtkit.enable = true;

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
  };




  # Use xfce as desktop manager not DE
  #services.xserver = {
  #  enable = true;
  #  # left alt should switch to 3rd level
  #  # https://nixos.wiki/wiki/Keyboard_Layout_Customization
  #  xkb.options = "lv3:lalt_switch";
  # #   windowManager.i3.enable = true;
  #  
  #  desktopManager.plasma5.enable = true;
  #  displayManager.sddm.enable = true;
  #};

  services.displayManager.gdm = {
    enable = true;
    wayland = true;
  };

  services.libinput.enable = true;

  services.xserver = {
    enable = true; # might need it for xwayland
    xkb.options = "lv3:lalt_switch caps:swapescape";
  };

  #environment.sessionVariables.NIXOS_OZONE_WL = "1"; # This variable fixes electron apps in wayland

  boot.kernelModules = [ "kvm-intel" "tun" "virtio" ];

  # Configure keymap in X11
  #services.xserver.layout = "pl";
  # services.xserver.xkb.options = "eurosign:e";
  i18n.defaultLocale = "en_US.UTF-8";


  services.fwupd.enable = true;


  services.dbus.enable = true;


  hardware = {
    graphics = {
      enable = true;
    };
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
  };

  virtualisation.docker = {
    enable = true;
  };

  # enable the tailscale daemon; this will do a variety of tasks:
  # 1. create the TUN network device
  # 2. setup some IP routes to route through the TUN
  services.tailscale.enable = true;


  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.flakm.extraGroups = lib.mkAfter [
    "wheel"
    "docker"
    "audio"
    "networkmanager"
    "input"
    "video"
    "rtkit"
    "users"
    "dip"
    "bluetooth"
  ];

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
    adwaita-icon-theme
    gnome-themes-extra
    gsettings-desktop-schemas
    gruvbox-dark-gtk
    spotify

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
    pkgs-unstable.thunderbird
    #unstable.thunderbird
    gpgme
    libreoffice


    bitwarden-desktop
    bitwarden-cli

    # spelling
    aspell
    aspellDicts.pl
    aspellDicts.en
    aspellDicts.en-computers

    tailscale

    libsForQt5.qtstyleplugins
    adwaita-qt
    adwaita-qt6

    qt5.qtwayland
    qt6.qmake
    qt6.qtwayland


    wgnord
    bpftrace

    glibc

    kdePackages.dolphin
    lxqt.lxqt-policykit

    # fun
    spotify


    # network monitoring
    iftop


    (fenix.withComponents [
      "cargo"
      "clippy"
      "rust-src"
      "rustc"
      "rustfmt"
    ])
    fenix.rust-analyzer
  ];

  programs.wireshark = {
    enable = true;
    package = pkgs-unstable.wireshark;

  };

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
        enableSSHSupport = true;
        enableExtraSocket = true;
      };
    };
    kdeconnect.enable = true;
  };

  services.yubikey-agent.enable = true;




  # Let's open the UDP port with which the network is tunneled through
  networking.firewall = {
    allowedUDPPorts = [ 41641 ]; # tailscale
  };


  fonts.fontDir.enable = true;
  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "FiraCode" ]; })
  ];



  # workaround for openforify client
  environment.etc."ppp/options".text = "ipcp-accept-remote";

  # enable browsing samba shares
  services.gvfs = {
    enable = true;
    package = lib.mkForce pkgs.gnome.gvfs;
  };

  services.undervolt = {
    # it stopped working
    enable = false;
    coreOffset = -100;
    uncoreOffset = -100;
    gpuOffset = -100;
  };

}
