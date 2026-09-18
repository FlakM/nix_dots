{ config, pkgs, ... }:
let
  vikunja-cli = pkgs.callPackage ../../packages/vikunja-cli.nix { };
  vikunja = pkgs.writeShellScriptBin "vikunja-cli" ''
    export VIKUNJA_URL="https://tasks.house.flakm.com"
    export VIKUNJA_USERNAME="$(<${config.sops.secrets.vikunja_username.path})"
    export VIKUNJA_PASSWORD="$(<${config.sops.secrets.vikunja_password.path})"
    exec ${vikunja-cli}/bin/vikunja-cli "$@"
  '';
  quickshell-vikunja = pkgs.writeShellApplication {
    name = "quickshell-vikunja";
    runtimeInputs = [ vikunja pkgs.jq ];
    text = ''
      case "''${1:-list}" in
        list)
          projects=$(vikunja-cli projects list)
          tasks=$(vikunja-cli tasks list --filter "done = false" --sort due_date --order-by asc --per-page 50)
          jq -n --argjson projects "$projects" --argjson tasks "$tasks" '
            ($projects.data | map({ key: (.id | tostring), value: .title }) | from_entries) as $project_names |
            (($projects.data | map(select(.is_favorite)) | first)
              // ($projects.data | map(select(.title != "Inbox")) | first)
              // ($projects.data | first)) as $pinned_project |
            {
              tasks: [$tasks.data[] | . + { project_title: ($project_names[(.project_id | tostring)] // "Unknown") }],
              count: $tasks.result_count,
              pinned_project: $pinned_project
            }
          '
          ;;
        done)
          vikunja-cli tasks update --id "''${2:?missing task id}" --done
          ;;
        *)
          printf 'usage: quickshell-vikunja list|done TASK_ID\n' >&2
          exit 2
          ;;
      esac
    '';
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

  home.packages = [ vikunja quickshell-vikunja ];

  home.file.".claude/skills/vikunja-cli" = {
    force = true;
    source = "${skillSource}/.claude/skills/vikunja-cli";
  };
}
