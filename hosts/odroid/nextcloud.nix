{ pkgs, config, ... }: {

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud28;
    hostName = "nextcloud.house.flakm.com";
    config.adminpassFile = "/etc/nextcloud-admin-pass";

    extraApps = with config.services.nextcloud.package.packages.apps; {
      inherit contacts calendar tasks;
    };
    extraAppsEnable = true;
    configureRedis = true;

    phpOptions = {
      #upload_max_filesize = "1G";
      #post_max_size = "1G";
    };

    extraOptions = {
      mail_smtpmode = "sendmail";
      mail_sendmailmode = "pipe";
    };

    https = true;

    database.createLocally = false;
    config = {
      dbtype = "pgsql";
      dbuser = "nextcloud";
      dbname = "nextcloud";
      dbhost = "/run/postgresql";
    };

  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
  services.postgresql.ensureUsers = [
    {
      name = "nextcloud";
      ensureDBOwnership = true;
    }
  ];

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

  programs.msmtp = {
    enable = true;
    setSendmail = true;
    extraConfig = ''
      defaults
      auth on
      tls on
      tls_trust_file /etc/ssl/certs/ca-certificates.crt
      logfile ~/.msmtp.log

      account default
      host smtp.fastmail.com
      port 587
      from nextcloud@flakm.com
      user me@flakm.com
      passwordeval "cat /var/secrets/fastmail-password" 
    '';
  };


}
