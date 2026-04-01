# MicroVM host configuration for amd-pc.
# Sets up a bridge network (192.168.100.1/24) with NAT and defines the "clawd" guest.
#
# After rebuild:
#   systemctl status microvm@clawd.service
#   ssh clawd
#
# Monitor traffic:
#   sudo iftop -i microbr0
#   sudo tcpdump -i microbr0 -n
#   nft list ruleset
#
# Resource usage:
#   systemd-cgtop
#   systemctl show microvm@clawd | grep -E "Memory|CPU"
#
# VM data lives on rpool/nixos/microvms/clawd — snapshotted by sanoid,
# replicable via syncoid like any other dataset.
{ lib, pkgs, inputs, config, ... }:
let
  clawdWebhookPort = 8788;
in {
  imports = [ inputs.microvm.nixosModules.host ];

  # Bridge interface for VM tap adapters.
  networking.bridges.microbr0.interfaces = [];
  networking.interfaces.microbr0.ipv4.addresses = [{
    address = "192.168.100.1";
    prefixLength = 24;
  }];

  # NAT so the VM can reach the internet.
  # Port-forward clawdWebhookPort → clawd VM so Nextcloud Talk can call OpenClaw.
  networking.nat = {
    enable = true;
    internalInterfaces = [ "microbr0" ];
    externalInterface = "enp14s0";
    forwardPorts = [{
      destination = "192.168.100.10:${toString clawdWebhookPort}";
      proto = "tcp";
      sourcePort = clawdWebhookPort;
    }];
  };

  sops.secrets.nextcloud_talk_bot_secret = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = "flakm";
    mode = "0400";
  };

  sops.secrets.github_token = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = "flakm";
    mode = "0400";
  };

  sops.secrets.jira_coralogix_token = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = "flakm";
    mode = "0400";
  };

  system.activationScripts.clawd-secrets = {
    deps = [ "setupSecrets" ];
    text = ''
      install -d -m 0555 -o root -g root /run/clawd-secrets
      install -m 0444 -o root -g root \
        ${config.sops.secrets.nextcloud_talk_bot_secret.path} \
        /run/clawd-secrets/nextcloud_talk_bot_secret
      install -m 0444 -o root -g root \
        ${config.sops.secrets.github_token.path} \
        /run/clawd-secrets/github_token
      install -m 0444 -o root -g root \
        ${config.sops.secrets.jira_coralogix_token.path} \
        /run/clawd-secrets/jira_coralogix_token
    '';
  };

  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  # Resolve the VM by hostname on the host.
  networking.hosts."192.168.100.10" = [ "clawd" "clawd.local" ];

  # SSH shortcut: `ssh clawd` → admin@192.168.100.10
  programs.ssh.extraConfig = ''
    Host clawd clawd.local
      HostName 192.168.100.10
      User flakm
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
      LogLevel ERROR
  '';

  # Mount the ZFS dataset that holds the VM's data volume before the VM starts.
  # Dataset: rpool/nixos/microvms/clawd (mountpoint=legacy)
  # Create once: zfs create -o mountpoint=legacy rpool/nixos/microvms/clawd
  fileSystems."/var/lib/microvms/clawd" = {
    device = "rpool/nixos/microvms/clawd";
    fsType = "zfs";
    options = [ "X-mount.mkdir" "noatime" "nofail" ];
  };

  # Ensure the VM waits for the ZFS mount and sops secrets; prevent rate-limit lockout.
  systemd.services."microvm@clawd" = {
    after = [ "var-lib-microvms-clawd.mount" "sops-install-secrets.service" "network-addresses-microbr0.service" ];
    requires = [ "var-lib-microvms-clawd.mount" "network-addresses-microbr0.service" ];
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      ExecStartPre = [ "${pkgs.coreutils}/bin/sleep 2" ];
      CPUQuota = "200%";
      MemoryMax = "5G";
    };
  };

  environment.systemPackages = with pkgs; [ iftop tcpdump nftables ];

  microvm.vms.clawd = {
    pkgs = pkgs;
    config = {
      imports = [
        ../../microvms/clawd/default.nix
        inputs.nix-openclaw.nixosModules.openclaw-gateway
      ];
      microvm.shares = [ {
        proto = "9p";
        tag = "host-secrets";
        source = "/run/clawd-secrets";
        mountPoint = "/run/host-secrets";
        readOnly = true;
      } ];
    };
  };
}
