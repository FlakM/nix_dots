{ config, pkgs, ... }:
{
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      gcloud = {
        format = "on [$symbol$account(@$domain)(\($project\))]($style) ";
        disabled = true;
      };

      aws = {
        disabled = true;
        symbol = "  ";
      };
      buf = {
        symbol = " ";
      };
      c = {
        symbol = " ";
      };
      dart = {
        symbol = " ";
      };
      directory = {
        read_only = " 󰌾";
      };
      docker_context = {
        symbol = " ";
      };
      git_branch = {
        symbol = " ";
      };
      golang = {
        symbol = " ";
      };
      guix_shell = {
        symbol = " ";
      };
      haskell = {
        symbol = " ";
      };
      haxe = {
        symbol = " ";
      };
      hg_branch = {
        symbol = " ";
      };
      hostname = {
        ssh_only = true;
        ssh_symbol = " ";
        style = "bold red";
        format = "[$ssh_symbol$hostname]($style) on ";
      };
      java = {
        symbol = " ";
      };
      julia = {
        symbol = " ";
      };
      kotlin = {
        symbol = " ";
      };
      lua = {
        symbol = " ";
      };
      memory_usage = {
        symbol = "󰍛 ";
      };
      meson = {
        symbol = "󰔷 ";
      };
      nim = {
        symbol = "󰆥 ";
      };
      nix_shell = {
        symbol = " ";
      };
      nodejs = {
        symbol = " ";
      };
      package = {
        symbol = "󰏗 ";
      };
      perl = {
        symbol = " ";
      };
      php = {
        symbol = " ";
      };
      pijul_channel = {
        symbol = " ";
      };
      python = {
        disabled = true;
        symbol = " ";
      };
      rlang = {
        symbol = "󰟔 ";
      };
      ruby = {
        symbol = " ";
      };
      rust = {
        symbol = " ";
      };
      scala = {
        symbol = " ";
      };
      swift = {
        symbol = " ";
      };
      zig = {
        symbol = " ";
      };
      custom.calendar = {
        command = "~/.local/bin/khal-next";
        when = "test -f ~/.local/bin/khal-next";
        format = "[$symbol($output)]($style) ";
        symbol = "󰃭 ";
        style = "bold yellow";
      };

      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
        vimcmd_symbol = "[❮](bold green)";
        vimcmd_replace_one_symbol = "[❮](bold purple)";
        vimcmd_replace_symbol = "[❮](bold purple)";
        vimcmd_visual_symbol = "[❮](bold yellow)";
      };

      cmd_duration = {
        min_time = 2000;
        format = "took [$duration]($style) ";
        style = "bold yellow";
      };

      direnv = {
        disabled = false;
        format = "[$symbol$loaded]($style) ";
        symbol = "󱁤 ";
        loaded_msg = "✓";
        unloaded_msg = "✗";
        style = "bold cyan";
      };

      git_status = {
        format = "([\\[$all_status$ahead_behind\\]]($style) )";
        ahead = "⇡\${count} ";
        behind = "⇣\${count} ";
        diverged = "⇕⇡\${ahead_count}⇣\${behind_count} ";
        conflicted = "= ";
        untracked = "?\${count} ";
        stashed = "≡\${count} ";
        modified = "!\${count} ";
        staged = "+\${count} ";
        renamed = "»\${count} ";
        deleted = "✘\${count} ";
        up_to_date = "";
        style = "bold red";
      };
    };
  };
}
