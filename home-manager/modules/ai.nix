{ config, pkgs, lib, llm-agents-pkgs, inputs, ... }:
let
  catchupVersion = "0.5.1";
  catchupPlatform = {
    x86_64-linux = {
      asset = "linux_amd64";
      hash = "sha256-MpswY3zVDwGGodYXJgkpjrC2uvljdwn03VYgOLI5JO8=";
    };
    aarch64-linux = {
      asset = "linux_arm64";
      hash = "sha256-W42jhxWnC7OMvdV0JZt7C48fAMNy/kspE9ELbE5QAeE=";
    };
    x86_64-darwin = {
      asset = "darwin_amd64";
      hash = "sha256-i3e93nrxjwqaF3F79TSogjCPSE3vmQhwYH/i4txItFE=";
    };
    aarch64-darwin = {
      asset = "darwin_arm64";
      hash = "sha256-76MJ/Wwh56FOZq3oY9eFOgAuGRmVsdBo3MiCk8dcGCc=";
    };
  }.${pkgs.stdenv.hostPlatform.system};
  catchup = pkgs.stdenvNoCC.mkDerivation {
    pname = "catchup";
    version = catchupVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/wilbeibi/catchup/releases/download/v${catchupVersion}/catchup_${catchupPlatform.asset}.tar.gz";
      hash = catchupPlatform.hash;
    };
    sourceRoot = ".";
    installPhase = ''
      install -Dm755 catchup "$out/bin/catchup"
    '';
  };
  catchupSkillSource = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/wilbeibi/catchup/v${catchupVersion}/SKILL.md";
    hash = "sha256-Cpkz4qZDNoaBNbNMmmEKFsEXziy1gMehWrIbmC5hlxY=";
  };
  catchupSkill = pkgs.runCommand "catchup-skill-${catchupVersion}" { } ''
    sed '4i version: ${catchupVersion}' ${catchupSkillSource} > "$out"
  '';
  cxSkills = inputs.cx-cli.packages.${pkgs.stdenv.hostPlatform.system}.skills;
  peonPingEnabled = lib.attrByPath [ "programs" "peon-ping" "enable" ] false config;
  cxSkillFiles = lib.mapAttrs'
    (name: _: lib.nameValuePair ".claude/skills/${name}" { force = true; source = "${cxSkills}/${name}"; })
    (lib.filterAttrs (_: t: t == "directory") (builtins.readDir cxSkills));

  # coralogix-private only ships linux packages; skip on darwin (work/air).
  hasCxPrivate =
    inputs ? coralogix-private
    && inputs.coralogix-private.packages ? ${pkgs.stdenv.hostPlatform.system};
  cxPrivateSkills =
    if hasCxPrivate then inputs.coralogix-private.packages.${pkgs.stdenv.hostPlatform.system}.skills else null;
  cxPrivateSkillFiles =
    if hasCxPrivate then
      lib.mapAttrs'
        (name: _: lib.nameValuePair ".claude/skills/${name}" { force = true; source = "${cxPrivateSkills}/${name}"; })
        (lib.filterAttrs (_: t: t == "directory") (builtins.readDir cxPrivateSkills))
    else { };
in
{
  home.packages = with llm-agents-pkgs; [
    claude-code
    codex
    ccusage
    opencode
    amp
    catchup
    inputs.cx-cli.packages.${pkgs.stdenv.hostPlatform.system}.default
  ] ++ lib.optional hasCxPrivate inputs.coralogix-private.packages.${pkgs.stdenv.hostPlatform.system}.aaa-help;

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
    ".claude/skills/catchup/SKILL.md" = {
      force = true;
      source = catchupSkill;
    };
  } // builtins.listToAttrs (map
    (name: {
      name = ".claude/skills/${name}";
      value = { force = true; source = ./claude/skills/${name}; };
    })
    (builtins.attrNames (builtins.readDir ./claude/skills)))
  // cxSkillFiles
  // cxPrivateSkillFiles;

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
            "npx"
            "-y"
            "chrome-devtools-mcp@latest"
            "--executablePath"
            "${pkgs.google-chrome}/bin/google-chrome-stable"
          ];
        };
      };
      plugin = [
        "opencode-gemini-auth@latest"
        "opencode-handoff@0.5.0"
      ] ++ lib.optional peonPingEnabled "./plugins/peon-ping.ts";
      provider.google.options.projectId = "904216483369";
    };
  };
}
