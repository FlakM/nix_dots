{ pkgs, config, ... }: {

  services.deluge = {
    enable = true;
    web = {
      enable = true;
      openFirewall = true;
      port = 8112;
    };
    declarative = true;
    config = {
      download_location = "/var/lib/deluge/downloads";
      #share_ratio_limit = "2.0";
      allow_remote = true;
    };
    authFile = "/var/secrets/deluge/auth";
    openFirewall = true;
  };

  systemd.services.deluged.serviceConfig = {
    NetworkNamespacePath = "/var/run/netns/nordvpn_ns";
  };

  systemd.services.delugeweb.serviceConfig = {
    NetworkNamespacePath = "/var/run/netns/nordvpn_ns";
  };

}
