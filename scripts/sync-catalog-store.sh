#!/usr/bin/env bash
# Copy the catalog store's source packets and the catalog archive from this
# machine's data directory to production's (ISSUES I101). Neither is in Git,
# and scripts/check-catalog-store.R stops a deploy whose committed readings
# lack them, so run this after preparing a packet or capturing a catalog, and
# before merging the reading that cites it.
#
#   bash scripts/sync-catalog-store.sh [--dry-run]
#
# Reads CEDAR_DATA_DIR, CEDAR_PROD_SSH and CEDAR_INSTITUTION (default unm)
# from .env (or the file CEDAR_ENV_FILE names). Production's data directory is read from its running cedar-shiny
# container, and the copies take that directory's owner (the app's user). It
# only adds and updates: production's own proposals and reviews, and anything
# else there, are left as they are.
set -euo pipefail
cd "$(dirname "$0")/.."

dry=""
case "${1:-}" in
  "") ;;
  --dry-run) dry="--dry-run" ;;
  *) echo "Usage: bash scripts/sync-catalog-store.sh [--dry-run]" >&2; exit 2 ;;
esac

env_file="${CEDAR_ENV_FILE:-.env}"
if [ ! -f "$env_file" ]; then
  echo "No $env_file here: run from the checkout that holds .env, or set CEDAR_ENV_FILE" >&2
  exit 1
fi
env_value() {
  { grep -E "^$1=" "$env_file" || true; } | tail -1 | cut -d= -f2- | sed -e "s/^[\"']//" -e "s/[\"']\$//"
}
data="$(env_value CEDAR_DATA_DIR)"
host="$(env_value CEDAR_PROD_SSH)"
institution="$(env_value CEDAR_INSTITUTION)"
institution="${institution:-unm}"
if [ -z "$data" ] || [ -z "$host" ]; then
  echo "Set CEDAR_DATA_DIR and CEDAR_PROD_SSH in .env" >&2
  exit 1
fi
data="${data/#\~/$HOME}"
for dir in "$data/catalog-scans/$institution" "$data/catalog-normalizations/$institution/programs"; do
  if [ ! -d "$dir" ]; then
    echo "Not found: $dir" >&2
    exit 1
  fi
done

remote_cmd() { ssh -o BatchMode=yes "$host" "$@"; }
remote="$(remote_cmd 'docker inspect cedar-shiny --format "{{range .Mounts}}{{if eq .Destination \"/srv/shiny-server/cedar/data\"}}{{.Source}}{{end}}{{end}}"')"
if [ -z "$remote" ]; then
  echo "Production's cedar-shiny container has no data directory mounted" >&2
  exit 1
fi
owner="$(remote_cmd "stat -c %u:%g '$remote'")"
remote_cmd "mkdir -p '$remote/catalog-scans' '$remote/catalog-normalizations/$institution'"
copy() {
  rsync -a $dry --itemize-changes --exclude .DS_Store -e "ssh -o BatchMode=yes" "$2" "$host:$3" |
    awk -v what="$1" '/^</ { n++ } END { printf "%s files %s: %d\n", what, (dry ? "to copy" : "copied"), n }' dry="$dry"
}
copy archive "$data/catalog-scans/$institution" "$remote/catalog-scans/"
copy packet "$data/catalog-normalizations/$institution/programs" "$remote/catalog-normalizations/$institution/"
if [ -z "$dry" ]; then
  remote_cmd "chown -R '$owner' '$remote/catalog-scans/$institution' '$remote/catalog-normalizations/$institution'"
  echo "Production now holds this machine's $institution catalog archive and source packets."
fi
