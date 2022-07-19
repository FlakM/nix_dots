{ config, pkgs, pkgsUnstable, libs, ... }:
{

  # https://github.com/nix-community/nix-direnv#via-home-manager
  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;
  
  
  home.packages = with pkgs; [
     jq
     wget
     curl
     git
     unzip
     zip

     xclip

     bat
     fd
     ripgrep
     fzf
     delta
     htop
     timewarrior
  ] ++ lib.optionals stdenv.isDarwin [
    coreutils # provides `dd` with --status=progress
  ] ++ lib.optionals stdenv.isLinux [
    iputils # provides `ping`, `ifconfig`, ...

    libuuid # `uuidgen` (already pre-installed on mac)
  ];

  programs.tmux = {
    enable = true;
    clock24 = true;
  };

  programs.dircolors = {
    enable = true;
  };

  programs.zsh = {
       enable = true;
       autocd = true;
       enableAutosuggestions = true;
       enableCompletion = true;

       zplug = {
         enable = true;
         plugins = [
           { name = "agkozak/zsh-z"; } # smart CD
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
       '';
     };  

  home.file."~/.p10k.zsh".source = config.lib.file.mkOutOfStoreSymlink ./home-manager/modules/.p10k.zsh;

  programs.git = {
    enable = true;
    userName  = "FlakM";
    userEmail = "maciej.jan.flak@gmail.com";
    signing = {
       key = "AD7821B8";
       signByDefault = true;
    };
  };

  programs.alacritty = {
    enable = true;
    settings = {


      window.padding = {
        x = 2;
        y = 2;
      };

      shell.program = "${pkgs.zsh}/bin/zsh";

      cursor.style = "Beam";

    };
  };

}
