# Local-dev nginx that fronts the Coralogix services on a single HTTPS port
# per `*.cx.test` subdomain. Lets the browser see one origin (and one cookie
# domain) per team, mirroring how `*.coralogix.com` works in staging/prod.
# `.test` is RFC 6761 reserved-for-testing — avoids `.localhost`'s special
# browser handling, and HTTPS termination here means sso-service can keep its
# production-vanilla cookie attributes (`Secure`, `SameSite=Strict`).
#
# Routing per host (port 8443, HTTPS):
#   /                  → Angular dev server (`web-app`, [::1]:4200)
#   /saml/*            → sso-service       (127.0.0.1:3030)
#   /v2/saml/*         → sso-service       (127.0.0.1:3030)
#   /api/v1/saml/*     → sso-service       (127.0.0.1:3030)
#   /api/v2/saml/*     → sso-service       (127.0.0.1:3030)
#   /auth/v1/*         → STS               (127.0.0.1:8084)
#
# ────────── Bootstrap (one-time) ──────────
# 1. Run as your user (NOT sudo): `mkcert -install`
#    - Creates the CA at `~/.local/share/mkcert/`
#    - Installs it into Chrome/Firefox NSS DB so they trust it natively
#    - Installs it into the system trust store (curl, wget, etc.)
# 2. `sudo nixos-rebuild switch`
#    - Systemd unit below uses your CA to issue the wildcard cert
#    - nginx starts on port 8443
# 3. Re-running `mkcert -install` is needed only after a Firefox profile reset
#    or new browser install.
#
# Update test env vars to use HTTPS:
#   SSO_CX_BASE_URL=https://aaa-multisaml-testing.cx.test:8443
#   SSO_ORG_TEAM1_BASE_URL=https://aaa-multisaml-testing-org1.cx.test:8443
#   SSO_ORG_TEAM2_BASE_URL=https://aaa-multisaml-testing-org2.cx.test:8443
#
# Update the SAML config's `api_base_endpoint` to `https://sso.cx.test:8443`
# in the DB and re-upload metadata to the IdP.

{ pkgs, lib, ... }:

