{ config, pkgs, inputs, ... }:

{
  sops.secrets.librus-env = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = config.services.librus-notifications.user;
    group = config.services.librus-notifications.group;
  };

  services.librus-notifications = {
    enable = true;
    package = inputs.librus-notifications.packages.x86_64-linux.default;
    environmentFile = config.sops.secrets.librus-env.path;
    schedule = [ "*:0/10" ];
    persistent = true;
  };
}
