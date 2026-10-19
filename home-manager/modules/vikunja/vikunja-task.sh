#!/usr/bin/env bash
# Mutate a Vikunja task without clobbering the fields you did not touch.
#
# Vikunja replaces the whole task on POST /tasks/{id}: a body carrying only the
# field you want to change blanks every other field, and `vikunja-cli tasks
# update` (1.0.0) builds exactly such a body. So every command here reads the
# task, patches it with jq, and writes the patched object back unchanged — that
# is also what keeps assignees and labels, which the write replaces wholesale.
#
# Env (wired up by home-manager/modules/vikunja.nix):
#   VIKUNJA_URL, VIKUNJA_USERNAME_FILE, VIKUNJA_PASSWORD_FILE, VIKUNJA_TZ
set -euo pipefail

tz="${VIKUNJA_TZ:-Europe/Warsaw}"

usage() {
  cat >&2 <<'EOF'
usage: vikunja-task <command>

  get <task-id>                                  full task as JSON
  done <task-id>                                 mark complete (also clears focus)
  reopen <task-id>                               clear the done flag
  priority <task-id> <0-5>                       set priority (>= 2 = important)
  due <task-id> <today|tomorrow|week|YYYY-MM-DD|RFC3339|clear>
  title <task-id> <text>
  description <task-id> <text>                   use <br> for line breaks
  move <task-id> <project-id>                    move it to another project
  focus <task-id>                                mark as the task being worked on
  unfocus [<task-id>]                            clear focus (one task, or all)
  focused                                        the focused task as JSON, or null
  delete <task-id>

Focus is stored as the Vikunja label named by VIKUNJA_FOCUS_LABEL (default
"doing"); at most one open task carries it.
EOF
  exit 2
}

focus_label="${VIKUNJA_FOCUS_LABEL:-doing}"

focus_label_id() {
  local id
  id="$(request GET /labels | jq -r --arg t "$focus_label" '[.[] | select(.title == $t) | .id][0] // empty')"
  if [[ -z "$id" ]]; then
    id="$(request PUT /labels "$(jq -cn --arg t "$focus_label" '{title:$t,hex_color:"72d7ff"}')" | jq -r '.id')"
  fi
  printf '%s' "$id"
}

focused_task_ids() {
  request GET "/tasks?filter=labels%20%3D%20$1" | jq -r '.[].id'
}

task_has_label() {
  request GET "/tasks/$1/labels" | jq -e --argjson l "$2" 'any(.[]; .id == $l)' >/dev/null
}

# Read the task, apply the jq program, post the result back untouched.
task_update() {
  local id="$1" program="$2"; shift 2
  local body
  body="$(request GET "/tasks/$id" | jq -c "$@" "$program")"
  request POST "/tasks/$id" "$body"
}

due_stamp() {
  case "$1" in
    today) TZ="$tz" date -d 'today 18:00' +%Y-%m-%dT%H:%M:%S%:z ;;
    tomorrow) TZ="$tz" date -d 'tomorrow 18:00' +%Y-%m-%dT%H:%M:%S%:z ;;
    week) TZ="$tz" date -d '7 days 18:00' +%Y-%m-%dT%H:%M:%S%:z ;;
    clear) printf '0001-01-01T00:00:00Z' ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) TZ="$tz" date -d "$1 18:00" +%Y-%m-%dT%H:%M:%S%:z ;;
    *T*) printf '%s' "$1" ;;
    *) echo "vikunja-task: invalid due date '$1'" >&2; exit 2 ;;
  esac
}

case "${1:-}" in
  get)
    [[ $# -eq 2 ]] || usage
    request GET "/tasks/$2"
    ;;
  done)
    [[ $# -eq 2 ]] || usage
    task_update "$2" '.done = true'
    lid="$(focus_label_id)"
    if task_has_label "$2" "$lid"; then
      request DELETE "/tasks/$2/labels/$lid" >/dev/null
    fi
    ;;
  move)
    [[ $# -eq 3 ]] || usage
    task_update "$2" '.project_id = $p' --argjson p "$3"
    ;;
  focus)
    [[ $# -eq 2 ]] || usage
    lid="$(focus_label_id)"
    while read -r other; do
      [[ -z "$other" || "$other" == "$2" ]] && continue
      request DELETE "/tasks/$other/labels/$lid" >/dev/null
    done < <(focused_task_ids "$lid")
    request PUT "/tasks/$2/labels" "$(jq -cn --argjson l "$lid" '{label_id:$l}')" >/dev/null
    request GET "/tasks/$2"
    ;;
  unfocus)
    lid="$(focus_label_id)"
    if [[ $# -eq 2 ]]; then
      if task_has_label "$2" "$lid"; then
        request DELETE "/tasks/$2/labels/$lid" >/dev/null
      fi
      printf 'unfocused %s\n' "$2"
    else
      while read -r other; do
        [[ -z "$other" ]] && continue
        request DELETE "/tasks/$other/labels/$lid" >/dev/null
      done < <(focused_task_ids "$lid")
      printf 'no focused task\n'
    fi
    ;;
  focused)
    lid="$(focus_label_id)"
    request GET "/tasks?filter=labels%20%3D%20$lid" \
      | jq -c '[.[] | select(.done == false)][0] // null'
    ;;
  reopen)
    [[ $# -eq 2 ]] || usage
    task_update "$2" '.done = false'
    ;;
  priority)
    [[ $# -eq 3 ]] || usage
    [[ "$3" =~ ^[0-5]$ ]] || { echo "vikunja-task: priority must be 0-5" >&2; exit 2; }
    task_update "$2" '.priority = $p' --argjson p "$3"
    ;;
  due)
    [[ $# -eq 3 ]] || usage
    task_update "$2" '.due_date = $d' --arg d "$(due_stamp "$3")"
    ;;
  title)
    [[ $# -eq 3 ]] || usage
    task_update "$2" '.title = $t' --arg t "$3"
    ;;
  description)
    [[ $# -eq 3 ]] || usage
    task_update "$2" '.description = $d' --arg d "$3"
    ;;
  delete)
    [[ $# -eq 2 ]] || usage
    printf '%s\n' "$(request DELETE "/tasks/$2")"
    ;;
  *) usage ;;
esac
