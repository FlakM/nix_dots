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

  networking.firewall.allowedTCPPorts = [ 80 443 ];


  services.nginx = {
    enable = true;

    virtualHosts = {
      ${config.services.nextcloud.hostName} = {
        enableACME = false; # Since you're providing your own certs
        forceSSL = true;

        sslCertificate = "/var/secrets/certs/odroid.tailecbd4.ts.net.crt";
        sslCertificateKey = "/var/secrets/certs/odroid.tailecbd4.ts.net.key";

        locations = {
          "/" = {
            proxyPass = "http://127.0.0.1:45854"; 
            proxySetHeaders = {
              Host = "$host";
              X-Real-IP = "$remote_addr";
              X-Forwarded-For = "$proxy_add_x_forwarded_for";
              X-Forwarded-Proto = "$scheme";
            };
          };
        };
      };
    };
  };

  # You might also want to ensure that the certificates are readable by the nginx process:
  systemd.tmpfiles.rules = [
    "a /var/secrets/certs/odroid.tailecbd4.ts.net.crt 0644 root root"
    "a /var/secrets/certs/odroid.tailecbd4.ts.net.key 0640 root root"
  ];

}
