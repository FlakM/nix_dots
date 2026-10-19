{ config, pkgs, ... }:
let
  vikunja-cli = pkgs.callPackage ../../packages/vikunja-cli.nix { };
  vikunja = pkgs.writeShellScriptBin "vikunja-cli" ''
    export VIKUNJA_URL="https://tasks.house.flakm.com"
    export VIKUNJA_USERNAME="$(<${config.sops.secrets.vikunja_username.path})"
    export VIKUNJA_PASSWORD="$(<${config.sops.secrets.vikunja_password.path})"
    exec ${vikunja-cli}/bin/vikunja-cli "$@"
  '';
  vikunjaLib = builtins.readFile ./vikunja/lib.sh;
  vikunjaEnv = {
    VIKUNJA_URL = "https://tasks.house.flakm.com";
    VIKUNJA_USERNAME_FILE = config.sops.secrets.vikunja_username.path;
    VIKUNJA_PASSWORD_FILE = config.sops.secrets.vikunja_password.path;
    VIKUNJA_TZ = "Europe/Warsaw";
    VIKUNJA_FOCUS_LABEL = "doing";
    # week: the personal "this week" plan, work: the urgent work queue
    VIKUNJA_WEEK_PROJECT = "27";
    VIKUNJA_WORK_PROJECT = "26";
  };
  # Project access (who can see/edit which project). vikunja-cli 1.0.0 speaks the
  # pre-2.0 membership API, so this talks to the API directly.
  vikunja-acl = pkgs.writeShellApplication {
    name = "vikunja-acl";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.jq ];
    runtimeEnv = vikunjaEnv;
    text = vikunjaLib + builtins.readFile ./vikunja/vikunja-acl.sh;
  };
  # Task mutations that survive Vikunja's full-replace update: read, patch, write
  # the whole writable field set (vikunja-cli tasks update blanks what you omit).
  vikunja-task = pkgs.writeShellApplication {
    name = "vikunja-task";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.jq ];
    runtimeEnv = vikunjaEnv;
    # jq programs legitimately carry $vars inside single quotes
    excludeShellChecks = [ "SC2016" ];
    text = vikunjaLib + builtins.readFile ./vikunja/vikunja-task.sh;
  };
  # Edit a task description in vim and write it back (the panel's `e` key).
  vikunja-edit-description = pkgs.writeShellApplication {
    name = "vikunja-edit-description";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.jq pkgs.kitty pkgs.vim ];
    runtimeEnv = vikunjaEnv;
    text = vikunjaLib + builtins.readFile ./vikunja/vikunja-edit-description.sh;
  };
  # Backend for the QuickShell task dashboard: list + the mutations the panel
  # offers (complete, reopen, priority, due date).
  quickshell-vikunja = pkgs.writeShellApplication {
    name = "quickshell-vikunja";
    runtimeInputs = [ vikunja vikunja-task pkgs.coreutils pkgs.jq ];
    runtimeEnv = vikunjaEnv;
    # jq programs legitimately carry $vars inside single quotes
    excludeShellChecks = [ "SC2016" ];
    text = builtins.readFile ./vikunja/quickshell-vikunja.sh;
  };
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

  home.packages = [ vikunja vikunja-acl vikunja-task vikunja-edit-description quickshell-vikunja ];

  home.file.".claude/skills/vikunja-cli" = {
    force = true;
    source = "${skillSource}/.claude/skills/vikunja-cli";
  };
}
