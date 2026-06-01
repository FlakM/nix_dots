{ pkgs, lib, ... }: {


  boot.zfs.forceImportRoot = false;

  # ZFS requires an LTS kernel. 26.05's default jumped to 6.18 which ZFS does
  # not support; pin to the 6.12 LTS (the kernel we already run).
  boot.kernelPackages = pkgs.linuxPackages_6_12;

  # rpool/nixos is the ZFS native-encryption root for / (and /home, /var/lib).
  # Under systemd stage-1 initrd (26.05 default) the default `true` scans key
  # status across all ~230 rpool datasets, which is slow enough that
  # sysroot.mount times out before the passphrase prompt shows. Scoping the
  # request to the single encryptionroot makes the prompt appear immediately;
  # loading that one key unlocks the whole inheriting subtree.
  boot.zfs.requestEncryptionCredentials = [ "rpool/nixos" ];

  programs.git.enable = true;


  programs = {

    gnupg = {
      dirmngr.enable = true;
      agent = {
        enable = true;
        enableSSHSupport = true;
      };
    };

    kdeconnect.enable = true;
  };


  security = {
    sudo.enable = true;
  };

  security.sudo.extraRules = [
    {
      users = [ "flakm" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ]; # "SETENV" # Adding the following could be a good idea
        }
      ];
    }
  ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };


  ## enable ZFS auto snapshot on datasets
  ## You need to set the auto snapshot property to "true"
  ## on datasets for this to work, such as
  # zfs set com.sun:auto-snapshot=true rpool/nixos/home
  services.zfs = {
    autoSnapshot = {
      enable = false;
      flags = "-k -p --utc";
      monthly = 48;
    };
  };


  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.flakm.extraGroups = lib.mkAfter [ "wheel" "pipewire" ];


  system.stateVersion = "23.12";


  nix.gc.dates = "weekly";

}
