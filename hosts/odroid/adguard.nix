{ self, config, lib, pkgs, ... }:
{

  networking.firewall.allowedUDPPorts = [ 53 ];
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
        bootstrap_dns = [ "1.1.1.1" "8.8.8.8" ];
        upstream_dns = [
          "https://dns.cloudflare.com/dns-query"
          "https://dns.google/dns-query"
          "https://dns.quad9.net/dns-query"
        ];
        enable_dnssec = true;
        ratelimit = 100;
        mutableSettings = false;


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
