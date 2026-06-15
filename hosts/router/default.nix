{ lib, pkgs, inputs, modulesPath, ... }:

let
  wanInterface = "enp1s0";
  lanInterface = "enp2s0";
  lanAddress = "192.168.10.1";
  lanCidr = "${lanAddress}/24";
  dhcpStart = "192.168.10.100";
  dhcpEnd = "192.168.10.250";
in
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    inputs.nixos-hardware.nixosModules.hardkernel-odroid-h3
  ];

  zfs-root.boot.enable = false;
  boot.zfs.requestEncryptionCredentials = lib.mkForce false;
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" "sdhci_pci" ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/EFI";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };

  networking = {
    hostName = "router";
    hostId = "8425d4f1";
    domain = "house.flakm.com";
    useDHCP = false;
    useNetworkd = false;
    dhcpcd.enable = false;
    networkmanager.enable = false;
    enableIPv6 = false;
    nameservers = [ "127.0.0.1" ];

    nat = {
      enable = true;
      externalInterface = wanInterface;
      internalInterfaces = [ lanInterface ];
    };

    firewall = {
      enable = true;
      allowPing = true;
      checkReversePath = "loose";
      trustedInterfaces = [ lanInterface ];
    };
  };

  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;

    networks = {
      "10-wan" = {
        matchConfig.Name = wanInterface;
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = false;
        };
        linkConfig.RequiredForOnline = "routable";
      };

      "20-lan" = {
        matchConfig.Name = lanInterface;
        address = [ lanCidr ];
        networkConfig = {
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
        };
        linkConfig.RequiredForOnline = "carrier";
      };
    };
  };

  services.dnsmasq = {
    enable = true;
    settings = {
      interface = [ lanInterface "lo" ];
      listen-address = [ lanAddress "127.0.0.1" ];
      bind-interfaces = true;
      domain-needed = true;
      bogus-priv = true;
      no-resolv = true;
      dhcp-authoritative = true;
      domain = "house.flakm.com";
      expand-hosts = true;
      server = [ "1.1.1.1" "9.9.9.9" ];
      dhcp-range = "${dhcpStart},${dhcpEnd},12h";
      dhcp-option = [
        "option:router,${lanAddress}"
        "option:dns-server,${lanAddress}"
      ];
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  environment.systemPackages = with pkgs; [
    dig
    ethtool
    iperf3
    nftables
    tcpdump
  ];

  time.timeZone = "Europe/Warsaw";
  system.stateVersion = lib.mkForce "26.05";
}
