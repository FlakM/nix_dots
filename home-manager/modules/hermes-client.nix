{ config, lib, pkgs, ... }:

let
  hermes-client = pkgs.callPackage ../../packages/hermes-client.nix { };
  hermes-tui = pkgs.callPackage ../../packages/hermes-tui.nix { };
in
{
  # Token for the agent HTTP API on the odroid. The value lives in
  # secrets/secrets.yaml under the `hermes_api_token` key (same token the
  # odroid exposes via HERMES_API_TOKEN_FILE). Only the path is referenced
  # here; nothing secret enters the Nix store.
  sops.secrets.hermes_api_token = {
    mode = "0400";
  };

  # Client config read by `hermes`, `hermes-tui` and `hermes-bridge`
  # (see packages/hermes-client/hermes_client/config.py and
  # packages/hermes-tui/src/config.rs).
  xdg.configFile."hermes/client.env".text = ''
    HERMES_API_URL=https://hermes.house.flakm.com
    HERMES_API_TOKEN_FILE=${config.sops.secrets.hermes_api_token.path}
  '';

  home.packages = [ hermes-client hermes-tui ];

  # SSE → notify-send + ~/.cache/hermes/bridge.json for the quickshell panel.
  # The bridge retries forever with exponential backoff, so a missing token or
  # an offline odroid is a banner in the TUI, never a dead service.
  systemd.user.services.hermes-bridge = {
    Unit = {
      Description = "Hermes notification bridge (SSE → notify-send → quickshell)";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
      # Restart=always must not be defeated by systemd's start rate limit.
      StartLimitIntervalSec = 0;
    };
    Service = {
      ExecStart = "${hermes-client}/bin/hermes-bridge";
      Restart = "always";
      RestartSec = 5;
      # The SSE read can block past systemd's stop grace period; do not let a
      # restart wait 90s and report `Result=timeout`.
      TimeoutStopSec = 5;
      Environment = [ "PYTHONUNBUFFERED=1" ];
    };
    Install.WantedBy = [ "default.target" ];
  };
}
