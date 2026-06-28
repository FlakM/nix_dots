#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
cd "$repo_root"

inputs=(cx-cli coralogix-private)
if [[ $# -gt 0 ]]; then
	inputs=("$@")
fi

nix flake update "${inputs[@]}"
