{ ... }: {

  # sudo zfs allow -d backup create,receive,destroy,rollback,snapshot,hold,release,mount tank/backup/
  # sudo zfs allow -d backup create,receive,destroy,rollback,snapshot,hold,release,mount rpool/nixos/var/lib/postgresql
  # sudo zfs allow -d backup create,receive,destroy,rollback,snapshot,hold,release,mount rpool/nixos/var/lib/paperless
  services.syncoid = {
    enable = true;
    user = "backup";

    commands."postgresql" = {
      source = "rpool/nixos/var/lib/postgresql";
      target = "tank/backup/postgresql";
    };

    commands."paperless-app" = {
      source = "rpool/nixos/var/lib/paperless/app";
      target = "tank/backup/paperless/app";
    };

    commands."paperless-ai" = {
      source = "rpool/nixos/var/lib/paperless/ai";
      target = "tank/backup/paperless/ai";
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

    datasets."rpool/nixos/var/lib/postgresql" = {
      useTemplate = [ "backup" ];
    };

    datasets."rpool/nixos/var/lib/paperless/app" = {
      useTemplate = [ "backup" ];
    };

    datasets."rpool/nixos/var/lib/paperless/ai" = {
      useTemplate = [ "backup" ];
    };
  };

}
