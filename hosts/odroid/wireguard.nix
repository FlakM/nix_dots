{ config, pkgs, ... }: {
  networking.wireguard.interfaces = {
    wg0 = {
      ips = [ "10.100.0.2/24" ];
      listenPort = 51820;
      privateKeyFile = config.sops.secrets.wireguard_odroid_private_key.path;

      peers = [
        {
          publicKey = "FfqgT6e/8BLwBBX1Gk1buHKOUWeGMsZw1HwkNRewaHY=";
          allowedIPs = [ "10.100.0.0/24" ];
          endpoint = "blog.flakm.com:51820";
          persistentKeepalive = 25;
        }
      ];
    };
  };

  networking.firewall.allowedUDPPorts = [ 51820 ];

  sops.secrets.wireguard_odroid_private_key = {
    sopsFile = ../../secrets/secrets.yaml;
  };
}
