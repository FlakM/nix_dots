{ lib, rustPlatform, fetchFromGitHub }:

rustPlatform.buildRustPackage {
  pname = "omada-cli";
  version = "0.1.0-unstable-2026-04-10";

  src = fetchFromGitHub {
    owner = "rhilseth";
    repo = "omada-cli";
    rev = "3a9c25ecba145451e25d61aa31d052a78d79770d";
    hash = "sha256-Cat5FUTju6hTgGlXRKlop0TekmsVRLN327UEms4/ScM=";
  };

  patches = [ ./omada-cli-auth.patch ];
  cargoHash = "sha256-xTzkP/jAxo3k7i4I/Quk304pr/iF+Gyz+8O+c4Iuje8=";

  meta = {
    description = "Dynamic CLI for the TP-Link Omada controller OpenAPI";
    homepage = "https://github.com/rhilseth/omada-cli";
    license = lib.licenses.mit;
    mainProgram = "omada";
  };
}
