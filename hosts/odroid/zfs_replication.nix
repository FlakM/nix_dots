{ ... }: {

  # sudo zfs allow -d backup create,receive,destroy,rollback,snapshot,hold,release,mount tank/backup/postgres
  services.syncoid = {
    enable = true;
    user = "backup";

    commands."postgres" = {
      source = "rpool/nixos/var/lib/postgres";
      target = "tank/backup/postgres";
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

    datasets."rpool/nixos/var/lib/postgres" = {
      useTemplate = [ "backup" ];
    };
  };

}
