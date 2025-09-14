# configuration in this file only applies to exampleHost host.
{ pkgs, pkgs-unstable, inputs, ... }: {


  # disabledModules = [ "services/web-apps/mealie.nix" ];

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
    ./paperless.nix
    #../../shared/k3s.nix
    #../../shared/wireguard.nix
    ../../shared/netdata.nix
    ./calibre.nix
    ./audiobookshelf.nix
    #../../shared/oom_killer.nix
    #./smokeping.nix

    #   "${pkgs-unstable.path}/nixos/modules/services/web-apps/mealie.nix"
       ./mealie.nix

    ../../shared/immich.nix

    #./zabbix.nix

    ./uptime-kuma.nix


    inputs.nixos-hardware.nixosModules.hardkernel-odroid-h3
  ];


  networking.hostName = "odroid";
  networking.domain = "house.flakm.com";


  users.users.flakm = {
    extraGroups = [ "deluge" "nextcloud" "sabnzbd" "sonarr" "jellyseerr" "flakm" ];
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

  environment.systemPackages = with pkgs; [
    home-manager
    tailscale

    wgnord
    wireguard-tools
    transmission
    unrar

    # for monitoring gpu (quicksync)
    intel-gpu-tools
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
