#!/usr/bin/env bash
set -euo pipefail

start="${1:-today}"
days="${2:-2}"

# `week` means the current Monday..Sunday, regardless of which day it is today.
if [[ "$start" == "week" ]]; then
  start=$(date -d "-$((10#$(date +%u) - 1)) days" +%d.%m.%Y)
fi

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
  | jq -s .
