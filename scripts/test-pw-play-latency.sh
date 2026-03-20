#!/usr/bin/env bash
set -euo pipefail

sample="${1:-$HOME/.openpeon/packs/rick-and-morty/sounds/because_i_invent_transform_create_and_destroy_for_a_living.mp3}"
system_pw_play="/run/current-system/sw/bin/pw-play"
wrapper_pw_play="$HOME/.local/bin/pw-play"

if [[ ! -f "$sample" ]]; then
	echo "Sample not found: $sample" >&2
	exit 1
fi

if [[ ! -x "$system_pw_play" ]]; then
	echo "System pw-play not found: $system_pw_play" >&2
	exit 1
fi

run_case() {
	local label="$1"
	shift
	echo "=== $label ==="
	"$@" "$sample"
	echo
	sleep 2
}

echo "Sample: $sample"
echo "Listen for whether the beginning is cut off."
echo

if [[ -x "$wrapper_pw_play" ]]; then
	run_case "1) wrapper cold (~/.local/bin/pw-play)" "$wrapper_pw_play"
else
	echo "Skipping 1) wrapper cold: $wrapper_pw_play not found"
	echo
fi

run_case "2) system cold (default latency)" "$system_pw_play" --volume 1.0
run_case "3) system with 50ms latency" "$system_pw_play" --latency 50ms --volume 1.0
run_case "4) system with 100ms latency" "$system_pw_play" --latency 100ms --volume 1.0

echo "Done. Tell me which cases played the full clip."
