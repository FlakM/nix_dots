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
    jq -n --argjson projects "$projects" --argjson tasks "$tasks" \
      --arg focus "$VIKUNJA_FOCUS_LABEL" \
      --arg week "${VIKUNJA_WEEK_PROJECT:-27}" \
      --arg work "${VIKUNJA_WORK_PROJECT:-26}" '
      ($projects.data | map({ id, title, is_favorite })) as $all |
      ($all | map({ key: (.id | tostring), value: .title }) | from_entries) as $names |
      (($all | map(select(.is_favorite)) | first)
        // ($all | map(select(.title != "Inbox")) | first)
        // ($all | first)) as $pinned |
      # Project ids are pinned by env, but fall back to a title match so a
      # recreated project keeps working without touching the config.
      def project($id; $re):
        ($all | map(select((.id | tostring) == $id)) | first)
        // ($all | map(select(.title | test($re; "i"))) | first);
      (project($week; "tydzie\u0144.*maciek|maciek.*tydzie\u0144") // $pinned) as $week_project |
      (project($work; "coralogix")
        // ($all | map(select(.id != $week_project.id)) | first)
        // $pinned) as $work_project |
      def enrich: . + { project_title: ($names[(.project_id | tostring)] // "Unknown") };
      def focused: [.labels[]?.title] | index($focus);
      [$tasks.data[] | enrich] as $open |
      {
        tasks: $open,
        important: ($open | map(select(.priority >= 2))
          | sort_by([(-.priority), (if (.due_date | startswith("0001")) then "9999" else .due_date end)])),
        focused: ($open | map(select(focused)) | first // null),
        count: $tasks.result_count,
        pinned_project: $pinned,
        week_project: $week_project,
        work_project: $work_project
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
