#!/usr/bin/env bash
input=$(cat)
j() { echo "$input" | jq -r "$1 // empty" 2>/dev/null; }

model=$(j '.model.display_name')
ctx=$(j '.context_window.used_percentage')
cost=$(j '.cost.total_cost_usd')
dur_ms=$(j '.cost.total_duration_ms')
added=$(j '.cost.total_lines_added')
removed=$(j '.cost.total_lines_removed')
r5h=$(j '.rate_limits.five_hour.used_percentage')
vim_mode=$(j '.vim.mode')

# push rate limits to Pushgateway (background, non-blocking)
if echo "$input" | jq -e '.rate_limits' >/dev/null 2>&1; then
  echo "$input" | jq -r '.rate_limits' > /tmp/.claude-rate-limits-last.json 2>/dev/null
  (echo "$input" | jq -r '
    .rate_limits as $rl |
    [
      "# HELP claude_rate_limit_pct Rate limit percentage used by window",
      "# TYPE claude_rate_limit_pct gauge",
      ($rl | to_entries[] | select(.value | type == "object") |
        .key as $k | .value | to_entries[] | select(.key == "used_percentage") |
        "claude_rate_limit_pct{window=\"\($k)\"} \(.value)"),
      "# HELP claude_rate_limit_resets_at Unix timestamp when rate limit window resets",
      "# TYPE claude_rate_limit_resets_at gauge",
      ($rl | to_entries[] | select(.value | type == "object") |
        .key as $k | .value | to_entries[] | select(.key == "resets_at") |
        "claude_rate_limit_resets_at{window=\"\($k)\"} \(.value)")
    ] | join("\n")
  ' | curl --silent --max-time 2 --data-binary @- "http://odroid:9091/metrics/job/claude-limits") &
fi
wt=$(j '.worktree.name')

# defaults
ctx=${ctx:-0}
cost=${cost:-0}

# context bar (20 blocks for finer granularity)
bw=20
filled=$(echo "$ctx $bw" | awk '{printf "%d", int($1/100*$2+0.5)}')
(( filled > bw )) && filled=$bw
(( filled < 0 )) && filled=0
empty=$((bw - filled))
bar=$(printf '%0.s━' $(seq 1 "$filled" 2>/dev/null))$(printf '%0.s┄' $(seq 1 "$empty" 2>/dev/null))

pct=$(printf "%.0f" "$ctx")
# context color: green < 60%, yellow < 80%, red >= 80%
if (( pct >= 80 )); then cc="1;31"
elif (( pct >= 60 )); then cc="33"
else cc="32"; fi

# duration
out=""
if [ -n "$dur_ms" ] && [ "$dur_ms" != "0" ]; then
  secs=$((dur_ms / 1000))
  if (( secs >= 3600 )); then
    dur="$((secs/3600))h$((secs%3600/60))m"
  elif (( secs >= 60 )); then
    dur="$((secs/60))m$((secs%60))s"
  else
    dur="${secs}s"
  fi
fi

# line 1: model | context bar | cost | duration
out="\033[1;36m${model:-?}\033[0m"
out+=" \033[${cc}m${bar} ${pct}%\033[0m"
out+=" \033[33m\$$(printf '%.2f' "$cost")\033[0m"
[ -n "$dur" ] && out+=" \033[2m${dur}\033[0m"

# line 2: rate limit | lines changed | worktree | vim mode
line2=""
if [ -n "$r5h" ]; then
  r5i=$(printf "%.0f" "$r5h")
  if (( r5i >= 80 )); then rc="1;31"
  elif (( r5i >= 50 )); then rc="33"
  else rc="2;32"; fi
  line2+="\033[${rc}m5h:${r5i}%\033[0m"
fi

if [ -n "$added" ] || [ -n "$removed" ]; then
  [ -n "$line2" ] && line2+=" "
  [ -n "$added" ] && [ "$added" != "0" ] && line2+="\033[32m+${added}\033[0m"
  [ -n "$removed" ] && [ "$removed" != "0" ] && line2+=" \033[31m-${removed}\033[0m"
fi

if [ -n "$wt" ]; then
  [ -n "$line2" ] && line2+=" "
  line2+="\033[2;35m${wt}\033[0m"
fi

if [ -n "$vim_mode" ]; then
  [ -n "$line2" ] && line2+=" "
  case "$vim_mode" in
    NORMAL)  vc="1;34" ;;
    INSERT)  vc="1;32" ;;
    VISUAL)  vc="1;35" ;;
    *)       vc="2" ;;
  esac
  line2+="\033[${vc}m${vim_mode}\033[0m"
fi

# git branch (cached 5s)
cache="/tmp/.claude-sl-git-$$"
now=$(date +%s)
if [ -f "$cache" ] && (( now - $(stat -c %Y "$cache" 2>/dev/null || echo 0) < 5 )); then
  branch=$(cat "$cache")
else
  branch=$(git -C "$(j '.cwd')" rev-parse --abbrev-ref HEAD 2>/dev/null)
  echo "$branch" > "$cache" 2>/dev/null
fi
if [ -n "$branch" ]; then
  [ -n "$line2" ] && line2+=" "
  line2+="\033[2;36m${branch}\033[0m"
fi

printf "%b" "$out"
[ -n "$line2" ] && printf "\n%b" "$line2"
