{ config, inputs, pkgs, ... }:
{
  imports = [
    "${inputs.planer}/nix/module.nix"
  ];

  services.planer = {
    enable = true;
    package = inputs.planer.packages.${pkgs.stdenv.hostPlatform.system}.planer;
    domain = "plan.local";
    bind = "127.0.0.1";
    port = 8330;
    environmentFile = config.sops.secrets.planer_pc_env.path;
    createDatabase = true;
    # The OpenCode CLI needs the login user's credentials.
    runAsUser = "flakm";
    runAsGroup = "users";
    # Workstation: no TLS/domain, localhost only.
    nginx.enable = false;
  };

  sops.secrets.planer_pc_env = {
    owner = "flakm";
    group = "users";
    mode = "0400";
    restartUnits = [ "planer.service" ];
  };
}
