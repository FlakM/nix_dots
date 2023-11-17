{ ... }: {

  # one time setup of zfs permissions
  # sudo zfs allow backup snapshot,send,receive tank/backup
  users.users.backup = {
    isNormalUser = true;
    home = "/home/backup";
    description = "Backup User";
  };

  services.syncoid = {
    enable = true;
    user = "backup";
    #commonArgs = [ "--no-sync-snap" "--skip-parent" "--recursive" ];
    sshKey = "/var/lib/syncoid/backup/keys";

    commands."odroid-programming" = {
      source = "rpool/nixos/home/programming";
      target = "backup@odroid:tank/backup/programming";
      extraArgs = [ "--sshoption=StrictHostKeyChecking=off" ];
    };
  };

  services.sanoid = {
    enable = true;
    templates.backup = {
      hourly = 36;
      daily = 30;
      monthly = 3;
      autoprune = true;
      autosnap = true;
    };

    datasets."rpool/nixos/home/programming" = {
      useTemplate = [ "backup" ];
    };
  };

}
