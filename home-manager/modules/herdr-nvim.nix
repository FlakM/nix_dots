{ config, lib, pkgs, llm-agents-pkgs, ... }:
let
  version = "1.1.0";
  src = pkgs.fetchFromGitHub {
    owner = "ChmaraX";
    repo = "herdr-nvim";
    rev = "v${version}";
    hash = "sha256-q44Qt73XzNNipwF3hHr3Hzg0EReC3tz2bKB/l4ZBqiE=";
  };
  bin = pkgs.rustPlatform.buildRustPackage {
    pname = "herdr-nvim";
    inherit version src;
    cargoHash = "sha256-pImtQ1YiM47VvA8u9ER/lXtDVsZhQy38fkCbzmT/gc4=";
    doCheck = false;
  };
  # herdr plugin root: manifest + lua, with bin/herdr-nvim where the manifest expects it
  plugin = pkgs.runCommand "herdr-nvim-plugin-${version}" { } ''
    mkdir -p $out/bin
    cp -r ${src}/herdr-plugin.toml ${src}/lua ${src}/plugin ${src}/doc $out/
    # copy, not symlink: herdr-nvim finds its lua via current_exe()/..
    cp ${bin}/bin/herdr-nvim $out/bin/herdr-nvim
  '';
  vimPlugin = pkgs.vimUtils.buildVimPlugin {
    pname = "herdr-nvim";
    inherit version src;
  };
in
{
  home.packages = [ bin ];

  programs.neovim.plugins = [
    {
      plugin = vimPlugin;
      type = "lua";
      config = ''require("herdr-nvim").setup({})'';
    }
  ];

  # herdr stores the canonical plugin path, so relink whenever the store path changes
  home.activation.herdrNvimPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    herdr=${llm-agents-pkgs.herdr}/bin/herdr
    root=$($herdr plugin list --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.result.plugins[] | select(.plugin_id == "chmarax.herdr-nvim") | .plugin_root' || true)
    if [ "$root" != "${plugin}" ]; then
      [ -n "$root" ] && run $herdr plugin unlink chmarax.herdr-nvim >/dev/null
      run $herdr plugin link ${plugin} >/dev/null
    fi
  '';

  xdg.configFile."herdr-nvim/config.toml".text = ''
    [sidebar]
    nvim_bin = "${config.programs.neovim.finalPackage}/bin/nvim"
  '';
}
