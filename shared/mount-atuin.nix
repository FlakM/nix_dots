{ pkgs, ... }: {
  systemd.services.mount-atuin = {
    description = "Mount Atuin ZFS Volume";
    wantedBy = [ "multi-user.target" ];
    after = [ "zfs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.util-linux}/bin/mount /dev/zvol/rpool/nixos/atuin /home/flakm/.local/share/atuin";
      User = "root";
    };
  };
}
