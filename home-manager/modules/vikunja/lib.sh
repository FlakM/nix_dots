#!/usr/bin/env bash
# Shared plumbing for the vikunja-acl / vikunja-task helpers. Concatenated in
# front of each script by home-manager/modules/vikunja.nix, so it is not a
# standalone program, and it is never run on its own.
#
#   VIKUNJA_URL, VIKUNJA_USERNAME_FILE, VIKUNJA_PASSWORD_FILE  (from the module)

base="${VIKUNJA_URL:-https://tasks.house.flakm.com}"
username="$(cat "${VIKUNJA_USERNAME_FILE:?VIKUNJA_USERNAME_FILE is not set}")"
password="$(cat "${VIKUNJA_PASSWORD_FILE:?VIKUNJA_PASSWORD_FILE is not set}")"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/vikunja-tools"
cache_file="$cache_dir/token"

# /api/v1/login is rate limited to 10 requests per minute, so the token is
# cached for nine minutes and every command reuses it.
login() {
  local response status body
  response="$(curl -sS -X POST "$base/api/v1/login" \
    -H 'Content-Type: application/json' \
    -d "$(jq -cn --arg u "$username" --arg p "$password" '{username:$u,password:$p}')" \
    -w $'\n%{http_code}')"
  status="${response##*$'\n'}"
  body="${response%$'\n'*}"
  if [[ "$status" != 2* ]]; then
    echo "${0##*/}: login failed (HTTP $status $body)" >&2
    exit 1
  fi
  mkdir -p "$cache_dir"
  printf '%s' "$body" | jq -r '.token' > "$cache_file"
}

cached_token() {
  if [[ -s "$cache_file" ]] && (( $(stat -c %Y "$cache_file") > $(date +%s) - 540 )); then
    cat "$cache_file"
  fi
}

fetch() {
  local method="$1" path="$2" payload="${3:-}"
  if [[ -n "$payload" ]]; then
    curl -sS -X "$method" "$base/api/v1$path" \
      -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
      -d "$payload" -w $'\n%{http_code}'
  else
    curl -sS -X "$method" "$base/api/v1$path" \
      -H "Authorization: Bearer $token" -w $'\n%{http_code}'
  fi
}

# Prints the response body, or exits with the server's error on a non-2xx.
request() {
  local method="$1" path="$2" payload="${3:-}" response status body
  token="$(cached_token)"
  if [[ -z "$token" ]]; then
    login
    token="$(cat "$cache_file")"
  fi
  response="$(fetch "$method" "$path" "$payload")"
  status="${response##*$'\n'}"
  body="${response%$'\n'*}"
  if [[ "$status" == 401 ]]; then
    rm -f "$cache_file"
    login
    token="$(cat "$cache_file")"
    response="$(fetch "$method" "$path" "$payload")"
    status="${response##*$'\n'}"
    body="${response%$'\n'*}"
  fi
  if [[ "$status" != 2* ]]; then
    echo "${0##*/}: HTTP $status $body" >&2
    exit 1
  fi
  printf '%s' "$body"
}
