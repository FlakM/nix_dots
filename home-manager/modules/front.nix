{ config, pkgs, pkgs-unstable, libs, lib, ... }:
{
  home.packages = with pkgs; [
    pnpm
    fnm
  ];

  # fnm shell hook — auto-uses the version from .nvmrc when cd-ing into a
  # repo. Lets us keep nixpkgs `nodejs_24` (24.14.1, has the sass-embedded
  # EPIPE bug) for everything else and pin a working version (e.g. 24.13.0)
  # per-project via `fnm install 24.13.0` + the project's .nvmrc.
  programs.zsh.initContent = lib.mkAfter ''
    if command -v fnm >/dev/null 2>&1; then
      eval "$(fnm env --use-on-cd --shell zsh)"
    fi
  '';

  home.sessionVariables = {
    LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.libuuid ] + "\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}";
  };
}
