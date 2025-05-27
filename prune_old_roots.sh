#!/usr/bin/env bash
set -euo pipefail

# Helper: get modification time of a file (epoch seconds), works on Linux & macOS
stat_mtime() {
  local file=$1
  if stat --version &>/dev/null; then
    stat -c %Y "$file"
  else
    stat -f %m "$file"
  fi
}

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running: nix-store --gc --print-roots"
roots=$(nix-store --gc --print-roots)

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Found GC roots:"
echo "$roots"
echo

now=$(date +%s)
max_age_days=7
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Deleting roots older than ${max_age_days} days under \$HOME..."
echo

# Process each non-empty line
while read -r line; do
  [[ -z "$line" ]] && continue

  # Split at the first " -> "
  root=${line%% ->*}

  # 1) exists?
  if [[ ! -e "$root" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Skipping (not found): $root"
    continue
  fi

  # 2) in home directory?
  if [[ "$root" != "$HOME/"* ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Skipping (outside home): $root"
    continue
  fi

  # 3) check age
  mtime=$(stat_mtime "$root")
  age_days=$(( (now - mtime) / 86400 ))
  if (( age_days > max_age_days )); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Deleting: $root (age: ${age_days}d)"
    rm -v "$root"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Keeping:  $root (age: ${age_days}d ≤ ${max_age_days}d)"
  fi
done <<< "$roots"

echo
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Done."


