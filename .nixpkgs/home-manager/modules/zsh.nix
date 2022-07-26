{ config, pkgs, pkgsUnstable, libs, ... }:
{

  home.packages = with pkgs; [
    zsh
  ];


  programs.zsh = {
    enable = true;
    autocd = true;

    enableAutosuggestions = true;
    enableCompletion = true;
    enableSyntaxHighlighting = true;

    zplug = {
      enable = true;
      plugins = [
        { name = "agkozak/zsh-z"; } # smart CD
        { name = "jeffreytse/zsh-vi-mode"; } # vi mode <3
        { name = "zsh-users/zsh-autosuggestions"; } # Simple plugin installation
        { name = "unixorn/fzf-zsh-plugin"; }
        { name = "romkatv/powerlevel10k"; tags = [ as:theme depth:1 ]; } # Installations with additional options. For the list of options, please refer to Zplug README.
      ];
    };
    shellAliases = {
      ls = "ls --color";
      ll = "ls -l";
      update = "sudo nixos-rebuild switch";
      config = "git --git-dir=$HOME/.cfg/ --work-tree=$HOME";
      vim = "nvim";
      vi = "vi";
      #rust-analyzer= "rustup run stable rust-analyzer";
    };

    initExtra = ''
      source ~/.p10k.zsh
      # home end
      bindkey  "^[[H"   beginning-of-line
      bindkey  "^[[F"   end-of-line
      # ctrl rigtArrow ctrl left arrow
      bindkey  "^[[1;5C" forward-word
      bindkey  "^[[1;5D" backward-word
      bindkey  "^[[1;3C" forward-word
      bindkey  "^[[1;eD" backward-word
      # rd is rancher desktop
      # zsh is in front of path as otherwise on darwin /usr/bin/zsh is picked earlier
      # cargo is here to allow cargo install $crate
      export PATH="${pkgs.zsh}/bin/zsh:${config.home.homeDirectory}/.rd/bin:${config.home.homeDirectory}/.cargo/bin:$PATH"
      export JAVA_HOME="${pkgs.jdk.home}/bin/.."
      export PKG_CONFIG_PATH="${pkgs.openssl.dev}/lib/pkgconfig"
      export PKG="/lib/pkgconfig"
    '';
    #       initExtraBeforeCompInit = ''
    #    fpath+=("${config.home.homeDirectory}"/share/zsh/site-functions "${config.home.homeDirectory}"/share/zsh/$ZSH_VERSION/functions "${config.home.homeDirectory}"/share/zsh/vendor-completions)
    #  '';
  };

  #home.file."${config.home.homeDirectory}/.cargo/bin/rust-analyzer".source = config.lib.file.mkOutOfStoreSymlink ./rust-analyzer-shim;

}
