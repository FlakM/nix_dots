{pkgs, lib, ...}:
let
  slack-wrapped = pkgs.master.slack.overrideAttrs (old: {
    installPhase = old.installPhase + ''
      rm $out/bin/slack

      makeWrapper $out/lib/slack/slack $out/bin/slack \
        --prefix XDG_DATA_DIRS : $GSETTINGS_SCHEMAS_PATH \
        --prefix PATH : ${lib.makeBinPath [pkgs.xdg-utils]} \
        --add-flags "--ozone-platform=wayland --enable-features=UseOzonePlatform,WebRTCPipeWireCapturer"
    '';
  });
in {

  home.packages = with pkgs; [
    #slack-wrapped
    master.slack
    google-cloud-sdk
    openfortivpn
    minio-client
    redis
  ];

}
