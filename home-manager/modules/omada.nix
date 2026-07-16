{ config, lib, pkgs, ... }:

let
  omada-cli = pkgs.callPackage ../../packages/omada-cli.nix { };
  omada = pkgs.writeShellScriptBin "omada" ''
    export OMADA_BASE_URL=https://omada.house.flakm.com
    export OMADA_SSL_VERIFY=true
    export OMADA_CLIENT_ID="$(<${config.sops.secrets.omada_client_id.path})"
    export OMADA_CLIENT_SECRET="$(<${config.sops.secrets.omada_client_secret.path})"
    exec ${omada-cli}/bin/omada "$@"
  '';
in
{
  sops.secrets = {
    omada_client_id = { };
    omada_client_secret = { };
  };

  home.packages = [ omada ];

  home.file.".claude/skills/omada" = {
    force = true;
    source = ./omada-skill;
  };
  home.file.".zfunc/_omada".source = ./omada-completion.zsh;

  programs.zsh.initContent = lib.mkAfter ''
    fpath=("${config.home.homeDirectory}/.zfunc" $fpath)
    autoload -Uz _omada
    compdef _omada omada
  '';
}
