#!/usr/bin/env bash
set -euo pipefail

config_dir="${HOME}/.openpeon"
config_json="${config_dir}/config.json"

pack="${1:-}"
if [[ -z "$pack" && -f "$config_json" ]]; then
	pack="$(
		python3 - "$config_json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f).get("default_pack", ""))
PY
	)"
fi

if [[ -z "$pack" ]]; then
	echo "Could not determine active pack. Pass one as: $0 <pack-name>" >&2
	exit 1
fi

pack_dir="${config_dir}/packs/${pack}"
sample="${2:-${pack_dir}/sounds/because_i_invent_transform_create_and_destroy_for_a_living.mp3}"

if [[ ! -f "$sample" ]]; then
	sample="$(
		python3 - "$pack_dir/openpeon.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for category in ("session.start", "task.complete", "input.required", "task.error"):
    sounds = data.get("categories", {}).get(category, {}).get("sounds", [])
    if sounds:
        print(f"{sys.argv[1].rsplit('/', 1)[0]}/{sounds[0]['file']}")
        break
else:
    raise SystemExit(1)
PY
	)"
fi

if [[ ! -f "$sample" ]]; then
	echo "Could not find a sample audio file in ${pack_dir}" >&2
	exit 1
fi

real_pw_play="$(which -a pw-play | awk 'NR==2 { print; exit }')"

echo "Pack:   $pack"
echo "Sample: $sample"
echo
echo "Listen for whether the clip is complete or cut off."
echo

silence_wav="$(mktemp --suffix=.wav)"
trap 'rm -f "$silence_wav"' EXIT
prime_ms="${PEON_PRIME_MS:-1000}"
prime_gap_ms="${PEON_PRIME_GAP_MS:-250}"
python3 - "$silence_wav" <<'PY'
import struct, sys, wave
path = sys.argv[1]
rate = 48000
duration_s = 1.0
frames = int(rate * duration_s)
with wave.open(path, "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(rate)
    silence = struct.pack("<h", 0) * 2
    w.writeframes(silence * frames)
PY

run_test() {
	local label="$1"
	shift
	echo "=== $label ==="
	"$@" "$sample"
	echo
	sleep 1
}

if [[ -x "${HOME}/.local/bin/pw-play" ]]; then
	echo "=== primed wrapper pw-play (${prime_ms}ms silence first) ==="
	"${HOME}/.local/bin/pw-play" "$silence_wav"
	python3 - "$prime_gap_ms" <<'PY'
import sys, time
time.sleep(int(sys.argv[1]) / 1000)
PY
	"${HOME}/.local/bin/pw-play" "$sample"
	echo
	sleep 1

	run_test "wrapper pw-play (~/.local/bin/pw-play, latency 2ms)" "${HOME}/.local/bin/pw-play"
else
	echo "Skipping wrapper pw-play: ${HOME}/.local/bin/pw-play not found"
	echo
fi

if [[ -n "$real_pw_play" && -x "$real_pw_play" ]]; then
	run_test "system pw-play (${real_pw_play}, default latency)" "$real_pw_play" --volume 1.0
else
	echo "Skipping system pw-play: could not find non-wrapper pw-play"
	echo
fi

if command -v paplay >/dev/null 2>&1; then
	run_test "paplay" paplay --volume=65536
else
	echo "Skipping paplay: not installed"
	echo
fi

echo "Done. Tell me which test played the full clip."
