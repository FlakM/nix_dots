{ pkgs, config, ... }:

{

  services.immich = {
    enable = true;
    redis.enable = true;
    accelerationDevices = [ "/dev/dri/renderD128" ]; # adjust if your VAAPI device differs
    settings = {
      server.externalDomain = "https://immich.house.flakm.com";
      ffmpeg = {
        accel = "vaapi"; # valid options: vaapi, qsv, nvenc, rkmpp, disabled
        accelDecode = true;
        preferredHwDevice = "auto";
      };
    };
  };


  services.nginx = {
    enable = true;
    virtualHosts = {
      "immich.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        forceSSL = true;
        extraConfig = ''
          client_max_body_size 50000M;

          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;

          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          proxy_redirect off;

          proxy_read_timeout 600s;
          proxy_send_timeout 600s;
          send_timeout 600s;
        '';
        locations."/" = {
          extraConfig = ''
            proxy_pass http://[::1]:${toString config.services.immich.port};
          '';
        };
      };
    };
  };

}
