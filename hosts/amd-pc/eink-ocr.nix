{ pkgs, pkgs-unstable, ... }:

let
  runtime = pkgs-unstable.ollama;
  start = pkgs.writeShellScript "eink-ocr-start" ''
    set -euo pipefail
    models=/var/lib/ollama/models
    manifest="$models/manifests/registry.ollama.ai/library/qwen2.5vl/7b"

    # New Ollama manifests carry separate runner variants. Select the llama.cpp
    # GGUF variant; older manifests already contain the projector directly.
    if ! ${pkgs.jq}/bin/jq -e 'any(.layers[]; .mediaType == "application/vnd.ollama.image.projector")' "$manifest" >/dev/null; then
      while read -r digest; do
        candidate="$models/blobs/''${digest/:/-}"
        if ${pkgs.jq}/bin/jq -e '.runner == "llamacpp"' "$candidate" >/dev/null; then
          manifest="$candidate"
          break
        fi
      done < <(${pkgs.jq}/bin/jq -r '.layers[] | select(.mediaType == "application/vnd.docker.distribution.manifest.v2+json") | .digest' "$manifest")
    fi
    model=$(${pkgs.jq}/bin/jq -er '.layers[] | select(.mediaType == "application/vnd.ollama.image.model") | .digest' "$manifest")
    projector=$(${pkgs.jq}/bin/jq -er '.layers[] | select(.mediaType == "application/vnd.ollama.image.projector") | .digest' "$manifest")

    exec ${runtime}/lib/ollama/llama-server \
      --host 127.0.0.1 --port 11435 --no-webui --offline \
      --model "$models/blobs/''${model/:/-}" \
      --mmproj "$models/blobs/''${projector/:/-}" \
      -c 2048 -np 1 -t 16 -b 512 -ub 512 -ngl 0 \
      --image-min-tokens 64 --image-max-tokens 256 --load-mode none
  '';
in
{
  # Keep the smaller image-token budget private to OCR. Shared Ollama retains
  # its normal vision settings for grounding/counting and other applications.
  systemd.services.eink-ocr = {
    description = "Dedicated low-latency handwriting OCR runtime";
    wantedBy = [ "multi-user.target" ];
    after = [ "ollama.service" "ollama-pull-qwen.service" ];
    wants = [ "ollama.service" "ollama-pull-qwen.service" ];
    environment = {
      HOME = "/run/eink-ocr";
      LD_LIBRARY_PATH = "${runtime}/lib/ollama";
    };
    serviceConfig = {
      ExecStart = start;
      Restart = "on-failure";
      RestartSec = 5;
      # Share the existing model files and dynamic identity, not another copy
      # of the weights. The OCR namespace cannot modify the models.
      User = "ollama";
      DynamicUser = true;
      StateDirectory = "ollama";
      RuntimeDirectory = "eink-ocr";
      ReadOnlyPaths = [ "/var/lib/ollama/models" ];
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      NoNewPrivileges = true;
    };
  };

  home-manager.users.flakm.systemd.user.services.eink-serve.Service.Environment = [
    "EINK_LLAMA_OCR_URL=http://127.0.0.1:11435"
  ];
}
