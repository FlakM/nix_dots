{ pkgs, ... }: {

  services.audiobookshelf = {
    enable = true;
    openFirewall = true;
  };

  services.nginx = {
    enable = true;

    virtualHosts = {
      "audiobookshelf.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        forceSSL = true;
        locations."/" = {
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host; # try $host instead if this doesn't work
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass http://127.0.0.1:8000; # replace port
            proxy_redirect http://127.0.0.1:8000 https://audiobookshelf.house.flakm.com;'';
        };
      };
    };
  };

  users.groups.deluge.members = [ "audiobookshelf" ];
  systemd.services.audiobookshelf.serviceConfig = {
    Environment = [
      "FFMPEG_PATH=${pkgs.ffmpeg}/bin/ffmpeg"
      "FFPROBE_PATH=${pkgs.ffmpeg}/bin/ffprobe"
    ];
  };

}
