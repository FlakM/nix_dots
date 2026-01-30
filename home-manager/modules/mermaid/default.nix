{ config, pkgs, lib, ... }:
let
  mermaid-render = pkgs.writeShellScriptBin "mermaid-render" ''
    set -euo pipefail

    usage() {
      echo "Usage: mermaid-render <input.mmd> [output.png] [options]"
      echo "Options:"
      echo "  --bg <color>     Background color (default: transparent)"
      echo "  --theme <name>   dark, default, forest, neutral (default: dark)"
      echo "  --scale <n>      Scale factor 1-3 (default: 3)"
      echo "  --clipboard      Copy result to clipboard via wl-copy"
      echo "  --help           Show this help"
      exit 0
    }

    INPUT="" OUTPUT="" BG="transparent" THEME="dark" SCALE="3" CLIP=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --bg)     BG="$2"; shift 2 ;;
        --theme)  THEME="$2"; shift 2 ;;
        --scale)  SCALE="$2"; shift 2 ;;
        --clipboard) CLIP=1; shift ;;
        --help)   usage ;;
        -*)       echo "Unknown option: $1" >&2; exit 1 ;;
        *)        if [[ -z "$INPUT" ]]; then INPUT="$1"; else OUTPUT="$1"; fi; shift ;;
      esac
    done

    [[ -z "$INPUT" ]] && usage
    [[ -z "$OUTPUT" ]] && OUTPUT="''${INPUT%.mmd}.png"

    ${pkgs.mermaid-cli}/bin/mmdc \
      -i "$INPUT" \
      -o "$OUTPUT" \
      -t "$THEME" \
      -s "$SCALE" \
      -b "$BG" \
      --quiet

    if [[ -n "$CLIP" ]]; then
      ${pkgs.wl-clipboard}/bin/wl-copy --type image/png < "$OUTPUT" 2>/dev/null || \
      ${pkgs.xclip}/bin/xclip -selection clipboard -t image/png -i "$OUTPUT" 2>/dev/null || true
    fi

    echo "$OUTPUT"
  '';
in
{
  home.packages = [ mermaid-render ];
}
