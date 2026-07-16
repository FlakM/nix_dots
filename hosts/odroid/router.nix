{ config, lib, ... }:

let
  lanInterface = "enp1s0";
  wanInterface = "enp2s0";
  pppInterface = "ppp0";
  gatewayAddress = "192.168.0.1";
  adguardAddress = "192.168.0.102";
in
{
  system.autoUpgrade.flake = lib.mkForce "github:FlakM/nix_dots#odroid-router";

  services.resolved.enable = lib.mkForce false;

  sops.secrets = {
    pppoe_username = {
      mode = "0400";
      restartUnits = [ "pppd-wan.service" ];
    };
    pppoe_password = {
      mode = "0400";
      restartUnits = [ "pppd-wan.service" ];
    };
  };

  networking = {
    useDHCP = lib.mkForce false;
    useNetworkd = lib.mkForce true;
    dhcpcd.enable = lib.mkForce false;
    networkmanager.enable = lib.mkForce false;
    enableIPv6 = false;
    nameservers = lib.mkForce [ "127.0.0.1" ];

    nat = {
      enable = true;
      externalInterface = pppInterface;
      internalInterfaces = [ lanInterface ];
      extraCommands = "iptables -w -t filter -A nixos-filter-forward -i ${pppInterface} -j DROP";
    };

    firewall = {
      allowedTCPPorts = lib.mkForce [ ];
      allowedUDPPorts = lib.mkForce [ 41641 51820 ];
      allowedTCPPortRanges = lib.mkForce [ ];
      allowedUDPPortRanges = lib.mkForce [ ];
      trustedInterfaces = lib.mkForce [ "lo" lanInterface "wg0" "tailscale0" "podman0" ];
      checkReversePath = "loose";
    };
  };

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;

    networks = {
      "10-wan" = {
        matchConfig.Name = wanInterface;
        networkConfig = {
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
        };
        linkConfig.RequiredForOnline = "carrier";
      };

      "20-lan" = {
        matchConfig.Name = lanInterface;
        address = [ "${gatewayAddress}/24" "${adguardAddress}/24" ];
        networkConfig = {
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
        };
        linkConfig.RequiredForOnline = "carrier";
      };
    };
  };

  services.pppd = {
    enable = true;
    peers.wan.config = "file /run/pppd/pppoe-options";
  };

  systemd.services.pppd-wan = {
    serviceConfig.Type = lib.mkForce "simple";
    preStart = ''
      username="$(<${config.sops.secrets.pppoe_username.path})"
      password="$(<${config.sops.secrets.pppoe_password.path})"

      escape_ppp_option() {
        local value="$1"
        value="''${value//\\/\\\\}"
        value="''${value//\"/\\\"}"
        printf '%s' "$value"
      }

      umask 077
      {
        printf 'plugin pppoe.so\n'
        printf '%s\n' '${wanInterface}'
        printf 'user "%s"\n' "$(escape_ppp_option "$username")"
        printf 'password "%s"\n' "$(escape_ppp_option "$password")"
        printf '%s\n' \
          noauth \
          noipdefault \
          defaultroute \
          replacedefaultroute \
          persist \
          maxfail 0 \
          holdoff 5 \
          mtu 1492 \
          mru 1492 \
          lcp-echo-interval 10 \
          lcp-echo-failure 3 \
          hide-password
      } > /run/pppd/pppoe-options
    '';
  };

  services.dnsmasq = {
    enable = true;
    settings = {
      port = 0;
      interface = lanInterface;
      bind-interfaces = true;
      dhcp-authoritative = true;
      domain = "house.flakm.com";
      dhcp-range = "192.168.0.100,192.168.0.250,12h";
      dhcp-host = [
        "a8:a1:59:dc:67:9c,amd-pc,192.168.0.249,infinite"
        "b4:22:00:87:58:88,DCP-B7520DW,192.168.0.170,infinite"
      ];
      dhcp-option = [
        "option:router,${gatewayAddress}"
        "option:dns-server,${adguardAddress}"
      ];
    };
  };
}
