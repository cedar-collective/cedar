#!/usr/bin/env bash
#
# pull-production-data.sh — copy production's prepared CEDAR tables to this machine
#
# Keeps a local development environment on the data production serves, without
# re-running the MyReports pulls or the transform locally. It copies the
# prepared tables (cedar_*.qs and cedar-status.json) and, with --projections,
# the saved projection bundles. Nothing local is deleted: a file that is
# replaced is kept in a dated backup folder beside it, and files production
# does not have are left alone.
#
# Connection settings come from the environment or the repository's .env
# (which is gitignored; never commit a host or a login):
#
#   CEDAR_PROD_SSH          login@host for ssh/sftp                  (required)
#   CEDAR_PROD_DATA_DIR     production's data directory              (required)
#   CEDAR_PROD_OUTPUT_DIR   production's output directory (<repo>/output there);
#                           required for --projections, never guessed
#   CEDAR_PROD_SSH_PORT     ssh port                                 (default: 22)
#   CEDAR_PROD_SSH_KEY      private key for that login, when it is not
#                           one ssh offers by default         (default: none)
#   CEDAR_DATA_DIR          local data directory       (default: <repo>/data)
#
# Usage:
#   scripts/pull-production-data.sh [--projections] [--method auto|rsync|sftp]
#                                   [--list] [--dry-run]
#
#   --list          show what production has, copy nothing
#   --projections   also copy output/projections/*.qs into <repo>/output/projections
#   --method        rsync copies only what changed; sftp works on accounts
#                   limited to file transfer. auto (default) uses rsync when the
#                   server allows a shell command, otherwise sftp; it stops if
#                   it cannot connect at all.
#   --dry-run       print the commands without running them
#
# After a pull, restart the app (scripts/restart-cedar.sh) so it reads the new
# files. Projection bundles built by a different model version are rebuilt or
# refused by the app, never silently reused.

set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
step() { echo -e "${BLUE}==>${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

PROJECTIONS=false
METHOD=auto
LIST_ONLY=false
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --projections) PROJECTIONS=true ;;
    --method) shift; METHOD="${1:-}" ;;
    --list) LIST_ONLY=true ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Unknown argument: $1 (see --help)" ;;
  esac
  shift
done
[[ "$METHOD" =~ ^(auto|rsync|sftp)$ ]] || die "--method must be auto, rsync, or sftp"

# Read only the keys this script needs from .env; never execute the file.
env_value() {
  local key="$1" file="$REPO_ROOT/.env"
  [[ -f "$file" ]] || return 0
  grep -E "^[[:space:]]*${key}=" "$file" | tail -1 | sed -E "s/^[[:space:]]*${key}=//; s/^['\"]//; s/['\"]$//"
}
CEDAR_PROD_SSH="${CEDAR_PROD_SSH:-$(env_value CEDAR_PROD_SSH)}"
CEDAR_PROD_DATA_DIR="${CEDAR_PROD_DATA_DIR:-$(env_value CEDAR_PROD_DATA_DIR)}"
CEDAR_PROD_OUTPUT_DIR="${CEDAR_PROD_OUTPUT_DIR:-$(env_value CEDAR_PROD_OUTPUT_DIR)}"
CEDAR_PROD_SSH_PORT="${CEDAR_PROD_SSH_PORT:-$(env_value CEDAR_PROD_SSH_PORT)}"
CEDAR_PROD_SSH_PORT="${CEDAR_PROD_SSH_PORT:-22}"
CEDAR_PROD_SSH_KEY="${CEDAR_PROD_SSH_KEY:-$(env_value CEDAR_PROD_SSH_KEY)}"
CEDAR_PROD_SSH_KEY="${CEDAR_PROD_SSH_KEY/#\~/$HOME}"
LOCAL_DATA_DIR="${CEDAR_DATA_DIR:-$(env_value CEDAR_DATA_DIR)}"
LOCAL_DATA_DIR="${LOCAL_DATA_DIR:-$REPO_ROOT/data}"
LOCAL_OUTPUT_DIR="$REPO_ROOT/output/projections"

[[ -n "$CEDAR_PROD_SSH" ]] || die "Set CEDAR_PROD_SSH (login@host) in the environment or .env"
[[ -n "$CEDAR_PROD_DATA_DIR" ]] || die "Set CEDAR_PROD_DATA_DIR (production's data directory) in the environment or .env"
! $PROJECTIONS || [[ -n "$CEDAR_PROD_OUTPUT_DIR" ]] ||
  die "--projections needs CEDAR_PROD_OUTPUT_DIR (production's <repo>/output) in the environment or .env"
[[ -d "$LOCAL_DATA_DIR" ]] || die "Local data directory does not exist: $LOCAL_DATA_DIR"

KEY_OPTS=()
if [[ -n "$CEDAR_PROD_SSH_KEY" ]]; then
  [[ -r "$CEDAR_PROD_SSH_KEY" ]] || die "CEDAR_PROD_SSH_KEY is not a readable file: $CEDAR_PROD_SSH_KEY"
  KEY_OPTS=(-i "$CEDAR_PROD_SSH_KEY" -o IdentitiesOnly=yes)
fi
SSH_OPTS=(-p "$CEDAR_PROD_SSH_PORT" ${KEY_OPTS[@]+"${KEY_OPTS[@]}"} -o BatchMode=no -o ConnectTimeout=15)
SFTP_OPTS=(-P "$CEDAR_PROD_SSH_PORT" ${KEY_OPTS[@]+"${KEY_OPTS[@]}"} -o ConnectTimeout=15)

