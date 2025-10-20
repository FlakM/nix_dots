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



    completionInit = "autoload -U compinit && compinit -i";

    autosuggestion.enable = true;
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
      k = "kubectl";
    };


    initExtra = ''
      # Enable bracketed paste mode for safe multiline pasting
      autoload -Uz bracketed-paste-magic
      zle -N bracketed-paste bracketed-paste-magic

      # home end
      bindkey  "^[[H"   beginning-of-line
      bindkey  "^[[F"   end-of-line
      # ctrl rigtArrow ctrl left arrow
      bindkey  "^[[1;5C" forward-word
      bindkey  "^[[1;5D" backward-word
      bindkey  "^[[1;3C" forward-word
      bindkey  "^[[1;eD" backward-word

      export PKG_CONFIG_PATH="${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.oniguruma.dev}/lib/pkgconfig:$PKG_CONFIG_PATH"
      export PKG="/lib/pkgconfig"

      function changelog() {
        latest_tag=$(git tag --sort=taggerdate | tail -1)
        new_version=$(echo $latest_tag | awk -F. '{$NF = $NF + 1;} 1' OFS=.)
        git-cliff "$latest_tag..HEAD" --tag "$new_version"
      }
      

      function my_init() {
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
      }



      function zvm_config() {
        ZVM_LAZY_KEYBINDINGS=false
        ZVM_SYSTEM_CLIPBOARD_ENABLED=true
        ZVM_CLIPBOARD_COPY_CMD='wl-copy'
        ZVM_CLIPBOARD_PASTE_CMD='wl-paste -n'
      }

      function zvm_after_init() {
        my_init

        # Create safe paste widget
        function safe-paste-widget() {
          local content
          content=$(wl-paste 2>/dev/null) || return
          # Replace with literal insertion without execution
          LBUFFER="$LBUFFER$content"
          zle redisplay
        }
        zle -N safe-paste-widget

        # Bind Alt+Shift+V to safe paste
        bindkey -M viins '^[[1;4V' safe-paste-widget  # Alt+Shift+V
        bindkey -M vicmd '^[[1;4V' safe-paste-widget

        # Try to make Shift+Insert safer by using our custom widget
        bindkey -M viins '^[[2;2~' safe-paste-widget  # Shift+Insert
        bindkey -M vicmd '^[[2;2~' safe-paste-widget

        # Enhanced bracketed paste mode for safe multiline pasting
        autoload -Uz bracketed-paste-magic
        zle -N bracketed-paste bracketed-paste-magic
        bindkey -M viins '^[[200~' bracketed-paste-magic
        bindkey -M vicmd '^[[200~' bracketed-paste-magic
      }
      source ${pkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh
      


      source ~/.zshrc_local 2>/dev/null || true
      source ~/.jfrog.env 2>/dev/null || true

      # silent import if it not exists
      source ~/.sdkman/bin/sdkman-init.sh 2>/dev/null || true


      # for home.sessionVariables to work
      # see @ https://discourse.nixos.org/t/home-manager-doesnt-seem-to-recognize-sessionvariables/8488/7
      . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
    '';


    #       initExtraBeforeCompInit = ''
    #    fpath+=("${config.home.homeDirectory}"/share/zsh/site-functions "${config.home.homeDirectory}"/share/zsh/$ZSH_VERSION/functions "${config.home.homeDirectory}"/share/zsh/vendor-completions)
    #  '';
  };

  #home.file."${config.home.homeDirectory}/.cargo/bin/rust-analyzer".source = config.lib.file.mkOutOfStoreSymlink ./rust-analyzer-shim;

}
