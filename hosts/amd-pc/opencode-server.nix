# Headless OpenCode server, reachable from the phone.
#
# `opencode serve` runs the same API + web UI that powers the desktop TUI, in
# the foreground, so systemd can supervise it. The web UI is password protected
# by OpenCode itself; this module adds the surrounding hardening:
#
#   * binds to 0.0.0.0 but the firewall only accepts the port from the home
#     LAN (192.168.0.0/24) and from the tailscale0 interface,
#   * the server password is generated on first boot and kept at
#     /var/lib/opencode/server.env (0600, owned by flakm) — never in the store,
#   * the unit runs as flakm with a hardened sandbox and no capabilities.
#
# Get the URL and password with `opencode-server-info`.
#
# NOTE: the desktop TUI keeps talking to its own shared background service on
# the channel-default port (49374); this is a separate, always-on instance on
# 49375. Point the TUI at it with `opencode --server http://127.0.0.1:49375`
# if you want to share sessions between phone and desktop.
{ config, pkgs, inputs, lib, ... }:

let
  port = 49375;

  # Same V2 binary that home-manager installs for flakm.
  opencode = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode2;

  home = config.users.users.flakm.home;

  stateDir = "/var/lib/opencode";
  passwordFile = "${stateDir}/server.env";

  # Extra tools the agents reach for through the shell. On top of these, PATH
  # also gets flakm's home-manager profile and the system profile, so the
  # phone server behaves like an interactive login (cx, nix, git, node, ...).
  agentPath = with pkgs; [
    coreutils
    bash
    git
    nix
    ripgrep
    fd
    findutils
    gnused
    gnugrep
    nodejs
  ];

  # Generate the password once, load it into the environment, then exec the
  # server. Doing this in the wrapper avoids an EnvironmentFile that would have
  # to exist before the service starts on the very first boot.
  serveScript = pkgs.writeShellScript "opencode-serve" ''
    set -euo pipefail

    if [ ! -s "${passwordFile}" ]; then
      umask 077
      printf 'OPENCODE_SERVER_PASSWORD=%s\n' \
        "$(${pkgs.coreutils}/bin/head -c 32 /dev/urandom | ${pkgs.coreutils}/bin/od -An -tx1 | ${pkgs.coreutils}/bin/tr -d ' \n')" \
        > "${passwordFile}"
    fi

    set -a
    # shellcheck disable=SC1090
    . "${passwordFile}"
    set +a

    exec ${opencode}/bin/opencode2 serve --hostname 0.0.0.0 --port ${toString port}
  '';
in
{
  systemd.services.opencode-server = {
    description = "OpenCode headless server (phone / LAN + Tailscale)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "tailscaled.service" ];
    wants = [ "network-online.target" ];

    # Ensure the home dataset is mounted before we touch ~/.local/share/opencode.
    unitConfig.RequiresMountsFor = [ home ];

    serviceConfig = {
      Type = "simple";
      User = "flakm";
      Group = "users";
      WorkingDirectory = home;
      ExecStart = serveScript;

      Environment = [
        "HOME=${home}"
        "XDG_RUNTIME_DIR=/run/opencode"
        "PATH=/etc/profiles/per-user/flakm/bin:/run/current-system/sw/bin:${lib.makeBinPath agentPath}"
      ];

      # /var/lib/opencode is created (and made writable under ProtectSystem)
      # by systemd, owned by flakm so the password file stays user-readable.
      StateDirectory = "opencode";
      StateDirectoryMode = "0700";
      RuntimeDirectory = "opencode";
      RuntimeDirectoryMode = "0700";

      Restart = "on-failure";
      RestartSec = 3;
      UMask = "0077";

      # --- sandboxing ---
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ home ];
      ProtectHome = false; # home must stay writable; it is the only writable path
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      RestrictSUIDSGID = true;
      RestrictRealtime = true;
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];
      LockPersonality = true;
      SystemCallArchitectures = "native";
      CapabilityBoundingSet = "";
    };
  };

  # Only the home LAN and the tailnet may reach the port; everything else is
  # rejected by the default firewall policy. This host uses the iptables
  # backend, so the rules go in extraCommands (extraInputRules is nftables-only)
  # and jump to nixos-fw-accept before the final reject.
  networking.firewall.extraCommands = ''
    iptables  -w -A nixos-fw -s 192.168.0.0/24 -p tcp --dport ${toString port} -j nixos-fw-accept
    iptables  -w -A nixos-fw -i tailscale0 -p tcp --dport ${toString port} -j nixos-fw-accept
    ip6tables -w -A nixos-fw -i tailscale0 -p tcp --dport ${toString port} -j nixos-fw-accept
  '';

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "opencode-server-info" ''
      set -eu
      port=${toString port}

      lan="$(${pkgs.iproute2}/bin/ip -4 route get 1.1.1.1 2>/dev/null \
        | ${pkgs.gawk}/bin/awk '{ for (i = 1; i <= NF; i++) if ($i == "src") print $(i + 1) }')"
      tailnet="$(${pkgs.iproute2}/bin/ip -o -4 addr show dev tailscale0 scope global 2>/dev/null \
        | ${pkgs.gawk}/bin/awk '{ split($4, a, "/"); print a[1] }')"

      echo "OpenCode server (port $port):"
      # Friendly HTTPS name, served by odroid's nginx (hosts/odroid/opencode-proxy.nix).
      echo "  https://opencode.house.flakm.com   (recommended)"
      if [ -n "$lan" ]; then echo "  http://$lan:$port   (home LAN, direct)"; fi
      if [ -n "$tailnet" ]; then echo "  http://$tailnet:$port   (tailnet, direct)"; fi
      echo
      echo "Password (also in ${passwordFile}) — enter it in the web UI:"
      ${pkgs.coreutils}/bin/cat "${passwordFile}"
    '')
    # `opencode pair` only talks to OpenCode's own background service, so it
    # cannot target this standalone server. Mint a pairing link against it by
    # hand, aimed at the friendly HTTPS name, and render a scannable QR code.
    (pkgs.writeShellScriptBin "opencode-phone-pair" ''
      set -eu
      port=${toString port}
      url="https://opencode.house.flakm.com"

      password="$(${pkgs.coreutils}/bin/cut -d= -f2 ${passwordFile})"
      code="$(OPENCODE_SERVER_PASSWORD="$password" opencode api \
        --server "http://127.0.0.1:$port" server.pair | ${pkgs.jq}/bin/jq -r .code)"
      link="$url/auth/connect/$code"

      echo "OpenCode pairing link (single use, expires in 5 minutes):"
      echo "  $link"
      echo
      ${pkgs.qrencode}/bin/qrencode -t ANSIUTF8 "$link"
    '')
  ];
}
