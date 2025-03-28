{ config, pkgs, lib, ... }:
let
  zathura-bin = "${pkgs.zathura}/bin/zathura";
  lesspipe = let
    mkDirective = mimetype: "${mimetype}; LESSQUIET=1 ${pkgs.lesspipe}/bin/lesspipe.sh '%s'; copiousoutput";
  in
  ''
    ${mkDirective "application/*"}
    ${mkDirective "audio/*"}
  '';
  convert-to-md = "${pkgs.writeShellScriptBin "print_html2md.sh" ''
    ${pkgs.python3Packages.html2text}/bin/html2text "$1" | ${pkgs.glow}/bin/glow -
  ''}/bin/print_html2md.sh";
in
{
  home.file.".config/mailcap" = {
    #image/*; ${pkgs.kitty}/bin/kitty +kitten icat %s; copiousoutput
    #image/*; (clear && ${pkgs.kitty}/bin/kitty +kitten icat %s && read -N 1); needsterminal
    text = ''
      text/html; ${convert-to-md} '%s'; copiousoutput
      image/*; ${pkgs.kitty}/bin/kitty +kitten icat %s; needsterminal
      application/pdf; ${zathura-bin} '%s'; test=test -n "$DISPLAY"
      application/x-pdf; ${zathura-bin} '%s'; test=test -n "$DISPLAY"
    '';
  };
}