let
  certDir = "/var/lib/nginx-cx-dev";
  userCaroot = "/home/flakm/.local/share/mkcert";

  # Custom gRPC-Web → gRPC shim. Source colocated with this module so the
  # flake stays in pure-eval mode (absolute paths outside the flake are
  # rejected). `vendorHash` is set after first build (run with the
  # placeholder, copy the "got: …" hash from the error, rebuild).
  cxGrpcShim = pkgs.buildGoModule {
    pname = "cx-grpc-web-shim";
    version = "0.1.0";
    src = ./cx-grpc-web-shim;
    vendorHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  upstreams = ''
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_http_version 1.1;
    proxy_redirect off;
    proxy_connect_timeout 60s;
    proxy_send_timeout 300s;
    proxy_read_timeout 300s;
    # Vite streams source-map / large module responses; buffering them in
    # nginx pauses the HTTP/2 stream and surfaces as `ERR_CONNECTION_CLOSED`.
    proxy_buffering off;
    proxy_request_buffering off;
  '';

  ssoLocations = {
    "/saml/" = {
      proxyPass = "http://sso-upstream";
      extraConfig = "${upstreams}";
    };
    "/v2/saml/" = {
      proxyPass = "http://sso-upstream";
      extraConfig = "${upstreams}";
    };
    "/api/v1/saml/" = {
      proxyPass = "http://sso-upstream";
      extraConfig = "${upstreams}";
    };
    "/api/v2/saml/" = {
      proxyPass = "http://sso-upstream";
      extraConfig = "${upstreams}";
    };
    "/api/v1/company/saml/" = {
      proxyPass = "http://sso-upstream";
      extraConfig = "${upstreams}";
    };
    "/api/v2/company/saml/" = {
      proxyPass = "http://sso-upstream";
      extraConfig = "${upstreams}";
    };
    "/auth/v1/" = {
      proxyPass = "http://sts-upstream";
      extraConfig = "${upstreams}";
    };
    # gRPC-Web → gRPC translation via Envoy (port 8085) to identity-service:6666.
    # Browsers can't speak native gRPC (no JS API for HTTP/2 trailers); Envoy's
    # `grpc_web` http_filter parses the HTTP/1.1 grpc-web body framing and
    # re-emits it as HTTP/2 gRPC to the upstream. nginx is plain proxy_pass.
    "/com.coralogix.identity." = {
      proxyPass = "http://envoy-grpc-upstream";
      extraConfig = "${upstreams}";
    };
    # Catch-all → Angular dev server (HMR websockets included).
    "/" = {
      proxyPass = "http://vite-upstream";
      extraConfig = ''
        ${upstreams}
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
      '';
    };
  };

  teamHost = _host: {
    # http2 = false: HTTP/1.1 from browser. Vite serves thousands of dynamic
    # imports per page; multiplexing them on a single HTTP/2 connection
    # outpaced Vite (or nginx's stream pacing) and stalled the tail of the
    # request fan-out into permanent `[pending]`. With HTTP/1.1 the browser
    # opens ~6 connections per host and naturally caps in-flight depth, which
    # is what direct localhost:4200 already relies on.
    http2 = false;
    listen = [{
      addr = "0.0.0.0";
      port = 8443;
      ssl = true;
    }];
    onlySSL = true;
    sslCertificate = "${certDir}/cert.pem";
    sslCertificateKey = "${certDir}/key.pem";
    locations = ssoLocations;
  };
in

{
  environment.systemPackages = [ pkgs.mkcert pkgs.nss.tools ];

  # System trust for the mkcert CA: `security.pki.certificateFiles` reads
  # paths in the Nix sandbox, which can't see `~/.local`. Instead, copy the
  # CA into a sandbox-readable location at activation time and append to a
  # writable bundle the user can point SSL_CERT_FILE at.
  systemd.tmpfiles.rules = [
    "d /etc/cx-dev-trust 0755 root root - -"
    "d /var/log/nginx-cx-dev 0755 nginx nginx - -"
    # NixOS nginx unit ships RuntimeDirectory=nginx, but its `nginx -t` ExecStartPre
    # races and sometimes runs before the runtime dir is created. Pin it via
    # tmpfiles so the pre-start config-test always finds /run/nginx.
    "d /run/nginx 0755 nginx nginx - -"
  ];

  systemd.services.cx-dev-trust-bundle = {
    description = "Append mkcert root CA to /etc/cx-dev-trust/ca-bundle.crt";
    after = [ "cx-dev-mkcert.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /etc/cx-dev-trust
      if [ -f ${userCaroot}/rootCA.pem ]; then
        cat /etc/ssl/certs/ca-bundle.crt ${userCaroot}/rootCA.pem \
          > /etc/cx-dev-trust/ca-bundle.crt
        chmod 0644 /etc/cx-dev-trust/ca-bundle.crt
      fi
    '';
  };

  # Issue the wildcard cert from the user-installed mkcert CA. Browsers already
  # trust that CA (because `mkcert -install` ran as the user), so the cert
  # nginx serves is trusted natively without any --ignore-cert hack.
  systemd.services.cx-dev-mkcert = {
    description = "Issue mkcert wildcard cert for *.cx.test from the user CA";
    before = [ "nginx.service" ];
    wantedBy = [ "nginx.service" ];
    path = [ pkgs.mkcert pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = "CAROOT=${userCaroot}";
    };
    script = ''
      mkdir -p ${certDir}

      if [ ! -f ${userCaroot}/rootCA.pem ]; then
        echo "ERROR: mkcert CA missing at ${userCaroot}." >&2
        echo "Run 'mkcert -install' as your user (not sudo) first, then re-run nixos-rebuild." >&2
        exit 1
      fi

      if [ ! -f ${certDir}/cert.pem ] || [ ! -f ${certDir}/key.pem ]; then
        mkcert \
          -cert-file ${certDir}/cert.pem \
          -key-file ${certDir}/key.pem \
          "*.cx.test" cx.test \
          "*.cx.localhost" cx.localhost \
          localhost 127.0.0.1 ::1
      fi

      chown nginx:nginx ${certDir}/cert.pem ${certDir}/key.pem
      chmod 0644 ${certDir}/cert.pem
      chmod 0640 ${certDir}/key.pem
    '';
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = false;
    # Vite dev fires thousands of dynamic-import requests per page; default
    # 1024 worker_connections starves under load.
    appendConfig = ''
      worker_processes auto;
      worker_rlimit_nofile 65536;
    '';
    eventsConfig = ''
      worker_connections 8192;
    '';
    # Pooled upstreams with `keepalive` so we don't spawn a fresh socket to
    # the dev servers on every HTTP/2 stream. Without this, Vite's [::1]:4200
    # gets hammered with hundreds of new connections per page load and starts
    # RST'ing streams, which the browser surfaces as `net::ERR_FAILED` for
    # dynamic imports.
    appendHttpConfig = ''
      # Allow more concurrent HTTP/2 streams per connection — Vite dev fires
      # thousands of dynamic imports during the FE bootstrap; default 128
      # (and even 512) gets exceeded and surfaces as Chrome
      # `ERR_HTTP2_SERVER_REFUSED_STREAM`.
      http2_max_concurrent_streams 4096;

      # Bare upstream blocks (no keepalive) so each HTTP/2 stream from the
      # browser maps to its own short-lived HTTP/1.1 connection to the dev
      # server. Keepalive pools (even at 64) serialised requests through the
      # pool and stalled the tail of Vite's bootstrap fan-out into permanent
      # `[pending]` once the pool was saturated. Direct hits to localhost:4200
      # work fine because each request gets a fresh socket — mirror that.
      upstream vite-upstream {
        server [::1]:4200;
      }
      upstream sso-upstream {
        server 127.0.0.1:3030;
      }
      upstream sts-upstream {
        server 127.0.0.1:8084;
      }
      upstream envoy-grpc-upstream {
        server 127.0.0.1:8085;
      }
    '';
    virtualHosts = {
      "aaa-multisaml-testing.cx.test" = teamHost "aaa-multisaml-testing.cx.test";
      "aaa-multisaml-testing-org1.cx.test" = teamHost "aaa-multisaml-testing-org1.cx.test";
      "aaa-multisaml-testing-org2.cx.test" = teamHost "aaa-multisaml-testing-org2.cx.test";
      "sso.cx.test" = teamHost "sso.cx.test";
      "dashboard.cx.test" = teamHost "dashboard.cx.test";
    };
  };

  networking.firewall.allowedTCPPorts = [ 8443 ];

  # gRPC-Web → gRPC translator with cookie→AuthContext minting.
  #
  # Why not nginx alone: nginx can't translate the gRPC-Web body framing.
  # Why not envoy: nixpkgs envoy is currently broken (deps tarball hash
  # mismatch), and bare envoy still wouldn't synthesize x-coralogix-auth.
  # Why a custom shim: identity-service expects x-coralogix-auth = base64url
  # (proto AuthContext{user_id, company_id}). In prod this is produced by
  # Istio. Locally we mint it: read the coralogix_global_session cookie,
  # call STS /auth/v1/session (cookie-validated) to resolve user/team, then
  # encode and forward as gRPC over HTTP/2 to identity-service:6666.
  systemd.services.cx-grpc-shim = {
    description = "gRPC-Web → gRPC translator with cookie→AuthContext minting";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    requires = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = "${cxGrpcShim}/bin/cx-grpc-web-shim";
      Restart = "on-failure";
      RestartSec = 2;
      DynamicUser = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
    };
  };
}
