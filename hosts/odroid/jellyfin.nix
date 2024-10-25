{ pkgs, config, ... }: {

  # TODO: enable hybrid codec support
  #nixpkgs.config.packageOverrides = pkgs: {
  #  vaapiIntel = pkgs.vaapiIntel.override { enableHybridCodec = true; };
  #};
  hardware.opengl = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vaapiIntel
      vaapiVdpau
      libvdpau-va-gl
      intel-compute-runtime # OpenCL filter support (hardware tonemapping and subtitle burn-in)
    ];
  };

  services.jellyfin.enable = true;

  networking.firewall.allowedTCPPorts = [ 443 8096 ];

  services.nginx = {
    enable = true;
    virtualHosts = {
      "jellyfin.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        #serverAliases = [ "*.house.flakm.com" ];
        forceSSL = true;
        locations."/" = {
          extraConfig = ''
            proxy_set_header Host $host; # try $host instead if this doesn't work
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass http://127.0.0.1:8096; # replace port
            proxy_redirect http://127.0.0.1:8096 https://jellyfin.house.flakm.com; # replace port
          '';
        };
      };

      "jellyseerr.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        #serverAliases = [ "*.house.flakm.com" ];
        forceSSL = true;
        locations."/" = {
          extraConfig = ''
            proxy_set_header Host $host; # try $host instead if this doesn't work
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass http://127.0.0.1:5055;
            proxy_redirect http://127.0.0.1:5055 https://jellyseerr.house.flakm.com;
          '';
        };
      };


      "sonarr.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        #serverAliases = [ "*.house.flakm.com" ];
        forceSSL = true;
        locations."/" = {
          extraConfig = ''
            proxy_set_header Host $host; # try $host instead if this doesn't work
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass http://127.0.0.1:8989;
            proxy_redirect http://127.0.0.1:8989 https://jellyseerr.house.flakm.com;
          '';
        };
      };


      "sabnzbd.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        #serverAliases = [ "*.house.flakm.com" ];
        forceSSL = true;
        locations."/" = {
          extraConfig = ''
            proxy_set_header Host $host; # try $host instead if this doesn't work
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass http://127.0.0.1:8080;
            proxy_redirect http://127.0.0.1:8080 https://sabnzbd.house.flakm.com;
          '';
        };
      };
    };
  };

  users.groups.jellyfin.members = [ "deluge" ];
  users.groups.deluge.members = [ "jellyfin" ];

  environment.systemPackages = with pkgs; [
    ffmpeg
  ];


  services.jellyseerr = {
    enable = true;
  };

  services.sonarr.enable = true;

  services.sabnzbd.enable = true;


}