run() {
  if $DRY_RUN; then printf '  [dry-run]'; printf ' %q' "$@"; echo; else "$@"; fi
}

if [[ "$METHOD" == auto ]]; then
  # ssh exits 255 for its own failures (refused, timed out, key rejected) and
  # otherwise with the remote command's status. Only the second means the
  # account has no shell or no rsync; a failed connection stops here rather
  # than becoming an sftp attempt that fails the same way with a vaguer message.
  probe_err="$(ssh "${SSH_OPTS[@]}" "$CEDAR_PROD_SSH" 'command -v rsync' 2>&1 >/dev/null)"
  probe_status=$?
  if [[ $probe_status -eq 255 ]]; then
    die "Could not connect to $CEDAR_PROD_SSH: ${probe_err:-ssh exited 255}"
  elif [[ $probe_status -ne 0 ]]; then
    warn "Production runs no rsync for this login; using sftp"
    METHOD=sftp
  elif ! command -v rsync >/dev/null 2>&1; then
    warn "rsync is not installed locally; using sftp"
    METHOD=sftp
  else
    METHOD=rsync
  fi
fi
step "Production: $CEDAR_PROD_SSH:$CEDAR_PROD_DATA_DIR (method: $METHOD)"
step "Local:      $LOCAL_DATA_DIR"

if $LIST_ONLY; then
  if [[ "$METHOD" == rsync ]]; then
    ssh "${SSH_OPTS[@]}" "$CEDAR_PROD_SSH" \
      "ls -la $(printf '%q' "$CEDAR_PROD_DATA_DIR")/cedar_*.qs $(printf '%q' "$CEDAR_PROD_DATA_DIR")/cedar-status.json"
  else
    printf 'ls -l %s/cedar_*.qs\nls -l %s/cedar-status.json\n' \
      "$CEDAR_PROD_DATA_DIR" "$CEDAR_PROD_DATA_DIR" |
      sftp "${SFTP_OPTS[@]}" -b - "$CEDAR_PROD_SSH"
  fi
  exit $?
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$LOCAL_DATA_DIR/.backup-$STAMP"

# Copy matching files from a remote directory into a local one, keeping any
# local file it replaces under $3.
pull_dir() {
  local remote_dir="$1" local_dir="$2" backup_dir="$3"; shift 3
  local patterns=("$@")
  mkdir -p "$local_dir"
  if [[ "$METHOD" == rsync ]]; then
    local filters=()
    for p in "${patterns[@]}"; do filters+=(--include="$p"); done
    run rsync -av --partial --backup --backup-dir="$backup_dir" \
      -e "ssh $(printf '%q ' "${SSH_OPTS[@]}")" "${filters[@]}" --exclude='*' \
      "$CEDAR_PROD_SSH:$remote_dir/" "$local_dir/"
  else
    # sftp has no backup option: download into a staging folder, then move
    # each file into place, keeping the one it replaces.
    local stage
    stage="$(mktemp -d "$local_dir/.pull-XXXXXX")"
    local batch=""
    for p in "${patterns[@]}"; do batch+="-get $remote_dir/$p $stage/"$'\n'; done
    if $DRY_RUN; then
      echo "  [dry-run] sftp ${SFTP_OPTS[*]} -b - $CEDAR_PROD_SSH <<< '$batch'"
      rmdir "$stage"; return 0
    fi
    printf '%s' "$batch" | sftp "${SFTP_OPTS[@]}" -b - "$CEDAR_PROD_SSH" ||
      { rm -rf "$stage"; die "sftp failed"; }
    local f name
    for f in "$stage"/*; do
      [[ -e "$f" ]] || continue
      name="$(basename "$f")"
      [[ -s "$f" ]] || { warn "Skipped empty download: $name"; continue; }
      if [[ -e "$local_dir/$name" ]] && ! cmp -s "$f" "$local_dir/$name"; then
        mkdir -p "$backup_dir"; mv "$local_dir/$name" "$backup_dir/$name"
      fi
      mv "$f" "$local_dir/$name"
      echo "  $name"
    done
    rm -rf "$stage"
  fi
}

step "Copying prepared tables"
pull_dir "$CEDAR_PROD_DATA_DIR" "$LOCAL_DATA_DIR" "$BACKUP_DIR" 'cedar_*.qs' 'cedar-status.json' ||
  die "Copying the prepared tables failed"

if $PROJECTIONS; then
  step "Copying projection bundles"
  pull_dir "$CEDAR_PROD_OUTPUT_DIR/projections" "$LOCAL_OUTPUT_DIR" \
    "$LOCAL_OUTPUT_DIR/.backup-$STAMP" '*.qs' ||
    die "Copying the projection bundles failed"
fi

if ! $DRY_RUN; then
  if [[ -d "$BACKUP_DIR" ]]; then
    ok "Replaced files are kept in $BACKUP_DIR"
  else
    ok "No local file needed replacing"
  fi
  if [[ -x "$SCRIPT_DIR/data-status.sh" ]]; then
    "$SCRIPT_DIR/data-status.sh" --data-dir "$LOCAL_DATA_DIR"
  fi
  echo "Restart the app to read the new files: scripts/restart-cedar.sh"
fi
