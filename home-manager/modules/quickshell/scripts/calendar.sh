#!/usr/bin/env bash
set -euo pipefail

start="${1:-today}"
days="${2:-2}"
year=$(date +%Y)

# `week` means the current Monday..Sunday, regardless of which day it is today.
if [[ "$start" == "week" ]]; then
  start=$(date -d "-$((10#$(date +%u) - 1)) days" +%d.%m.%Y)
fi

# Window bounds as ISO dates — the same span khal lists — so Librus tasks can
# be filtered into it (overdue ones are pinned to the window's first day).
window_start="$year-01-01"
window_end="$window_start"
if [[ "$start" == "today" ]]; then
  window_start=$(date +%F)
else
  IFS='.' read -r sd sm sy <<< "$start"
  if [[ -n "$sy" ]]; then
    window_start=$(printf '%04d-%02d-%02d' "$sy" "$sm" "$sd")
  else
    window_start=$(printf '%04d-%02d-%02d' "$year" "$sm" "$sd")
    # Around new year the listed date belongs to the next year.
    if (( $(date -d "$window_start" +%s) < $(date +%s) - 2592000 )); then
      window_start=$(printf '%04d-%02d-%02d' "$((year + 1))" "$sm" "$sd")
    fi
  fi
fi
window_end=$(date -d "$window_start + $((days - 1)) days" +%F)

# Open tasks from the Librus — Emilka Vikunja project (fed by czujka-librus on
# odroid). Tasks without a due date are skipped — the Vikunja panel covers
# those. A failure to reach Vikunja must not hide the calendar events.
tasks="[]"
if tasks_raw=$(quickshell-vikunja list 2>/dev/null); then
  tasks=$(printf '%s' "$tasks_raw" |
    jq '
      [.tasks[]
        | select(.project_title | test("Librus"; "i"))
        | select((.done // false) | not)
        | select(.due_date != null and (.due_date | startswith("0001") | not))
        | {
            title,
            iso: (.due_date | split("T")[0]),
            hm: (try (.due_date | capture("T(?<hm>[0-9]{2}:[0-9]{2}):(?<rest>[0-9]{2})")).hm catch "")
          }
        | {
            kind: "task",
            date: (if .iso < $ws then $ws else .iso end),
            start: .hm,
            end: "",
            title,
            calendar: "Librus — Emilka",
            all_day: false,
            overdue: (.iso < $ws),
            due_date: .iso
          }
        | select(.date <= $we)]' \
      --arg ws "$window_start" --arg we "$window_end") || tasks="[]"
fi
[[ -z "$tasks" ]] && tasks="[]"

khal list "$start" "${days}d" --day-format "" --format $'{start-date}\t{start-time}\t{end-time}\t{title}\t{calendar}' 2>/dev/null \
  | while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      # cut keeps empty fields (tab-as-IFS in read would collapse them, and
      # all-day events have empty start/end times).
      raw_date=$(cut -f1 <<< "$line")
      [[ -z "$raw_date" ]] && continue
      ev_start=$(cut -f2 <<< "$line")
      ev_end=$(cut -f3 <<< "$line")
      title=$(cut -f4 <<< "$line")
      calendar=$(cut -f5 <<< "$line")

      IFS='.' read -r day month _ <<< "$raw_date"
      year=$(date +%Y)
      iso=$(printf '%s-%s-%s' "$year" "$month" "$day")
      # khal prints dates without a year (dd.mm.); around new year the listed
      # date belongs to the next year, so nudge it forward when it reads as old.
      if (( $(date -d "$iso" +%s) < $(date +%s) - 2592000 )); then
        iso=$(printf '%s-%s-%s' "$((year + 1))" "$month" "$day")
      fi

      jq -cn \
        --arg date "$iso" \
        --arg start "$ev_start" \
        --arg end "$ev_end" \
        --arg title "$title" \
        --arg calendar "$calendar" \
        '{date: $date, start: $start, end: $end, title: $title, calendar: $calendar, all_day: ($start == "")}'
    done \
  | jq -s . \
  | jq -cn --argjson events "$(cat)" --argjson tasks "$tasks" '
      ($events | map(.kind = "event" | .overdue = false)) + $tasks
      | sort_by(.date, .start)'
