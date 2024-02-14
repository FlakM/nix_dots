{ config, pkgs, ... }:

{

  networking.firewall = {
    allowedUDPPorts = [ 51820 ];
  };

  #networking.wg-quick.interfaces = {
  #  wg0 = {
  #    address = [ "fdf3:e1c5:2572:6::29/128" ];
  #    #dns = [ "fdf3:e1c5:2572::2:0" ];
  #    privateKeyFile = "/home/flakm/wireguard-keys/private";

  #    peers = [
  #      {
  #        publicKey = "iRVcBTyDgqYOtabwnmKD2QHCVik1ZVeHjys0yW4qgmc=";
  #        allowedIPs = [ "fdf3:e1c5:2572::/48" ];
  #        endpoint = "wg-devs.eobuwie.org:51820";
  #        persistentKeepalive = 25;
  #      }
  #    ];
  #  };
  #};

  # Enable WireGuard
  networking.wireguard.interfaces = {
    # "wg0" is the network interface name. You can name the interface arbitrarily.
    wg0 = {
      # Determines the IP address and subnet of the client's end of the tunnel interface.
      ips = [ "fdf3:e1c5:2572:6::29/128" ];

      listenPort = 51820; # to match firewall allowedUDPPorts (without this wg uses random port numbers)

      # Path to the private key file.
      #
      # Note: The private key can also be included inline via the privateKey option,
      # but this makes the private key world-readable; thus, using privateKeyFile is
      # recommended.
      privateKeyFile = "/home/flakm/wireguard-keys/private";
      mtu = 1420; # https://www.wireguard.com/receive/

      peers = [
        # For a client configuration, one peer entry for the server will suffice.

        {
          # Public key of the server (not a file path).
          publicKey = "iRVcBTyDgqYOtabwnmKD2QHCVik1ZVeHjys0yW4qgmc=";

          # Forward all the traffic via VPN.
          allowedIPs = [ "fdf3:e1c5:2572::/48" ];
          # Or forward only particular subnets
          #allowedIPs = [ "10.100.0.1" "91.108.12.0/22" ];

          # Set this to the server IP and port.
          endpoint = "wg-devs.eobuwie.org:51820"; # ToDo: route to endpoint not automatically configured https://wiki.archlinux.org/index.php/WireGuard#Loop_routing https://discourse.nixos.org/t/solved-minimal-firewall-setup-for-wireguard-client/7577

          # Send keepalives every 25 seconds. Important to keep NAT tables alive.
          persistentKeepalive = 25;

        }
      ];
    };
  };

}
