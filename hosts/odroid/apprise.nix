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
  # Topic the phone client is subscribed to. Changing it requires updating the
  # subscription on the phone as well.
  # Podcast descriptions come out of RSS as HTML. Treat incoming bodies as
  # HTML so Apprise converts them for the target instead of forwarding tags.
  ntfyUrl = "ntfys://ntfy.sh/audiobookshelf?format=markdown";
in
{
  # Apprise API is a notification fan-out service. Audiobookshelf posts a
  # title/body here once, and Apprise delivers it to any configured backend
  # (ntfy, Discord, mail, ...). There is no nixpkgs package or NixOS module
  # for the API server, so run the upstream image under podman.
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
  # module restarts ABS and re-applies the settings.
  systemd.services.audiobookshelf.preStart = lib.mkAfter ''
    ${pkgs.python3}/bin/python3 ${./audiobookshelf-notify.py} \
      '${appriseApiUrl}' '${ntfyUrl}'
  '';

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
