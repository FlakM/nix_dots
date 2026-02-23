{ llm-agents-pkgs, ... }:

{
  home.packages = with llm-agents-pkgs; [
    claude-code
    codex
    gemini-cli
    ccusage
    ccusage-codex
    opencode
  ];
}
