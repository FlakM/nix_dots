{ config, pkgs, llm-agents-pkgs, ... }:

{
  home.packages = with llm-agents-pkgs; [
    claude-code
    codex
    gemini-cli
    ccusage
    ccusage-codex
    opencode
    amp
    rtk
  ];

  home.file = {
    ".claude/CLAUDE.md" = {
      force = true;
      source = ./claude/CLAUDE.md;
    };
    ".claude/settings.json" = {
      force = true;
      source = ./claude/settings.json;
    };
    ".claude/commands/hypr-screenshot.md" = {
      force = true;
      source = ./claude/commands/hypr-screenshot.md;
    };
    ".claude/statusline.sh" = {
      force = true;
      source = ./claude/statusline.sh;
      executable = true;
    };
    ".claude/hooks/rtk-rewrite.sh" = {
      force = true;
      source = ./claude/hooks/rtk-rewrite.sh;
      executable = true;
    };
  } // builtins.listToAttrs (map
    (name: {
      name = ".claude/skills/${name}";
      value = { force = true; source = ./claude/skills/${name}; };
    })
    (builtins.attrNames (builtins.readDir ./claude/skills)));

  xdg.configFile."opencode/opencode.json" = {
    force = true;
    text = builtins.toJSON {
      "$schema" = "https://opencode.ai/config.json";
      permission = {
        "*" = {
          "*" = "allow";
        };
        external_directory = {
          "~/programming/**" = "allow";
          "~/Downloads/**" = "allow";
          "/tmp/**" = "allow";
          "~/.cargo/**" = "allow";
          "~/.rustup/**" = "allow";
        };
      };
      mcp = {
        attlassian = {
          type = "remote";
          url = "https://mcp.atlassian.com/v1/mcp";
          oauth = { };
        };
        coralogix-c4c = {
          type = "remote";
          url = "https://api.eu2.coralogix.com/mgmt/api/v1/mcp";
          oauth = { };
        };
        coralogix-audit = {
          type = "remote";
          url = "https://api.eu2.coralogix.com/mgmt/api/v1/mcp";
          oauth = { };
        };
        coralogix-staging = {
          type = "remote";
          url = "https://api.eu2.coralogix.com/mgmt/api/v1/mcp";
          oauth = { };
        };
        notion = {
          type = "remote";
          url = "https://mcp.notion.com/mcp";
        };
        chrome-devtools = {
          type = "local";
          command = [
            "npx" "-y" "chrome-devtools-mcp@latest"
            "--executablePath" "${pkgs.google-chrome}/bin/google-chrome-stable"
          ];
        };
      };
      plugin = [ "opencode-gemini-auth@latest" ];
      provider.google.options.projectId = "904216483369";
    };
  };
}
