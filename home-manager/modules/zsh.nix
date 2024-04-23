{ config, pkgs, ... }:
{

  home.packages = with pkgs; [
    zsh
    eza
  ];

  programs.zoxide.enable = true;

  programs.zsh = {
    enable = true;
    autocd = true;

    enableAutosuggestions = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;

    zplug = {
      enable = false;
      plugins = [
        { name = "agkozak/zsh-z"; } # smart CD
        #{ name = "jeffreytse/zsh-vi-mode"; } # vi mode <3
      ];
    };
    shellAliases = {
      ls = "eza";
      ll = "ls -l";
      vim = "nvim";
      vi = "vi";
    };


    initExtra = ''
      # home end
      bindkey  "^[[H"   beginning-of-line
      bindkey  "^[[F"   end-of-line
      # ctrl rigtArrow ctrl left arrow
      bindkey  "^[[1;5C" forward-word
      bindkey  "^[[1;5D" backward-word
      bindkey  "^[[1;3C" forward-word
      bindkey  "^[[1;eD" backward-word

      export PKG_CONFIG_PATH="${pkgs.openssl.dev}/lib/pkgconfig"
      export PKG="/lib/pkgconfig"

      function changelog() {
        latest_tag=$(git tag --sort=taggerdate | tail -1)
        new_version=$(echo $latest_tag | awk -F. '{$NF = $NF + 1;} 1' OFS=.)
        git-cliff "$latest_tag..HEAD" --tag "$new_version"
      }

      export ATUIN_NOBIND="true"
      eval "$(atuin init zsh)"

      bindkey -M viins -r '^R'
      bindkey -M viins '^R' atuin-search-viins

      bindkey -M vicmd -r '^R'
      bindkey -M vicmd '^R' atuin-search-vicmd

      bindkey '^R' atuin-search-viins

      bindkey '^[[A' atuin-up-search-viins
      bindkey '^[OA' atuin-up-search-viins
      bindkey -M viins '^[[A' atuin-up-search-viins
      bindkey -M viins '^[OA' atuin-up-search-viins
      bindkey -M vicmd '^[[A' atuin-up-search-viins
      bindkey -M vicmd '^[OA' atuin-up-search-viins

      source ~/.zshrc_local
    '';


    #       initExtraBeforeCompInit = ''
    #    fpath+=("${config.home.homeDirectory}"/share/zsh/site-functions "${config.home.homeDirectory}"/share/zsh/$ZSH_VERSION/functions "${config.home.homeDirectory}"/share/zsh/vendor-completions)
    #  '';
  };

  #home.file."${config.home.homeDirectory}/.cargo/bin/rust-analyzer".source = config.lib.file.mkOutOfStoreSymlink ./rust-analyzer-shim;

}
