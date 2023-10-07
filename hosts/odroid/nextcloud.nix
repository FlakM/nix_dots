{ pkgs, config, ... }: {

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud27;
    hostName = "odroid.tailecbd4.ts.net";
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

  networking.firewall.allowedTCPPorts = [ 80 443 ];


  services.nginx = {
    enable = true;

    virtualHosts = {
      ${config.services.nextcloud.hostName} = {
        enableACME = false; # Since you're providing your own certs
        forceSSL = true;

        sslCertificate = "/var/secrets/certs/odroid.tailecbd4.ts.net.crt";
        sslCertificateKey = "/var/secrets/certs/odroid.tailecbd4.ts.net.key";
      };
    };
  };

}
