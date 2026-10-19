#!/usr/bin/env bash
# Manage who can access which Vikunja project.
#
# The vendored vikunja-cli (v1.0.0) predates the Vikunja 2.x membership API: it
# calls /projects/{id}/members (now 404) and identifies users by numeric id
# (now rejected), so access management goes through the API directly here.
# lib.sh (prepended by the nix module) provides login/request.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: vikunja-acl <command>

  projects                          list projects (id, title, owner)
  whoami                            show the account this tool logs in as
  access <project-id>               list users with access and their rights
  add <project-id> <username> <read|write|admin>
  set <project-id> <username> <read|write|admin>
  remove <project-id> <username>

rights: read = view only, write = view + edit tasks, admin = also manage access
EOF
  exit 2
}

right_number() {
  case "$1" in
    0|read) printf 0 ;;
    1|write) printf 1 ;;
    2|admin) printf 2 ;;
    *) echo "vikunja-acl: invalid right '$1' (expected read|write|admin)" >&2; exit 2 ;;
  esac
}

rights_def='def rname: if . == 2 then "admin" elif . == 1 then "write" else "read" end;'

case "${1:-}" in
  projects)
    request GET /projects \
      | jq -r '.[] | "\(.id)\t\(.title)\towner=\(.owner.username)"'
    ;;
  whoami)
    request GET /user | jq -c '{id, username}'
    ;;
  access)
    [[ $# -eq 2 ]] || usage
    request GET "/projects/$2/users" \
      | jq -c "$rights_def"'. | sort_by(.username) | .[] | {username, right: (.permission | rname), level: .permission}'
    ;;
  add)
    [[ $# -eq 4 ]] || usage
    level="$(right_number "$4")"
    request PUT "/projects/$2/users" \
      "$(jq -cn --arg u "$3" --argjson r "$level" '{username:$u,permission:$r}')" \
      | jq -c "$rights_def"'{username, right: (.permission | rname), level: .permission}'
    ;;
  set)
    [[ $# -eq 4 ]] || usage
    level="$(right_number "$4")"
    request POST "/projects/$2/users/$3" \
      "$(jq -cn --argjson r "$level" '{permission:$r}')" \
      | jq -c "$rights_def"'{username, right: (.permission | rname), level: .permission}'
    ;;
  remove)
    [[ $# -eq 3 ]] || usage
    printf '%s\n' "$(request DELETE "/projects/$2/users/$3")"
    ;;
  *) usage ;;
esac
