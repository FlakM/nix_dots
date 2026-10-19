# Reverse-proxy the OpenCode server that runs on amd-pc
# (see hosts/amd-pc/opencode-server.nix) as https://opencode.house.flakm.com.
#
# nginx on this host already holds the *.house.flakm.com certificate and AdGuard
# already rewrites *.house.flakm.com to this host, so exposing OpenCode needs no
# extra certificate and no extra DNS record — only this vhost.
{ config, pkgs, lib, ... }:

let
  # Matches the AdGuard "amd-pc" rewrite (hosts/odroid/adguard.nix).
  amdPcHost = "192.168.0.249";
  # Keep in sync with `port` in hosts/amd-pc/opencode-server.nix.
  opencodePort = 49375;
in
{
  services.nginx.virtualHosts."opencode.house.flakm.com" = {
    useACMEHost = "house.flakm.com";
    forceSSL = true;

    # Phone screenshots/attachments can exceed nginx's 1m default body size.
    extraConfig = "client_max_body_size 50m;";

    locations."/" = {
      proxyPass = "http://${amdPcHost}:${toString opencodePort}";
      # Agent output streams over SSE; the UI also opens a websocket.
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        # Streaming: don't buffer and don't cut long agent turns.
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };
}
