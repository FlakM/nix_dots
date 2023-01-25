{ config, pkgs, ... }:
{
  # allow apps like teams etc...
  nixpkgs.config.allowUnfree = true;


  nix.settings.experimental-features = [ "nix-command" "flakes" ];


  # networking.hostName = "nixos"; # Define your hostname.
  networking.networkmanager.enable = true;
  networking.wireless.iwd.enable = true;
  networking.networkmanager.wifi.backend = "iwd";
  networking.firewall.checkReversePath = "loose";


  time.timeZone = "Europe/Warsaw";

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  #networking.useDHCP = false;
  #networking.interfaces.enp0s9.useDHCP = true;
  #networking.interfaces.eth0.useDHCP = true;

  # Enable the X11 windowing system.
  #services.xserver.enable = true;

  # Enable the Plasma 5 Desktop Environment.
  #services.xserver.displayManager.sddm.enable = true;
  #services.xserver.desktopManager.plasma5.enable = true;

  # Needed for sway
  security.polkit.enable = true;

  #services.xserver.displayManager.gdm = {
  #  enable = true;
  #  wayland = true;
  #};
  #services.xserver.libinput.enable = true;

  services.xserver.videoDrivers = [ "amdgpu" ];
  boot.initrd.kernelModules = [ "amdgpu" ];

  # Configure keymap in X11
  services.xserver.layout = "pl";
  # services.xserver.xkbOptions = "eurosign:e";
  i18n.defaultLocale = "en_US.UTF-8";


  services.fwupd.enable = true;


  services.dbus.enable = true;

  # Enable sound.
  #sound.enable = true;

  hardware = {
    opengl = {
      enable = true;
      #driSupport = true;
    };
    #video.hidpi.enable = true;
    bluetooth.enable = true;
  };

  # https://shen.hong.io/nixos-home-manager-wayland-sway/ 
  # https://github.com/emersion/xdg-desktop-portal-wlr/wiki/%22It-doesn't-work%22-Troubleshooting-Checklist
  xdg = {
    portal = {
      enable = true;
      extraPortals = with pkgs; [ 
        xdg-desktop-portal-wlr 
        #xdg-desktop-portal-gtk
      ];
      wlr.enable = true;
    };
  };
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    #jack.enable = true;
  };

  virtualisation.docker.enable = true;

  # enable the tailscale daemon; this will do a variety of tasks:
  # 1. create the TUN network device
  # 2. setup some IP routes to route through the TUN
  #services.tailscale = { enable = true; };


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

   security.pam.services.swaylock = {
     text = "auth include login";
   };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
   environment.systemPackages = with pkgs; [
     wayland
     swaylock
     swayidle
     wl-clipboard
     mako
     wofi
     waybar
     pipewire-media-session
     wlroots
     rtkit


     wget
     curl
     firefox-wayland
     #google-chrome
     chromium

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
     spotify
     gimp
     vlc
     signal-desktop

     # office
     thunderbird
     gpgme
     teams
     libreoffice
     bitwarden
     bitwarden-cli

     # spelling
     aspell
     aspellDicts.pl
     aspellDicts.en
     aspellDicts.en-computers

     tailscale
     element-desktop

     pkg-config
     openssl
     
     #libsForQt5.bismuth
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
  system.stateVersion = "22.11"; # Did you read the comment?



  fonts.fontDir.enable = true;
  fonts.fonts = with pkgs; [
    (nerdfonts.override { fonts = [ "RobotoMono" ]; })
  ];

}


