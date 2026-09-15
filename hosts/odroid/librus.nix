{ config, pkgs, inputs, lib, ... }:

let
  librusPackage = inputs.librus-notifications.packages.x86_64-linux.default.overrideAttrs (oldAttrs: {
    postPatch = (oldAttrs.postPatch or "") + ''
      substituteInPlace rust/openai.rs \
        --replace-fail "1A" "2A" \
        --replace-fail "klasy 1" "klasy 2" \
        --replace-fail "1 klasy" "2 klasy" \
        --replace-fail "            temperature: 0.3," "" \
        --replace-fail "    temperature: f32," ""
      substituteInPlace rust/email.rs --replace-fail "1A" "2A"
    '';
  });

  # Wrapper script that sources secrets and runs librus-test
  librusTestWrapper = pkgs.writeShellScriptBin "librus-test" ''
    # librus-test - Test the Librus notification pipeline
    #
    # Usage:
    #   librus-test <email>
    #   librus-test --type=message me@flakm.com
    #   librus-test --dry-run me@flakm.com
    #
    # Options:
    #   --type=TYPE  Item type: message, announcement, grade, event
    #   --dry-run    Don't send email, just analyze
    #   --help       Show help

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

    exec ${librusPackage}/bin/librus-notifications "$@"
  '';
in
{
  sops.secrets.librus-env = {
    sopsFile = ../../secrets/secrets.yaml;
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
    schedule = [ "*:0/10" ];
    persistent = true;
  };

  systemd.services.librus-notifications.environment.OPENAI_MODEL = "gpt-5.6-sol";
}
