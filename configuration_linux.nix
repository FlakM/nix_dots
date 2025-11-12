{ pkgs, lib, ... }: {


  boot.zfs.forceImportRoot = false;

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
