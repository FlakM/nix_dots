{ pkgs, config, ... }: {

  services.deluge = {
    enable = true;
    web = {
      enable = true;
      openFirewall = true;
    };
    declarative = true;
    config = {
      download_location = "/var/lib/deluge/downloads";
      max_upload_speed = "1000.0";
      #share_ratio_limit = "2.0";
      allow_remote = true;
      daemon_port = 58846;
      listen_ports = [ 6881 6889 ];
    };
    authFile = "/var/secrets/deluge/auth";
  };

  systemd.services.deluged.serviceConfig = {
    NetworkNamespacePath = "/var/run/netns/nordvpn_ns";
  };

}
