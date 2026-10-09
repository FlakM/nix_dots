#!/usr/bin/env bash
# Usage: bash scoped-diff.sh <baseSha> <out-path> [-- files...]
# Writes one patch file and prints {path, totalLines, files: {"<file>": {startLine, lineCount}}}
# so agents can Read(offset, limit) their own section.
set -uo pipefail

base="$1"; out="$2"; shift 2
[[ "${1:-}" == "--" ]] && shift
git diff -M "$base"...HEAD -- "$@" >"$out"

awk -v path="$out" '
  /^diff --git / { if (f != "") idx[f] = start "," (NR - start); split($0, a, " b/"); f = a[length(a)]; start = NR; order[++n] = f }
  END {
    if (f != "") idx[f] = start "," (NR - start + 1)
    printf "{\"path\":\"%s\",\"totalLines\":%d,\"files\":{", path, NR
    for (i = 1; i <= n; i++) { split(idx[order[i]], p, ","); printf "%s\"%s\":{\"startLine\":%d,\"lineCount\":%d}", (i > 1 ? "," : ""), order[i], p[1], p[2] }
    print "}}"
  }' "$out"
