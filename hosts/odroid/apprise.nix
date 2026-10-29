{
  lib,
  pkgs,
  ...
}:
let
  domain = "apprise.house.flakm.com";
  dataDir = "/var/lib/apprise";
  uid = 993;
  gid = 993;
  port = 8100;

  appriseApiUrl = "http://127.0.0.1:${toString port}/notify";
  # ABS only ever sends static Apprise URLs, so the per-episode Storii play
  # button is added by a relay in front of Apprise (see abs-notify-relay.py).
  relayPort = 8101;
  relayUrl = "http://127.0.0.1:${toString relayPort}/notify";
  # Topic the phone client is subscribed to. Changing it requires updating the
  # subscription on the phone as well.
  # Podcast descriptions come out of RSS as HTML. Treat incoming bodies as
  # HTML so Apprise converts them for the target instead of forwarding tags.
  # Target is the self-hosted private ntfy (hosts/odroid/ntfy.nix); the
  # `agents` user credential is injected at preStart time from sops so the
  # password never ends up in the nix store (see systemd.services below).
  ntfyHost = "ntfy.house.flakm.com";
in
{
  # Apprise API is a notification fan-out service. Audiobookshelf posts a
  # title/body here once, and Apprise delivers it to any configured backend
  # (ntfy, Discord, mail, ...). There is no nixpkgs package or NixOS module
  # for the API server, so run the upstream image under podman.
  # Episode notifications pass through abs-notify-relay.service first, which
  # adds the Storii "Play" button to the ntfy destination.
  users.users.apprise = {
    isSystemUser = true;
    uid = uid;
    group = "apprise";
    home = dataDir;
  };

  users.groups.apprise.gid = gid;

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 apprise apprise - -"
    "d ${dataDir}/config 0750 apprise apprise - -"
    "d ${dataDir}/attach 0750 apprise apprise - -"
    "d ${dataDir}/plugin 0750 apprise apprise - -"
  ];

  virtualisation.oci-containers.containers.apprise = {
    image = "docker.io/caronc/apprise:2.0.1";
    # 8000 is taken by audiobookshelf; keep this loopback-only and let nginx
    # serve the management UI over TLS.
    ports = [ "127.0.0.1:${toString port}:8000" ];
    volumes = [
      "${dataDir}/config:/config"
      "${dataDir}/attach:/attach"
      "${dataDir}/plugin:/plugin"
    ];
    environment = {
      TZ = "Europe/Warsaw";
      APPRISE_STATEFUL_MODE = "simple";
      APPRISE_WORKER_COUNT = "1";
      APPRISE_DEFAULT_FORMAT = "html";
    };
    extraOptions = [
      "--user=${toString uid}:${toString gid}"
      "--read-only"
      "--tmpfs=/tmp:rw,nosuid,nodev,noexec,size=64m"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges"
    ];
  };

  systemd.services.podman-apprise = {
    requires = [ "systemd-tmpfiles-setup.service" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    serviceConfig.RestartSec = "5s";
  };

  # ABS keeps notification settings in SQLite and only reads them at startup,
  # so apply them from the service's preStart hook. This runs as the
  # audiobookshelf user and before ExecStart, which also means changing this
  # module restarts ABS and re-applies the settings. ABS posts to the relay,
  # not straight to Apprise.
  systemd.services.audiobookshelf.preStart = lib.mkAfter ''
    agentsPassword="$(</run/secrets/ntfy_agents_password)"
    ${pkgs.python3}/bin/python3 ${./audiobookshelf-notify.py} \
      '${relayUrl}' "ntfys://agents:''${agentsPassword}@${ntfyHost}/audiobookshelf?format=markdown"
  '';

  # Adds the per-episode `storii://play?id=...&episodeId=...` button to episode
  # notifications: ABS sends Apprise URLs verbatim (no template variables), so
  # the IDs travel in a hidden body marker that this relay strips before
  # forwarding to the Apprise API.
  systemd.services.abs-notify-relay = {
    description = "Audiobookshelf -> Apprise relay (Storii play button)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "podman-apprise.service" ];
    after = [ "podman-apprise.service" ];
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${./abs-notify-relay.py} ${toString relayPort} '${appriseApiUrl}'";
      DynamicUser = true;
      Restart = "always";
      RestartSec = "2s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
    };
  };

  systemd.services.audiobookshelf.wants = [ "abs-notify-relay.service" ];
  systemd.services.audiobookshelf.after = [ "abs-notify-relay.service" ];

  services.nginx.virtualHosts."${domain}" = {
    useACMEHost = "house.flakm.com";
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 25m;
      '';
    };
  };
}
