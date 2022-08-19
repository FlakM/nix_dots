{ config, pkgs, pkgsUnstable, libs, ... }:
{

  home.packages = with pkgs; [
    git
  ];

  programs.git = {
    enable = true;
    userName  = "FlakM";
    userEmail = "maciej.jan.flak@gmail.com";
    # mac os is messed up...
    signing = {
       key = "AD7821B8";
       signByDefault = true;
    };

    delta.enable = true;
    lfs.enable = true;

    ignores = [
      ".metals"
      ".bloop"
      "out"
      ".envrc"
      ".history/"
      "**/project/metals.sbt"
      ".idea/"
      ".vscode/settings.json"
      ".bloop/"
      ".bsp/"
      ".scala-build/"
      ".direnv/"
      ".flake_dir/"
    ];
    
    extraConfig = {
      pull = { ff = "only"; };
      init.defaultBranch = "main";
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
