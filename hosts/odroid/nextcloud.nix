{ pkgs, config, ... }: {

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud27;
    hostName = "odroid";
    config.adminpassFile = "/etc/nextcloud-admin-pass";

    extraApps = with config.services.nextcloud.package.packages.apps; {
      inherit news contacts calendar tasks;
    };
    extraAppsEnable = true;
    configureRedis = true;
    phpOptions = {
      upload_max_filesize = "1G";
      post_max_size = "1G";
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 ];

}
