{ pkgs, lib, ... }: {

  users.users.backup = {
    isNormalUser = true;
    home = "/home/backup";
    description = "Backup User";
  };

  systemd.services.zfs-allow-rpool-nixos-home-programming = {
    description = "Ensure ZFS delegated permissions for syncoid backup user";
    wantedBy = [ "syncoid-odroid-programming.service" ];
    before = [ "syncoid-odroid-programming.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.zfs}/bin/zfs allow backup send,hold,snapshot,destroy,mount,create,receive,release,rollback rpool/nixos/home/programming
    '';
  };

  services.syncoid = {
    enable = true;
    user = "backup";
    #commonArgs = [ "--no-sync-snap" "--skip-parent" "--recursive" ];
    sshKey = "/var/lib/syncoid/backup/keys";

    commands."odroid-programming" = {
      source = "rpool/nixos/home/programming";
      # Use the LAN address: syncoid's ssh must bypass Tailscale SSH (which
      # enforces an interactive "check" on backup@odroid and breaks the job).
      target = "backup@192.168.0.102:tank/backup/programming";
      extraArgs = [ "--sshoption=StrictHostKeyChecking=off" ];
    };
  };

  # nixpkgs' syncoid hardening denies the @timer syscall group, but pv (which
  # syncoid spawns for the progress bar) uses setitimer; without it pv dies
  # with SIGSYS and breaks the `zfs send | pv | ...` pipe. Re-allow @timer.
  systemd.services."syncoid-odroid-programming".serviceConfig.SystemCallFilter =
    lib.mkForce [
      "@system-service"
      "~@aio"
      "~@chown"
      "~@keyring"
      "~@memlock"
      "~@privileged"
      "~@resources"
      "~@setuid"
    ];

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

    datasets."rpool/nixos/microvms/clawd" = {
      useTemplate = [ "backup" ];
    };
  };

}
