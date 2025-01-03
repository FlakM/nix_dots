{ pkgs, config, ... }: {

  # TODO: enable hybrid codec support
  #nixpkgs.config.packageOverrides = pkgs: {
  #  vaapiIntel = pkgs.vaapiIntel.override { enableHybridCodec = true; };
  #};
  hardware.graphics = {
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
    };
  };

  users.groups.jellyfin.members = [ "deluge" ];
  users.groups.deluge.members = [ "jellyfin" ];

  environment.systemPackages = with pkgs; [
    #ffmpeg
  ];

}
