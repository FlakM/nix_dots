{
  lib,
  stdenv,
  python3,
  makeWrapper,
  libnotify,
}:

# Three entry points over one pure-Python source tree.  Dependencies are
# limited to httpx (HTTP/SSE) and textual (TUI); everything else is stdlib.
stdenv.mkDerivation {
  pname = "hermes-client";
  version = "1.0.0";

  src = ./hermes-client;

  nativeBuildInputs = [ makeWrapper ];

  # The tests are offline (httpx.MockTransport, temp cache dirs).
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    PYTHONPATH=$PWD ${python3.withPackages (ps: [ ps.httpx ps.textual ])}/bin/python3 \
      -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/hermes-client/hermes_client $out/bin
    cp hermes_client/*.py $out/lib/hermes-client/hermes_client/

    makeWrapper ${python3.withPackages (ps: [ ps.httpx ps.textual ])}/bin/python3 $out/bin/hermes \
      --add-flags "-m hermes_client.cli" \
      --prefix PYTHONPATH : "$out/lib/hermes-client" \
      --prefix PATH : "${libnotify}/bin"

    makeWrapper ${python3.withPackages (ps: [ ps.httpx ps.textual ])}/bin/python3 $out/bin/hermes-tui \
      --add-flags "-m hermes_client.tui" \
      --prefix PYTHONPATH : "$out/lib/hermes-client" \
      --prefix PATH : "${libnotify}/bin"

    makeWrapper ${python3.withPackages (ps: [ ps.httpx ps.textual ])}/bin/python3 $out/bin/hermes-bridge \
      --add-flags "-m hermes_client.bridge" \
      --prefix PYTHONPATH : "$out/lib/hermes-client" \
      --prefix PATH : "${libnotify}/bin"

    runHook postInstall
  '';

  meta = {
    description = "Hermes desktop clients: CLI, textual TUI and notification bridge";
    license = lib.licenses.mit;
    mainProgram = "hermes";
    platforms = lib.platforms.unix;
  };
}
