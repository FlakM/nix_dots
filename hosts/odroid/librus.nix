{ config, pkgs, inputs, lib, ... }:

let
  librusPackage = inputs.librus-notifications.packages.x86_64-linux.default;

  librusTestWrapper = pkgs.writeShellScriptBin "librus-test" ''
    SECRETS_FILE="${config.sops.secrets.librus-env.path}"

    if [[ ! -r "$SECRETS_FILE" ]]; then
      echo "Error: Cannot read secrets at $SECRETS_FILE"
      echo "Make sure you're in the librus-notifications group"
      exit 1
    fi

    # Export environment variables from secrets file
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      key="''${line%%=*}"
      value="''${line#*=}"
      export "$key=$value"
    done < "$SECRETS_FILE"

    exec ${librusPackage}/bin/librus-notifications --check "$@"
  '';
in
{
  sops.secrets.librus-env = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = config.services.librus-notifications.user;
    group = config.services.librus-notifications.group;
    mode = "0440";
  };

  sops.secrets.librus-google-calendar = {
    sopsFile = ../../secrets/librus-google-calendar.yaml;
    owner = config.services.librus-notifications.user;
    group = config.services.librus-notifications.group;
    mode = "0440";
  };

  users.users.flakm.extraGroups = lib.mkAfter [ "librus-notifications" ];

  environment.systemPackages = [ librusTestWrapper ];

  services.librus-notifications = {
    enable = true;
    package = librusPackage;
    environmentFile = config.sops.secrets.librus-env.path;
    calendarId = "iq7mg01s5t9m9u0tcm48d36718@group.calendar.google.com";
    calendarCredentialsFile = config.sops.secrets.librus-google-calendar.path;
    schedule = [ "*:0/10" ];
    persistent = true;
  };

  systemd.services.librus-notifications.environment.OPENAI_MODEL = "gpt-6.1-sol";
}
