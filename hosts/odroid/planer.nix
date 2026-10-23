{ config, inputs, pkgs, ... }:
{
  imports = [
    "${inputs.planer}/nix/module.nix"
  ];

  services.planer = {
    enable = true;
    package = inputs.planer.packages.${pkgs.stdenv.hostPlatform.system}.planer;
    domain = "plan.house.flakm.com";
    environmentFile = config.sops.secrets.planer_env.path;
    acmeHost = "house.flakm.com";
    createDatabase = true;
    # The OpenCode CLI needs the login user's credentials.
    runAsUser = "flakm";
    runAsGroup = "users";
  };

  sops.secrets.planer_env = {
    owner = "flakm";
    group = "users";
    mode = "0400";
    restartUnits = [ "planer.service" ];
  };
}
