{ config, pkgs, ... }:
{
  home.packages = with pkgs; [
    zsh
    eza
    asciinema
    asciinema-agg
  ];

  programs.zoxide.enable = true;

  programs.zsh = {
    enable = true;
    autocd = true;

    completionInit = "autoload -U compinit && compinit -i";

    autosuggestion.enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ls = "eza";
      ll = "ls -l";
      vim = "nvim";
      vi = "vi";
      k = "kubectl";
    };

    initContent = ''
      function claude() {
        local project_name
        project_name="$(basename "$PWD")"
        OTEL_RESOURCE_ATTRIBUTES="project.name=$project_name,project.path=$PWD" command claude "$@"
      }

      # home end
      bindkey  "^[[H"   beginning-of-line
      bindkey  "^[[F"   end-of-line
      # ctrl rigtArrow ctrl left arrow
      bindkey  "^[[1;5C" forward-word
      bindkey  "^[[1;5D" backward-word
      bindkey  "^[[1;3C" forward-word
      bindkey  "^[[1;3D" backward-word

      export PKG_CONFIG_PATH="${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.oniguruma.dev}/lib/pkgconfig:$PKG_CONFIG_PATH"

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
        if command -v wl-copy &>/dev/null; then
          ZVM_CLIPBOARD_COPY_CMD='wl-copy'
          ZVM_CLIPBOARD_PASTE_CMD='wl-paste -n'
        elif command -v pbcopy &>/dev/null; then
          ZVM_CLIPBOARD_COPY_CMD='pbcopy'
          ZVM_CLIPBOARD_PASTE_CMD='pbpaste'
        fi
      }

      function zvm_after_init() {
        my_init
        autoload -Uz bracketed-paste-magic
        zle -N bracketed-paste bracketed-paste-magic
      }
      source ${pkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh

      source ~/.zshrc_local 2>/dev/null || true
      source ~/.jfrog.env 2>/dev/null || true
      [ -f /run/secrets/jira_coralogix_token ] && export JIRA_API_TOKEN="$(cat /run/secrets/jira_coralogix_token)"

      source ~/.sdkman/bin/sdkman-init.sh 2>/dev/null || true
    '';
  };
}
