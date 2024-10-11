{ pkgs, ... }:
{
  # This is required so that pod can reach the API server (running on port 6443 by default)
  services.k3s.enable = true;

  networking.firewall.trustedInterfaces = [ "cni+" ];

  virtualisation.containerd.enable = true;
  #virtualisation.containerd.settings = {
  #  version = 2;
  #  plugins."io.containerd.grpc.v1.cri" = {
  #    cni.conf_dir = "/var/lib/rancher/k3s/agent/etc/cni/net.d/";
  #    # FIXME: upstream
  #    cni.bin_dir = "${pkgs.runCommand "cni-bin-dir" {} ''
  #      mkdir -p $out
  #      ln -sf ${pkgs.cni-plugins}/bin/* ${pkgs.cni-plugin-flannel}/bin/* $out
  #    ''}";
  #  };
  #};

  environment.systemPackages = with pkgs; [
    (pkgs.writeShellScriptBin "k3s-reset-node" (builtins.readFile ./k3s-reset-node))
    k3s
    kubernetes-helm
    kubectl
    yamlfmt
  ];

  systemd.services.k3s = {
    wants = [ "containerd.service" ];
    after = [ "containerd.service" ];
  };

  systemd.services.containerd.serviceConfig = {
    ExecStartPre = [
      "-${pkgs.zfs}/bin/zfs create -o mountpoint=/var/lib/containerd/io.containerd.snapshotter.v1.zfs rpool/containerd"
    ];
  };

}
