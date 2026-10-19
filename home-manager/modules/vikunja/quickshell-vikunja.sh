#!/usr/bin/env bash
# Backend for the QuickShell Vikunja dashboard.
#
# `list` is one JSON document with everything the panel renders; every other
# command is a task mutation delegated to vikunja-task, which does the
# read-modify-write that Vikunja's full-replace task update requires.
#
# "Important" is the Vikunja priority: the panel's star sets priority 4 and
# clears it to 0, and everything with priority >= 2 is listed in the important
# section, ordered by priority and then due date.
set -euo pipefail

case "${1:-list}" in
  list)
    projects=$(vikunja-cli projects list)
    tasks=$(vikunja-cli tasks list --filter "done = false" --sort due_date --order-by asc --per-page 100)
    jq -n --argjson projects "$projects" --argjson tasks "$tasks" --arg focus "$VIKUNJA_FOCUS_LABEL" '
      ($projects.data | map({ key: (.id | tostring), value: .title }) | from_entries) as $names |
      (($projects.data | map(select(.is_favorite)) | first)
        // ($projects.data | map(select(.title != "Inbox")) | first)
        // ($projects.data | first)) as $pinned |
      def enrich: . + { project_title: ($names[(.project_id | tostring)] // "Unknown") };
      def focused: [.labels[]?.title] | index($focus);
      [$tasks.data[] | enrich] as $open |
      {
        tasks: $open,
        important: ($open | map(select(.priority >= 2))
          | sort_by([(-.priority), (if (.due_date | startswith("0001")) then "9999" else .due_date end)])),
        focused: ($open | map(select(focused)) | first // null),
        count: $tasks.result_count,
        pinned_project: $pinned
      }
    '
    ;;
  done | reopen | priority | due | focus | unfocus)
    exec vikunja-task "$@"
    ;;
  *)
    printf 'usage: quickshell-vikunja list|done ID|reopen ID|priority ID N|due ID today|tomorrow|week|clear\n' >&2
    exit 2
    ;;
esac
