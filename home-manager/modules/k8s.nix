{ pkgs, config, lib, pkgs-master, pkgs-unstable, ... }: {

  home.packages = with pkgs; [
    teleport_17
    kubectx
    kubectl
  ];

  programs.k9s = {
    enable = true;

    # 1) Define your new “modern-dark” skin inline
    skins = {
      # The attribute name “modern-dark” becomes the file ~/.config/k9s/skins/modern-dark.yaml
      modern-dark = {
        k9s = {
          body = {
            fgColor = "white";
            bgColor = "#1F1F2E"; # deep charcoal
            logoColor = "cyan";
          };
          info = {
            fgColor = "lightgray";
            sectionColor = "slategray";
          };
          frame = {
            border = {
              fgColor = "gray";
              focusColor = "lightgray";
            };
            menu = {
              fgColor = "white";
              keyColor = "cyan";
              numKeyColor = "yellow";
            };
            crumbs = {
              fgColor = "white";
              bgColor = "#2C2F45";
              activeColor = "magenta";
            };
            status = {
              newColor = "green";
              modifyColor = "orange";
              addColor = "cyan";
              errorColor = "red";
              highlightColor = "magenta";
              killColor = "magenta";
              completedColor = "gray";
            };
            title = {
              fgColor = "white";
              bgColor = "#3B3E50";
              highlightColor = "cyan";
              counterColor = "yellow";
              filterColor = "lightgray";
            };
          };
          views = {
            table = {
              fgColor = "white";
              bgColor = "#1F1F2E";
              cursorColor = "cyan";
              header = {
                fgColor = "white";
                bgColor = "#2C2F45";
                sorterColor = "yellow";
              };
            };
            yaml = {
              keyColor = "cyan";
              colonColor = "white";
              valueColor = "lightgreen";
            };
            logs = {
              fgColor = "white";
              bgColor = "black";
            };
          };
        };
      };
    };

    # 2) Tell K9s to use it globally
    settings = {
      k9s = {
        ui = {
          skin = "modern-dark";
        };
      };
    };
  };
}
