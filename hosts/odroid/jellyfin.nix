{ pkgs, pkgs-unstable, config, ... }: {

  nixpkgs.overlays = [
    (self: super: {
      vaapiIntel = super.vaapiIntel.override { enableHybridCodec = true; };
    })
  ];

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs;[
      intel-media-driver
      intel-vaapi-driver
      libva-vdpau-driver
      libvdpau-va-gl
      intel-compute-runtime
    ];
  };

  # to allow jellyfin to fully use hardware acceleration
  hardware.firmware = with pkgs; [
    linux-firmware
  ];

  services.jellyfin = {
    enable = true;
    group = "jellyfin";
  };

  systemd.services.jellyfin = {
    serviceConfig = {
      SupplementaryGroups = [ "render" "video" "media" ];
      DeviceAllow = [
        "/dev/dri/renderD128 rw"
      ];
    };
  };

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
            proxy_redirect http://127.0.0.1:8989 https://sonarr.house.flakm.com;                                                                                                                                                                                                      
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

      "radarr.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        forceSSL = true;
        locations."/" = {
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass http://127.0.0.1:7878;
            proxy_redirect http://127.0.0.1:7878 https://radarr.house.flakm.com;
          '';
        };
      };


      "readarr.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        #serverAliases = [ "*.house.flakm.com" ];                                                                                                                                                                                                                                     
        forceSSL = true;
        locations."/" = {
          extraConfig = ''                                                                                                                                                                                                                                                            
            proxy_set_header Host $host; # try $host instead if this doesn't work                                                                                                                                                                                                     
            proxy_set_header X-Forwarded-Proto $scheme;                                                                                                                                                                                                                               
            proxy_pass http://127.0.0.1:8787;                                                                                                                                                                                                                                         
            proxy_redirect http://127.0.0.1:8787 https://readarr.house.flakm.com;                                                                                                                                                                                                     
          '';
        };
      };
    };
  };

  environment.systemPackages = with pkgs; [
    #ffmpeg
  ];



  disabledModules = [ "services/misc/jellyseerr.nix" ];

  imports = [
    "${pkgs-unstable.path}/nixos/modules/services/misc/jellyseerr.nix"
  ];

  services.jellyseerr = {
    enable = true;
    package = pkgs-unstable.jellyseerr;
  };

  services.sonarr.enable = true;

  services.sabnzbd.enable = true;

  services.radarr.enable = true;

  services.readarr.enable = true;

}
