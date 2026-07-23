{ config, pkgs, ... }:
let
  vikunja-cli = pkgs.callPackage ../../packages/vikunja-cli.nix { };
  vikunja = pkgs.writeShellScriptBin "vikunja-cli" ''
    export VIKUNJA_URL="https://tasks.house.flakm.com"
    export VIKUNJA_USERNAME="$(<${config.sops.secrets.vikunja_username.path})"
    export VIKUNJA_PASSWORD="$(<${config.sops.secrets.vikunja_password.path})"
    exec ${vikunja-cli}/bin/vikunja-cli "$@"
  '';
  skillSource = pkgs.fetchFromGitHub {
    owner = "jo-nike";
    repo = "vikunja-cli";
    rev = "v1.0.0";
    hash = "sha256-Rv7i073TRug5n5x0f2DMIR4Z0NvHreYj2YcPj060pXU=";
  };
in
{
  sops.secrets = {
    vikunja_username = { };
    vikunja_password = { };
  };

  home.packages = [ vikunja ];

  home.file.".claude/skills/vikunja-cli" = {
    force = true;
    source = "${skillSource}/.claude/skills/vikunja-cli";
  };
}
