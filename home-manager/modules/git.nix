{ config, pkgs, pkgs-unstable, lib, ... }:
{

  home.packages = with pkgs; [
    git
    git-crypt
    pkgs-unstable.delta
    as-tree
  ];

  programs.git = {
    enable = true;
    userName = "FlakM";
    userEmail = "maciej.jan.flak@gmail.com";
    # mac os is messed up...
    signing = {
      key = "AD7821B8";
      signByDefault = true;
    };

    #delta = {
    #  enable = true;
    #  package = pkgs-unstable.delta;
    #};
    lfs.enable = true;

    ignores = [
      ".metals"
      ".bloop"
      "out"
      ".history/"
      "**/project/metals.sbt"
      ".idea/"
      ".vscode/settings.json"
      ".bloop/"
      ".bsp/"
      ".scala-build/"
      ".direnv/"
      ".flake_dir/"
      "result"
      ".local_ignore"
    ];

    extraConfig = {
      pull = { ff = "only"; };
      init.defaultBranch = "main";
      core.pager = "${pkgs-unstable.delta}/bin/delta --color-only --features ${"\$\(cat ~/.config/delta/theme 2>/dev/null || echo dark-mode\)"}";
      delta = {
        navigate = true;
        "dark-mode" = {
          light = false;
          syntax-theme = "TwoDark";
        };
        "light-mode" = {
          light = true;
          syntax-theme = "GitHub";
        };
      };
      interactive.diffFilter = "${pkgs-unstable.delta}/bin/delta --color-only";
      merge.conflictStyle = "diff3";
      diff.colorMoved = "default";
      merge.conflictstyle = "diff3";
    };


    aliases = {
      # those two aliases are here to allow rebase when flake files are assumed unchanged
      # otherwise the rebase would fail even the git status doesn't show anything to be changed
      # the idea to keep the flake.* added but not commited comes from link:
      # https://discourse.nixos.org/t/can-i-use-flakes-within-a-git-repo-without-committing-flake-nix/18196/4
      "flake-hide" = "!git update-index --no-assume-unchanged flake* || true &&  mkdir -p .flake_dir && mv flake* .flake_dir/";
      "flake-unhide" = "!mv .flake_dir/flake* . || true && git add --intent-to-add flake.* || true && git update-index --assume-unchanged flake* || true";
    };
  };
}
