{ pkgs, config, ... }:
let
  webhookUrl = "http://192.168.0.249:8788/nextcloud-talk-webhook";
in {

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud33;
    hostName = "nextcloud.house.flakm.com";
    config.adminpassFile = "/etc/nextcloud-admin-pass";

    extraApps = {

      inherit (config.services.nextcloud.package.packages.apps) contacts calendar tasks previewgenerator notes memories cookbook mail bookmarks spreed;
      news = pkgs.fetchNextcloudApp {
        sha256 = "sha256-e2lledOH4LzB+/nWjL+wsCuJJTi50yNgPDnGVkl7FNk=";
        url = "https://github.com/nextcloud/news/releases/download/28.4.1/news.tar.gz";
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
      overwritehost = "nextcloud.house.flakm.com";
      overwriteprotocol = "https";
      "overwrite.cli.url" = "https://nextcloud.house.flakm.com";
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

  systemd.services.nextcloud-setup = {
    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
  };

  sops.secrets.nextcloud_talk_bot_secret = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = "nextcloud";
    group = "nextcloud";
  };

  # Idempotently register the OpenClaw bot in Nextcloud Talk.
  # Re-runs on each rebuild; occ talk:bot:install is a no-op if the bot URL already exists.
  systemd.services.nextcloud-talk-bot-register = {
    description = "Register OpenClaw bot in Nextcloud Talk";
    wantedBy = [ "multi-user.target" ];
    after = [ "nextcloud-setup.service" "sops-install-secrets.service" ];
    requires = [ "nextcloud-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "nextcloud";
    };
    script = ''
      SECRET=$(cat ${config.sops.secrets.nextcloud_talk_bot_secret.path})
      OCC="${config.services.nextcloud.occ}/bin/nextcloud-occ"
      if ! $OCC talk:bot:list --output json 2>/dev/null | grep -q '"name":"OpenClaw"'; then
        BOT_OUT=$($OCC talk:bot:install "OpenClaw" "$SECRET" "${webhookUrl}" "OpenClaw AI agent")
        BOT_ID=$(echo "$BOT_OUT" | grep '^ID:' | awk '{print $2}')
        [ -n "$BOT_ID" ] && $OCC talk:bot:state "$BOT_ID" 1
      fi
    '';
  };

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
  #systemd.services.nextcloud-pre-generate = {
  #  description = "Nextcloud OCC Preview Pre-generation";
  #  wantedBy = [ "multi-user.target" ];
  #  after = [ "network.target" ];
  #  serviceConfig = {
  #    ExecStart = "${config.services.nextcloud.occ}/bin/nextcloud-occ preview:pre-generate";
  #    User = "nextcloud";
  #    Group = "nextcloud";
  #  };
  #};

  #systemd.timers.nextcloudPreGenerateTimer = {
  #  wantedBy = [ "timers.target" ];
  #  partOf = [ "nextcloud-pre-generate.service" ];
  #  timerConfig = {
  #    OnCalendar = "daily";
  #    Persistent = true;
  #  };
  #};



}
