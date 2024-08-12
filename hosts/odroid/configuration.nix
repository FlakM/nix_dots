# configuration in this file only applies to exampleHost host.
{ pkgs, ... }: {

  imports = [
    ./nextcloud.nix
    ./tandoor.nix
    ./postgres.nix
    ./jellyfin.nix
    ./deluged.nix
    ./samba.nix
    ./backupuser.nix
    ./zfs_replication.nix
    ./acme.nix
    ./adguard.nix
    #../../shared/k3s.nix
    #../../shared/wireguard.nix
    ../../shared/netdata.nix
    ./calibre.nix
    ./audiobookshelf.nix
    #../../shared/oom_killer.nix
  ];



  users.users.flakm = {
    extraGroups = [ "deluge" "nextcloud" ];
  };

  systemd.services.mount-atuin = {
    description = "Mount Atuin ZFS Volume";
    wantedBy = [ "multi-user.target" ];
    after = [ "zfs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.utillinux}/bin/mount /dev/zvol/rpool/nixos/atuin /home/flakm/.local/share/atuin";
      User = "root";
    };
  };


  programs.tmux = {
    enable = true;
    newSession = true;
    terminal = "tmux-direct";
  };
  services.emacs.enable = false;

  environment.systemPackages = with pkgs; [
    home-manager
    tailscale

    wgnord
    wireguard-tools
    transmission
    unrar
  ];

  # Let's open the UDP port with which the network is tunneled through
  networking.firewall = {
    allowedUDPPorts = [ 41641 ]; # tailscale
  };



  # enable the tailscale daemon; this will do a variety of tasks:
  # 1. create the TUN network device
  # 2. setup some IP routes to route through the TUN
  services.tailscale.enable = true;


  boot.zfs.extraPools = [ "tank" ];


  # workaround for openforify client
  environment.etc."ppp/options".text = "ipcp-accept-remote";
}
