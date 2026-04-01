#!/usr/bin/env bash
input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "?"')
used=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

filled=$(echo "$used" | awk '{printf "%d", int($1/10+0.5)}')
empty=$((10 - filled))
bar=$(printf '%0.s█' $(seq 1 "$filled" 2>/dev/null))$(printf '%0.s░' $(seq 1 "$empty" 2>/dev/null))
pct=$(printf "%.0f" "$used")

# color: green < 50%, yellow < 80%, red >= 80%
if [ "$pct" -ge 80 ]; then c="31"; elif [ "$pct" -ge 50 ]; then c="33"; else c="32"; fi

printf "\033[2;36m%s\033[0m \033[%sm%s %d%%\033[0m \033[2;33m\$%.2f\033[0m" \
  "$model" "$c" "$bar" "$pct" "$cost"
