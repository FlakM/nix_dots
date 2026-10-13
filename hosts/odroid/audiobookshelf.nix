{ pkgs, pkgs-default, ... }: {

  nixpkgs.overlays = [
    (
      self: super: {
        audiobookshelf = super.audiobookshelf.override {
          ffmpeg-full = super.ffmpeg;
        };
      }
    )
  ];

  services.audiobookshelf = {
    enable = true;
    # reached only through the nginx vhost below
    openFirewall = false;
    host = "127.0.0.1";
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
            client_max_body_size 2G;
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass http://127.0.0.1:8000;
            proxy_redirect http://127.0.0.1:8000 https://audiobookshelf.house.flakm.com;'';
        };
      };
    };
  };

  users.groups.deluge.members = [ "audiobookshelf" ];

}
