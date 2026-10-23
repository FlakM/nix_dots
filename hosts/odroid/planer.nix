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
  };

  sops.secrets.planer_env = {
    owner = "root";
    group = "planer";
    mode = "0440";
    restartUnits = [ "planer.service" ];
  };
}
