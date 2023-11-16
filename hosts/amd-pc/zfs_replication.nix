{ ... }: {
  services.syncoid = {
    enable = true;
    user = "backupuser";
    commonArgs = [ "--no-sync-snap" "--skip-parent" "--recursive" ];
    sshKey = "/var/lib/syncoid/backup/keys";

    commands."odroid-programming" = {
      source = "rpool/nixos/home/programming";
      target = "backupuser@odroid:tank/backup/programming";
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
