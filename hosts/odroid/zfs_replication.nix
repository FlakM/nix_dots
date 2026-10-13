{ pkgs, ... }: {

  # sudo zfs allow -d backup create,receive,destroy,rollback,snapshot,hold,release,mount rpool/nixos/var/lib/postgresql
  # sudo zfs allow -d backup create,receive,destroy,rollback,snapshot,hold,release,mount rpool/nixos/var/lib/paperless
  # sudo zfs allow -d backup create,receive,destroy,rollback,snapshot,hold,release,mount tank/data/media/audiobookshelf

  # The syncoid module unallows the shared parent tank/backup on every odroid
  # job stop, which strips the receive delegation amd-pc's push into
  # tank/backup/programming relies on. Grant it on the dataset itself so it
  # survives the parent unallow.
  systemd.services.zfs-allow-tank-backup-programming = {
    description = "Ensure ZFS receive delegation for amd-pc syncoid target";
    wantedBy = [ "multi-user.target" ];
    after = [ "zfs-import.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.zfs}/bin/zfs allow backup change-key,compression,create,mount,mountpoint,receive,rollback tank/backup/programming
    '';
  };

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

    datasets."tank/data/media/audiobookshelf" = {
      useTemplate = [ "backup" ];
    };

    datasets."tank/syncthing-encrypted" = {
      useTemplate = [ "backup" ];
    };
  };

}
