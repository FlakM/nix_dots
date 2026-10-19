#!/usr/bin/env bash
# Open a task description in $EDITOR (via a terminal window), then push the
# edited text back to Vikunja.
#
# The description is stored as HTML with <br> line breaks; it is shown as plain
# text with real newlines and converted back on save. Everything else on the
# task is left alone (read-modify-write, see vikunja-task).
#
# Env: VIKUNJA_TERMINAL (default kitty), VIKUNJA_EDITOR (default vim),
#      VIKUNJA_EDIT_SCRIPT (testing hook: replaces the editor, gets the file).
set -euo pipefail

id="${1:?usage: vikunja-edit-description <task-id>}"
terminal="${VIKUNJA_TERMINAL:-kitty}"
editor="${VIKUNJA_EDITOR:-vim}"

tmp="$(mktemp --suffix=.md)"
trap 'rm -f "$tmp"' EXIT

# HTML -> editable text
render() {
  sed -E \
    -e 's/<br[[:space:]]*\/?>/\n/gI' \
    -e 's/<\/(p|div|li)>/\n/gI' \
    -e 's/<[^>]*>//g' \
    -e 's/&nbsp;/ /g' \
    -e 's/&lt;/</g' \
    -e 's/&gt;/>/g' \
    -e 's/&amp;/\&/g'
}

request GET "/tasks/$id" | jq -r '.description // ""' | render > "$tmp"
original="$(cat "$tmp")"

if [[ -n "${VIKUNJA_EDIT_SCRIPT:-}" ]]; then
  "$VIKUNJA_EDIT_SCRIPT" "$tmp"
else
  "$terminal" -e "$editor" "$tmp" || true
fi

edited="$(cat "$tmp")"
if [[ "$edited" == "$original" ]]; then
  printf 'vikunja-edit-description: no changes\n'
  exit 0
fi

# text -> HTML: every line break becomes <br>
html="$(printf '%s' "$edited" | awk '{ printf "%s%s", (NR > 1 ? "<br>" : ""), $0 }')"
body="$(request GET "/tasks/$id" | jq -c --arg description "$html" '.description = $description')"
request POST "/tasks/$id" "$body" > /dev/null
printf 'vikunja-edit-description: saved task %s\n' "$id"
