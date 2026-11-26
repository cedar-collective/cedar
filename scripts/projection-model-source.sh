#!/usr/bin/env bash
# The files whose edit makes the next deploy rebuild both projection bundles.
#
#   scripts/projection-model-source.sh             # the list, one path a line
#   scripts/projection-model-source.sh --touched   # paths on stdin; prints the ones on the list
#
# The list is enrollment_projection_model_source_files()
# (R/features/enrollment-projections.R). It is read here from the function's
# own text, so that a shell with no R can ask: ./run-tests.sh --changed, and
# the pull-request check that names the cost before the merge and not after
# it (ISSUES M77). The deploy hashes these same files; test-ci.R holds that
# this reading and the function's value are one list.
set -euo pipefail
cd "$(dirname "$0")/.."

source_file="R/features/enrollment-projections.R"
list="$(sed -n '/^enrollment_projection_model_source_files <- function() {$/,/^}$/p' "$source_file" |
  grep -o '"[^"]*"' | tr -d '"' || true)"
if [ -z "$list" ]; then
  echo "projection-model-source.sh: no list read from ${source_file}:" \
       "enrollment_projection_model_source_files() is no longer written as this script reads it" >&2
  exit 2
fi

case "${1:-}" in
  "")
    printf '%s\n' "$list" ;;
  --touched)
    # grep's 1 is "none of them", which is an answer; anything above is not.
    grep -F -x -f <(printf '%s\n' "$list") || [ "$?" -eq 1 ] ;;
  *)
    echo "usage: scripts/projection-model-source.sh [--touched]" >&2
    exit 2 ;;
esac
