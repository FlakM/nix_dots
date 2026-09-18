{ lib, fetchurl, stdenvNoCC }:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "slk";
  version = "0.20.0";

  src = fetchurl {
    url = "https://github.com/gammons/slk/releases/download/v${finalAttrs.version}/slk_${finalAttrs.version}_linux_x86_64.tar.gz";
    hash = "sha256-Pl26ZrY405fCMnZfImT4RTx2SFSRGra5rxRBRJupf6w=";
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 slk $out/bin/slk
    runHook postInstall
  '';

  meta = {
    description = "Fast Slack TUI client";
    homepage = "https://getslk.sh";
    license = lib.licenses.mit;
    mainProgram = "slk";
    platforms = [ "x86_64-linux" ];
  };
})
