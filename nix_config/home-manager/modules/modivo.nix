{ lib, pkgs, ... }:
let
  ## xdg-open shim that proxies to handlr
  xdg-open = pkgs.writeScriptBin "xdg-open" ''
    #!/usr/bin/env bash
    handlr open "$@"
  '';
  slack-wrapped = pkgs.slack.overrideAttrs (old: {
    installPhase = old.installPhase + ''
      rm $out/bin/slack

      makeWrapper $out/lib/slack/slack $out/bin/slack \
        --prefix XDG_DATA_DIRS : $GSETTINGS_SCHEMAS_PATH \
        --prefix PATH : ${lib.makeBinPath [xdg-open]} \
        --add-flags "--ozone-platform=wayland --enable-features=UseOzonePlatform,WebRTCPipeWireCapturer"
    '';
  });
  vpn = pkgs.openfortivpn.overrideAttrs (old: {
    src = builtins.fetchGit {
      url = "https://github.com/adrienverge/openfortivpn";
      ref = "master";
      rev = "1ccb8ee682af255ae85fecd5fcbab6497ccb6b38";
    };
  });

in
{
  home.packages = with pkgs; [
    slack-wrapped
    google-cloud-sdk
    #unstable.openfortivpn
    vpn
  ];
}
