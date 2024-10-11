{ config, lib, pkgs, ... }:
let kata-runtime = pkgs.callPackage ../kata-runtime { };
in let
  kata-config =
    pkgs.callPackage ./default-config.nix { kata-runtime = kata-runtime; };
  kata-runtimes =
    pkgs.callPackage ../kata-runtime/kata-runtimes.nix { kata-runtime = kata-runtime; };
  fullCNIPlugins = pkgs.buildEnv {
    name = "full-cni";
    paths = with pkgs;[
      cni-plugins
      cni-plugin-flannel
    ];
  };
in
{

  config = {
    environment.etc = {
      "kata-containers/configuration-qemu.toml".text = kata-config.qemu;
      "kata-containers/configuration-fc.toml".text = kata-config.fc;
      "kata-containers/configuration-snp.toml".text = kata-config.snp;
    };

    virtualisation.docker.enable = true;
    virtualisation.docker.daemon.settings = {
      runtimes.kata-qemu.runtimeType =
        "${kata-runtime}/bin/containerd-shim-kata-v2";
      runtimes.kata-qemu.options = {
        TypeUrl = "io.containerd.kata.v2.options";
        ConfigPath = "/etc/kata-containers/configuration-qemu.toml";
      };
      runtimes.kata-fc.runtimeType =
        "${kata-runtime}/bin/containerd-shim-kata-v2";
      runtimes.kata-fc.options = {
        TypeUrl = "io.containerd.kata.v2.options";
        ConfigPath = "/etc/kata-containers/configuration-fc.toml";
      };
      runtimes.kata-snp.runtimeType =
        "${kata-runtime}/bin/containerd-shim-kata-v2";
      runtimes.kata-snp.options = {
        TypeUrl = "io.containerd.kata.v2.options";
        ConfigPath = "/etc/kata-containers/configuration-snp.toml";
      };
    };

    virtualisation.containerd.enable = true;

    systemd.services.containerd.path = [
      "${kata-runtime}"
      "${kata-runtime}/bin"
      pkgs.lvm2
      pkgs.util-linux
      pkgs.e2fsprogs
      "${kata-runtimes}"
    ];
    # full configuration: https://github.com/containerd/containerd/blob/main/docs/cri/config.md
    # kata containers configuration https://github.com/kata-containers/kata-containers/blob/main/docs/how-to/containerd-kata.md
    virtualisation.containerd.settings = {
      plugins."io.containerd.grpc.v1.cri" = {
        containerd =
          {
            default_runtime_name = "runc";

            runtimes = {
              kata = {
                runtime_type = "io.containerd.kata.v2";
                privileged_without_host_devices = true;
                pod_annotations = [ "io.katacontainers.*" ];
                container_annotations = [ "io.katacontainers.*" ];
                options = {
                  ConfigPath = "/etc/kata-containers/configuration-qemu.toml";
                };
              };

              runc = {
                privileged_without_host_devices = false;
                runtime_type = "io.containerd.runc.v2";
                options = {
                  BinaryName = "";
                  CriuImagePath = "";
                  CriuPath = "";
                  CriuWorkPath = "";
                  IoGid = 0;
                };
              };
            };
          };

        cni = {
          bin_dir = "${fullCNIPlugins}/bin";
        };

      };
    };


    #plugins.devmapper = {
    #  pool_name = "devpool";
    #  root_path = "/var/lib/containerd/devmapper";
    #  base_image_size = "10GB";
    #  discard_blocks = true;
    #};
  };

}
