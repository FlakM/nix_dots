{ config, pkgs, pkgs-unstable, lib, ... }: {

  home.packages = [
    pkgs-unstable.claude-code
    pkgs-unstable.codex
    pkgs-unstable.gemini-cli
    pkgs-unstable.cursor-cli
  ];

}
