{ lib, rustPlatform, makeWrapper, wl-clipboard, xclip, xdg-utils }:

rustPlatform.buildRustPackage {
  pname = "hermes-tui";
  version = "2.1.0";

  src = ./hermes-tui;

  cargoLock.lockFile = ./hermes-tui/Cargo.lock;

  # Unit tests are offline: config parsing, payload normalisation, conversation
  # storage and headless rendering with ratatui's TestBackend.
  doCheck = true;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/hermes-tui \
      --prefix PATH : ${lib.makeBinPath [ wl-clipboard xclip xdg-utils ]}
  '';

  meta = {
    description = "Hermes terminal client: conversations, tracked threads and live jobs";
    longDescription = ''
      A ratatui front end for the Hermes agent HTTP API. Chat is a first-class
      tab: press n (or just type) to start a new conversation thread and keep
      the context across follow-up messages. Threads shows tracked Slack, PR
      and Jira threads, and Jobs shows agent runs and the live event feed.
    '';
    license = lib.licenses.mit;
    mainProgram = "hermes-tui";
    platforms = lib.platforms.unix;
  };
}
