{ pkgs, ... }: {


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


  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
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
  users.users.flakm = {
    shell = pkgs.zsh;
    isNormalUser = true;
    extraGroups = [ "wheel" "pipewire" ]; # Enable ‘sudo’ for the user.
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDh6bzSNqVZ1Ba0Uyp/EqThvDdbaAjsJ4GvYN40f/p9Wl4LcW/MQP8EYLvBTqTluAwRXqFa6fVpa0Y9Hq4kyNG62HiMoQRjujt6d3b+GU/pq7NN8+Oed9rCF6TxhtLdcvJWHTbcq9qIGs2s3eYDlMy+9koTEJ7Jnux0eGxObUaGteQUS1cOZ5k9PQg+WX5ncWa3QvqJNxx446+OzVoHgzZytvXeJMg91gKN9wAhKgfibJ4SpQYDHYcTrOILm7DLVghrcU2aFqLKVTrHSWSugfLkqeorRadHckRDr2VUzm5eXjcs4ESjrG6viKMKmlF1wxHoBrtfKzJ1nR8TGWWeH9NwXJtQ+qRzAhnQaHZyCZ6q4HvPlxxXOmgE+JuU6BCt6YPXAmNEMdMhkqYis4xSzxwWHvko79NnKY72pOIS2GgS6Xon0OxLOJ0mb66yhhZB4hUBb02CpvCMlKSLtvnS+2IcSGeSQBnwBw/wgp1uhr9ieUO/wY5K78w2kYFhR6Iet55gutbikSqDgxzTmuX3Mkjq0L/MVUIRAdmOysrR2Lxlk692IrNYTtUflQLsSfzrp6VQIKPxjfrdFhHIfbPoUdfMf+H06tfwkGONgcej56/fDjFbaHouZ357wcuwDsuMGNRCdyW7QyBXF/Wi28nPq/KSeOdCy+q9KDuOYsX9n/5Rsw== flakm" # content of authorized_keys file
    ];
  };


  system.stateVersion = "23.12";


  nix.gc = {
    dates = "weekly";
  };

}
