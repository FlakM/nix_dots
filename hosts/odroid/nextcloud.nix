{ pkgs, config, ... }: {

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud27;
    hostName = "nextcloud.house.flakm.com";
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

    extraOptions = {
      mail_smtpmode = "sendmail";
      mail_sendmailmode = "pipe";
    };

    https = true;
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];


  services.nginx = {
    enable = true;

    virtualHosts = {
      ${config.services.nextcloud.hostName} = {
        enableACME = false; # Since you're providing your own certs
        forceSSL = true;

        sslCertificate = "/var/secrets/certs/house.crt";
        sslCertificateKey = "/var/secrets/certs/house.key";
        # redirect http to https
      };
    };
  };

}
