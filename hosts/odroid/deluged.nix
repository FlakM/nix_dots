{ pkgs, config, ... }:
let
  nordvpnSetupScript = pkgs.writeScript "nordvpn-setup.sh" ''
    #!/usr/bin/env bash
    set -e

    mkdir -p /etc/netns/nordvpn_ns
    echo "nameserver 8.8.8.8" > /etc/netns/nordvpn_ns/resolv.conf

    # Create a network namespace for NordVPN
    ip netns add nordvpn_ns  || true
    
    # Create a virtual Ethernet pair** for the NordVPN namespace to communicate with the main network:
    ip link add veth-nordvpn type veth peer name br-nordvpn || true
    
    # Move `veth-nordvpn` interface into the NordVPN namespace
    ip link set veth-nordvpn netns nordvpn_ns || true
    
    # **Set up the interfaces and IP addresses**:
    ip addr add 10.200.2.1/24 dev br-nordvpn || true
    ip link set br-nordvpn up || true
    
    ip netns exec nordvpn_ns ip addr add 10.200.2.2/24 dev veth-nordvpn || true
    ip netns exec nordvpn_ns ip link set veth-nordvpn up || true
    ip netns exec nordvpn_ns ip route add default via 10.200.2.1 || true
    
    # **Setup NAT on the main namespace** to allow the NordVPN namespace to access the external network:
    iptables -t nat -A POSTROUTING -s 10.200.2.0/24 -j MASQUERADE
    
    
    # enable ip forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # **Start NordVPN's WireGuard client inside the `nordvpn_ns` namespace**:
    ip netns exec nordvpn_ns wgnord c poland

    sleep 5
    
    # check if the internet connection works property
    ip netns exec nordvpn_ns curl ipinfo.io
    
    # Ensure the loopback interface (`lo`) is up and running
    ip netns exec nordvpn_ns ip link set lo up
    
    PORT=8112
    DEFAULT_INTERFACE="enp1s0" # Change this to your main interface if it's different
    
    # Forward traffic from the default namespace to the nordvpn_ns namespace
    iptables -t nat -A PREROUTING -i $DEFAULT_INTERFACE -p tcp --dport $PORT -j DNAT --to-destination 10.200.2.2:$PORT
    
    # Allow packet forwarding for these connections
    iptables -A FORWARD -i $DEFAULT_INTERFACE -o br-nordvpn -p tcp --dport $PORT -d 10.200.2.2 -j ACCEPT
    
    # Set reverse NAT for replies
    iptables -t nat -A POSTROUTING -o br-nordvpn -p tcp --dport $PORT -d 10.200.2.2 -j SNAT --to-source 10.200.2.1


    for PORT in {6881..6891}; do
        iptables -t nat -A PREROUTING -i $DEFAULT_INTERFACE -p tcp --dport $PORT -j DNAT --to-destination 10.200.2.2:$PORT
        iptables -A FORWARD -i $DEFAULT_INTERFACE -o br-nordvpn -p tcp --dport $PORT -d 10.200.2.2 -j ACCEPT
        iptables -t nat -A POSTROUTING -o br-nordvpn -p tcp --dport $PORT -d 10.200.2.2 -j SNAT --to-source 10.200.2.1
    done
  '';
in
{

  #systemd.services.nordvpn-setup = {
  #  description = "NordVPN Network Setup";
  #  path = with pkgs; [ iproute2 iptables bash wireguard-tools wgnord curl openresolv ];
  #  script = "${nordvpnSetupScript}";
  #  wantedBy = [ "multi-user.target" ];
  #  before = [ "deluged.service" "delugeweb.service" ];
  #  wants = [ "network-online.target" ];
  #  after = [ "network-online.target" ];

  #  serviceConfig = {
  #    Restart = "on-failure";
  #    RestartSec = "5s"; # Waits 5 seconds before restarting
  #    StartLimitIntervalSec = "60s"; # Check number of restarts within 60 seconds
  #    StartLimitBurst = 3; # Allow up to 3 restarts within the interval
  #  };
  #};

  services.deluge = {
    enable = true;
    web = {
      enable = true;
      openFirewall = false;
      port = 8112;
    };
    declarative = false;
    config = {
      download_location = "/var/media/grownups/seriale/";
      #share_ratio_limit = "2.0";
      allow_remote = true;
      dht = false;
      peer_exchange = false;
      dht_torrents = false;
      lsd = false;
      enable_utp = false;
      enable_udp_trackers = true;
      announce_to_all_trackers = true;
      allow_incoming_legacy = true;
      listen_ports = [ 6881 6891 ]; # This sets the incoming port range
    };
    authFile = "/var/secrets/deluge/auth";
    openFirewall = true;
  };



  #systemd.services.deluged.serviceConfig = {
  #  NetworkNamespacePath = "/var/run/netns/nordvpn_ns";
  #};

  #systemd.services.delugeweb.serviceConfig = {
  #  NetworkNamespacePath = "/var/run/netns/nordvpn_ns";
  #};


  networking.firewall.allowedTCPPorts = [ 8112 6881 6882 6883 6884 6885 6886 6887 6888 6889 6890 6891 ];
  networking.firewall.allowedUDPPorts = [ 6881 6882 6883 6884 6885 6886 6887 6888 6889 6890 6891 ];

  services.nginx = {
    enable = true;
    virtualHosts = {
      "delugeweb.house.flakm.com" = {
        enableACME = false; # Since you're providing your own certs
        forceSSL = true;
        sslCertificate = "/var/secrets/certs/house.crt";
        sslCertificateKey = "/var/secrets/certs/house.key";

        locations."/" = {
          extraConfig = ''
            proxy_set_header Host $host; # try $host instead if this doesn't work
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass http://127.0.0.1:8112; # replace port
            proxy_redirect http://127.0.0.1:8112 https://delugeweb.house.flakm.com;'';
        };
      };
    };
  };

}
