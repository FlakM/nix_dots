{ config, pkgs, ... }:
{
  # allow apps like teams etc...
  nixpkgs.config.allowUnfree = true;


  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # to mount ntfs external disk
  boot.supportedFilesystems = [ "ntfs" ];


  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # networking.hostName = "nixos"; # Define your hostname.
  networking.networkmanager.enable = true;
  networking.wireless.iwd.enable = true;
  networking.networkmanager.wifi.backend = "iwd";
  networking.firewall.checkReversePath = "loose";


  #services.xserver.videoDrivers = [ "nvidia" ];
  #hardware.opengl.enable = true;

  time.timeZone = "Europe/Warsaw";

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  #networking.useDHCP = false;
  #networking.interfaces.enp0s9.useDHCP = true;
  #networking.interfaces.eth0.useDHCP = true;

  services.undervolt = {
    enable = true;
    coreOffset = -150;
    gpuOffset = -100;
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the Plasma 5 Desktop Environment.
  services.xserver.displayManager.sddm.enable = true;
  services.xserver.desktopManager.plasma5.enable = true;

  # Configure keymap in X11
  # services.xserver.layout = "us";
  # services.xserver.xkbOptions = "eurosign:e";

  i18n.defaultLocale = "en_US.UTF-8";


  services.onedrive.enable = true;
  services.dbus.enable = true;

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = true;

  virtualisation.docker.enable = true;
  # otherwise docker swarm init won't work
  # https://docs.docker.com/config/containers/live-restore/
  virtualisation.docker.liveRestore = false;

  # enable the tailscale daemon; this will do a variety of tasks:
  # 1. create the TUN network device
  # 2. setup some IP routes to route through the TUN
  services.tailscale = { enable = true; };


  # Define a user account. Don't forget to set a password with ‘passwd’.
   users.users.flakm = {
     shell = pkgs.zsh;
     isNormalUser = true;
     extraGroups = [ "wheel" "docker" ]; # Enable ‘sudo’ for the user.
   };





  hardware.video.hidpi.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
   environment.systemPackages = with pkgs; [
     wget
     curl
     firefox
     google-chrome

     # editors & development
     jetbrains.idea-community

     dbeaver

     binutils 
     inotify-tools

     # vpn/rdp
     jq
     openconnect
     freerdp
     openvpn


     # media
     spotify
     gimp
     vlc
     signal-desktop

     # office
     thunderbird
     gpgme
     teams
     libreoffice
     keepassxc
     bitwarden
     bitwarden-cli
     dropbox-cli

     # spelling
     aspell
     aspellDicts.pl
     aspellDicts.en
     aspellDicts.en-computers

     tailscale
     element-desktop
     discord

     pkg-config
     openssl
   ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  services.udev.packages = [ pkgs.yubikey-personalization ];

# Depending on the details of your configuration, this section might be necessary or not;
# feel free to experiment
  services.pcscd.enable = true;
  environment.shellInit = ''
    export GPG_TTY="$(tty)"
    gpg-connect-agent /bye
    export SSH_AUTH_SOCK="/run/user/$UID/gnupg/S.gpg-agent.ssh"
  '';
  
  services.printing.enable = true;
  services.printing.drivers = [ pkgs.brlaser ];

  programs = {
    ssh.startAgent = false;

    gnupg = {
      dirmngr.enable = true;
      agent = {
      enable = true;
      enableSSHSupport = true;
      };
    };
    # This adds JAVA_HOME to the global environment, by sourcing the jdk's
    # setup-hook on shell init. It is equivalent to starting a shell through 
    # 'nix-shell -p jdk', or roughly the following system-wide configuration:
    # 
    #   environment.variables.JAVA_HOME = ${pkgs.jdk.home}/lib/openjdk;
    #   environment.systemPackages = [ pkgs.jdk ];
    java = {
      enable = true;
      package = pkgs.jdk8;
    };
    kdeconnect.enable = true;
  };


  # Let's open the UDP port with which the network is tunneled through
  networking.firewall = {
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ 41641 ];
  };

  systemd.user.services.dropbox = {
    description = "Dropbox";
    wantedBy = [ "graphical-session.target" ];
    environment = {
      QT_PLUGIN_PATH = "/run/current-system/sw/" + pkgs.qt5.qtbase.qtPluginPrefix;
      QML2_IMPORT_PATH = "/run/current-system/sw/" + pkgs.qt5.qtbase.qtQmlPrefix;
    };
    serviceConfig = {
      ExecStart = "${pkgs.dropbox.out}/bin/dropbox";
      ExecReload = "${pkgs.coreutils.out}/bin/kill -HUP $MAINPID";
      KillMode = "control-group"; # upstream recommends process
      Restart = "on-failure";
      PrivateTmp = true;
      ProtectSystem = "full";
      Nice = 10;
    };
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.05"; # Did you read the comment?



  fonts.fontDir.enable = true;
  fonts.fonts = with pkgs; [
    (nerdfonts.override { fonts = [ "RobotoMono" ]; })
  ];

}



