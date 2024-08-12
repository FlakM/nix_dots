{ pkgs, config, ... }: {

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud29;
    hostName = "nextcloud.house.flakm.com";
    config.adminpassFile = "/etc/nextcloud-admin-pass";

    extraApps = {

      inherit (config.services.nextcloud.package.packages.apps) contacts calendar tasks previewgenerator notes memories cookbook mail bookmarks;
      news = pkgs.fetchNextcloudApp {
        sha256 = "sha256-BbGzrOBDshZfiDhKUMiTXGnI7767hpCGsujMbPqmJyg=";
        url = "https://github.com/nextcloud/news/releases/download/25.0.0-alpha5/news.tar.gz";
        license = "gpl3";
      };

    };


    extraAppsEnable = true;
    configureRedis = true;

    phpOptions = {
      #upload_max_filesize = "1G";
      #post_max_size = "1G";
    };

    settings = {
      mail_smtpmode = "sendmail";
      mail_sendmailmode = "pipe";
      enabledPreviewProviders = [
        "OC\\Preview\\Movie"
        "OC\\Preview\\BMP"
        "OC\\Preview\\GIF"
        "OC\\Preview\\JPEG"
        "OC\\Preview\\Krita"
        "OC\\Preview\\MarkDown"
        "OC\\Preview\\MP3"
        "OC\\Preview\\OpenDocument"
        "OC\\Preview\\PNG"
        "OC\\Preview\\TXT"
        "OC\\Preview\\XBitmap"
        "OC\\Preview\\HEIC"
      ];
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
        useACMEHost = "house.flakm.com";
        forceSSL = true;
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


  # add systemd cron job to nextcloud-occ preview:pre-generate it should run at nigt
  systemd.services.nextcloud-pre-generate = {
    description = "Nextcloud OCC Preview Pre-generation";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${config.services.nextcloud.occ}/bin/nextcloud-occ preview:pre-generate";
      User = "nextcloud";
      Group = "nextcloud";
    };
  };

  systemd.timers.nextcloudPreGenerateTimer = {
    wantedBy = [ "timers.target" ];
    partOf = [ "nextcloud-pre-generate.service" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };



}
