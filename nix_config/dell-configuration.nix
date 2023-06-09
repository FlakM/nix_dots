{ pkgs, ... }:
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
    # it stopped working
    enable = false;
    coreOffset = -150;
    uncoreOffset = -150;
    gpuOffset = -100;
  };

  nixpkgs.config.pulseaudio = true;

  # Use xfce as desktop manager not DE
  services.xserver = {
    enable = true;
    # left alt should switch to 3rd level
    # https://nixos.wiki/wiki/Keyboard_Layout_Customization
    xkbOptions = "lv3:lalt_switch";
    desktopManager = {
      xterm.enable = false;
      xfce = {
        enable = true;
        noDesktop = true;
        enableXfwm = false;
      };
    };
    displayManager.defaultSession = "xfce";
    windowManager.i3.enable = true;
  };

  # Configure keymap in X11
  services.xserver.layout = "pl";
  # services.xserver.xkbOptions = "eurosign:e";
  i18n.defaultLocale = "en_US.UTF-8";

  services.dbus.enable = true;

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = true;

  virtualisation.docker.enable = true;

  # enable the tailscale daemon; this will do a variety of tasks:
  # 1. create the TUN network device
  # 2. setup some IP routes to route through the TUN
  services.tailscale.enable = true;


  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.flakm = {
    shell = pkgs.zsh;
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "audio" "networkmanager" "input" "video" "rtkit" "users" "dip" "bluetooth" ]; # Enable ‘sudo’ for the user.
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDh6bzSNqVZ1Ba0Uyp/EqThvDdbaAjsJ4GvYN40f/p9Wl4LcW/MQP8EYLvBTqTluAwRXqFa6fVpa0Y9Hq4kyNG62HiMoQRjujt6d3b+GU/pq7NN8+Oed9rCF6TxhtLdcvJWHTbcq9qIGs2s3eYDlMy+9koTEJ7Jnux0eGxObUaGteQUS1cOZ5k9PQg+WX5ncWa3QvqJNxx446+OzVoHgzZytvXeJMg91gKN9wAhKgfibJ4SpQYDHYcTrOILm7DLVghrcU2aFqLKVTrHSWSugfLkqeorRadHckRDr2VUzm5eXjcs4ESjrG6viKMKmlF1wxHoBrtfKzJ1nR8TGWWeH9NwXJtQ+qRzAhnQaHZyCZ6q4HvPlxxXOmgE+JuU6BCt6YPXAmNEMdMhkqYis4xSzxwWHvko79NnKY72pOIS2GgS6Xon0OxLOJ0mb66yhhZB4hUBb02CpvCMlKSLtvnS+2IcSGeSQBnwBw/wgp1uhr9ieUO/wY5K78w2kYFhR6Iet55gutbikSqDgxzTmuX3Mkjq0L/MVUIRAdmOysrR2Lxlk692IrNYTtUflQLsSfzrp6VQIKPxjfrdFhHIfbPoUdfMf+H06tfwkGONgcej56/fDjFbaHouZ357wcuwDsuMGNRCdyW7QyBXF/Wi28nPq/KSeOdCy+q9KDuOYsX9n/5Rsw== flakm" # content of authorized_keys file
      # note: ssh-copy-id will add user@clientmachine after the public key
      # but we can remove the "@clientmachine" part
    ];
  };




  environment.pathsToLink = [ "/share/zsh" ];

  hardware.video.hidpi.enable = true;

  hardware.bluetooth.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    xfce.xfce4-pulseaudio-plugin

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

    libsForQt5.bismuth
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

  services.openssh = {
    enable = false;
    # require public key authentication for better security
    passwordAuthentication = false;
    kbdInteractiveAuthentication = false;
    #permitRootLogin = "yes";
  };



  # Let's open the UDP port with which the network is tunneled through
  networking.firewall = {
    #allowedTCPPorts = [ 22 ];
    allowedUDPPorts = [ 41641 ];
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

}



