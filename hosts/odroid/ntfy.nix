# Self-hosted ntfy push notification hub.
#
# Credentials live in secrets.yaml:
#   ntfy_admin_password / ntfy_agents_password - Basic auth for the web UI / CLI
#   ntfy_agent_token     - tk_... bearer token for publishing/subscribing
#   ntfy_environment     - EnvironmentFile that provisions users/ACL/token
#                          declaratively at server start (users are marked
#                          "provisioned": removing them from the config
#                          deletes them from the database).
#
# Access paths:
#   - LAN / tailnet via https://ntfy.house.flakm.com (nginx, restricted below)
#   - public (agents on other machines) via https://ntfy.public.flakm.com,
#     proxied from the Hetzner blog server over the wireguard link to the raw
#     :2586 listener — same pattern as the jellyfin/audiobookshelf public
#     vhosts, which live in the blog repo.
{ config, pkgs, lib, ... }: {
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.public.flakm.com";
      # raw listener reachable from the wireguard hub; nginx (LAN/tailnet)
      # proxies to 127.0.0.1, so the firewall only opens :2586 on wg0
      listen-http = "0.0.0.0:2586";
      behind-proxy = true;

      # private instance: nothing readable/writable without credentials
      auth-default-access = "deny-all";
      enable-login = true;

      # queue/own reminders past the default 12h retention
      cache-duration = "36h";

      # iOS app on a self-hosted server needs the poll_request relay
      upstream-base-url = "https://ntfy.sh";
    };
    environmentFile = config.sops.secrets.ntfy_environment.path;
  };

  sops.secrets.ntfy_environment = {
    sopsFile = ../../secrets/secrets.yaml;
    restartUnits = [ "ntfy-sh.service" ];
  };

  # Basic-auth credential for non-admin publishing (Apprise/audiobookshelf).
  # Owned by the ABS user: its preStart hook composes the Apprise URL from it.
  # Rotating it rewrites ntfy's provisioned user hash (ntfy-sh restart) and the
  # ABS notification settings (audiobookshelf preStart) in one go.
  sops.secrets.ntfy_agents_password = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = "audiobookshelf";
    # ABS preStart rebuilds its notification URL from this; ntfy-sh doesn't
    # need a restart (its own hash lives in ntfy_environment).
    restartUnits = [ "audiobookshelf.service" ];
  };

  # wireguard-only exposure for the hetzner proxy
  networking.firewall.interfaces.wg0.allowedTCPPorts = [ 2586 ];

  services.nginx.virtualHosts."ntfy.house.flakm.com" = {
    useACMEHost = "house.flakm.com";
    forceSSL = true;
    # LAN / tailnet only; the public path goes through the hetzner proxy
    extraConfig = ''
      allow 192.168.0.0/16;
      allow 100.64.0.0/10;
      allow 10.100.0.0/24;
      # podman bridge: the apprise container publishes its notifications
      # through this vhost (see apprise.nix)
      allow 10.88.0.0/16;
      deny all;
    '';
    locations."/" = {
      proxyWebsockets = true;
      extraConfig = ''
        proxy_pass http://127.0.0.1:2586;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_redirect http://127.0.0.1:2586 https://ntfy.house.flakm.com;
        # subscriptions keep a JSON/SSE stream open for hours
        proxy_buffering off;
        proxy_cache off;
        gzip off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };

  environment.systemPackages = with pkgs; [ ntfy-sh ];
}
