{ self, config, lib, pkgs, ... }:
{

  networking.firewall.allowedUDPPorts = [ 53 ];

  systemd.services.adguardhome = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    # yaml-merge (PyYAML) drops the T separator from ISO8601 timestamps
    # turning "2026-02-15T15:32:54" into "2026-02-15 15:32:54"
    # which Go's time.Time parser rejects. Fix it after merge.
    # https://github.com/NixOS/nixpkgs/issues/483743
    preStart = lib.mkAfter ''
      if [ -f "$STATE_DIRECTORY/AdGuardHome.yaml" ]; then
        ${lib.getExe pkgs.gnused} -i 's/protection_disabled_until: \([0-9-]*\) \([0-9]\)/protection_disabled_until: \1T\2/' "$STATE_DIRECTORY/AdGuardHome.yaml"
      fi
    '';
    # `sed -i` above fchown()s the in-place temp file on close; the module's
    # SystemCallFilter (~@privileged) blocks chown and the kernel kills sed with
    # SIGSYS, looping the unit. Re-allow the chown family for this service.
    serviceConfig.SystemCallFilter = lib.mkAfter [ "@chown" ];
  };

  # Health check: restart AdGuard Home if DNS stops responding.
  # The DNS proxy can become wedged (goroutine exhaustion from DoH + DNSSEC)
  # while the process stays alive, so systemd's default restart logic won't help.
  systemd.services.adguardhome-watchdog = {
    description = "AdGuard Home DNS health check";
    after = [ "adguardhome.service" ];
    requires = [ "adguardhome.service" ];
    serviceConfig = {
      Type = "oneshot";
      # Don't let systemctl restart kill this unit mid-flight
      KillMode = "none";
      ExecStart = pkgs.writeShellScript "adguardhome-watchdog" ''
        # Wait for AdGuard to be fully up before testing
        sleep 10
        if ! ${pkgs.dig}/bin/dig @127.0.0.1 cloudflare.com +short +timeout=5 +tries=2 > /dev/null 2>&1; then
          echo "AdGuard Home DNS unresponsive, restarting..."
          systemctl restart adguardhome.service
        fi
      '';
    };
  };

  systemd.timers.adguardhome-watchdog = {
    description = "Run AdGuard Home DNS health check every 5 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
    };
  };

  services.adguardhome = {
    enable = true;
    openFirewall = true;
    allowDHCP = true;

    settings = {
      #auth_attempts = 3;
      #block_auth_min = 10;
      http.address = "0.0.0.0:3000";

      filtering = {
        rewrites = [
          {
            domain = "odroid";
            answer = "192.168.0.102";
            enabled = true;
          }
          {
            domain = "amd-pc";
            answer = "192.168.0.249";
            enabled = true;
          }
          {
            domain = "amd";
            answer = "192.168.0.249";
            enabled = true;
          }
          {
            domain = "jellyfin.house.flakm.com";
            answer = "192.168.0.102";
            enabled = true;
          }
          {
            domain = "house.flakm.com";
            answer = "192.168.0.102";
            enabled = true;
          }
          {
            domain = "*.house.flakm.com";
            answer = "192.168.0.102";
            enabled = true;
          }
        ];
      };

      dns = {
        bind_hosts = [ "0.0.0.0" ];
        bootstrap_dns = [ "1.1.1.1" "8.8.8.8" "9.9.9.9" ];
        upstream_dns = [
          "https://dns.cloudflare.com/dns-query"
          "https://dns.google/dns-query"
        ];
        # Plain DNS fallback breaks the DoH bootstrap circular dependency
        # (AGH needs DNS to resolve DoH hostnames)
        fallback_dns = [ "1.1.1.1" "8.8.8.8" ];
        # Cloudflare/Google already validate DNSSEC; second layer just
        # inflates responses and triggers "buffer size too small" errors
        enable_dnssec = false;
        ratelimit = 100;
        # Default 300 causes goroutine exhaustion when DoH upstreams are slow;
        # 0 = unlimited. See github.com/AdguardTeam/AdGuardHome/issues/4317
        max_goroutines = 0;
        # Free goroutines faster when upstreams are slow (default 10s)
        upstream_timeout = "3s";
      };

      users = [
        {
          name = "admin";
          password = "$2y$10$PjU1eo8TxgRWekuVfihCZu9H9kwZ8duzmqD.DV2ByDAgQ5e3b7Bri";
        }
      ];

      #statistics = {
      #  enabled = true;
      #  interval = "8760h";
      #};
      #dhcp = {
      #  enabled = true;
      #  interface_name = "enp1s0";
      #  dhcpv4 = {
      #    enabled = true;
      #    gateway_ip = "192.168.0.1";
      #    subnet_mask = "255.255.255.0";
      #    range_start = "192.168.0.100";
      #    range_end = "192.168.0.255";
      #  };
      #};

      filters = [
        {
          enabled = true;
          name = "AdGuard DNS filter";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
          id = 1;
        }
        {
          enabled = true;
          name = "AdAway Default Blocklist";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt";
          id = 2;
        }
      ];


    };
  };



  services.nginx = {
    enable = true;
    virtualHosts = {
      "adguard.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        #serverAliases = [ "*.house.flakm.com" ];
        forceSSL = true;
        locations."/" = {
          extraConfig = ''
            proxy_set_header Host $host; # try $host instead if this doesn't work
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass http://127.0.0.1:3000; # replace port
            proxy_redirect http://127.0.0.1:3000 https://adguard.house.flakm.com; # replace port
          '';
        };
      };
    };
  };
}
