#!/usr/bin/env bash
#
# data-status.sh — Show current state of CEDAR data files
#
# Reads cedar-status.json (written by transform-to-cedar.R) and
# parse-data-summary.log without loading any large data files.
#
# Usage:
#   scripts/data-status.sh [--data-dir PATH]
#
# Run from the project root or any subdirectory.

# ── Colors ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $*"; }
err()  { echo -e "  ${RED}✗${NC} $*"; }
hdr()  { echo -e "\n${BOLD}${BLUE}$*${NC}"; }

# ── Locate project root ───────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# ── Parse args ────────────────────────────────────────────────────────────────
DATA_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --data-dir) DATA_DIR="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--data-dir PATH]"
      echo "  Default data dir: <project-root>/data"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

[[ -z "$DATA_DIR" ]] && DATA_DIR="$PROJECT_ROOT/data"

STATUS_JSON="$DATA_DIR/cedar-status.json"
PARSE_LOG="$DATA_DIR/parse-data-summary.log"

# ── Portable mtime (macOS BSD stat vs Linux GNU stat) ─────────────────────────
get_mtime() {
  stat -f "%m" "$1" 2>/dev/null || stat -c "%Y" "$1" 2>/dev/null
}
get_mtime_str() {
  stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$1" 2>/dev/null \
    || stat -c "%y" "$1" 2>/dev/null | cut -c1-16
}

# ── Header ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}CEDAR Data Status${NC}  ${DIM}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${DIM}Data dir: $DATA_DIR${NC}"
echo "────────────────────────────────────────────────────────"

# ── Cedar tables ─────────────────────────────────────────────────────────────
hdr "Cedar Tables"

if [[ ! -f "$STATUS_JSON" ]]; then
  warn "cedar-status.json not found — run transform-to-cedar.R to generate it"
  echo -e "  ${DIM}Showing filesystem info instead:${NC}"
  for f in "$DATA_DIR"/cedar_*.qs; do
    [[ -f "$f" ]] || continue
    [[ "$f" == *"-original.qs" ]] && continue
    name=$(basename "$f" .qs)
    size=$(du -sh "$f" 2>/dev/null | cut -f1)
    mtime=$(get_mtime_str "$f")
    printf "  %-22s  %6s  %s\n" "$name" "$size" "$mtime"
  done
elif ! python3 -m json.tool "$STATUS_JSON" >/dev/null 2>&1; then
  warn "cedar-status.json is invalid JSON — rerun transform-to-cedar.R to regenerate it"
  echo -e "  ${DIM}Showing filesystem info instead:${NC}"
  for f in "$DATA_DIR"/cedar_*.qs; do
    [[ -f "$f" ]] || continue
    [[ "$f" == *"-original.qs" ]] && continue
    name=$(basename "$f" .qs)
    size=$(du -sh "$f" 2>/dev/null | cut -f1)
    mtime=$(get_mtime_str "$f")
    printf "  %-22s  %6s  %s\n" "$name" "$size" "$mtime"
  done
else
  python3 - "$STATUS_JSON" << 'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    status = json.load(f)

generated = status.get("generated", "unknown")
tables = status.get("tables", {})

print(f"  Generated: {generated}\n")
print(f"  {'Table':<18}  {'Rows':>10}  {'Size':>7}  {'As-of Date':>12}  {'Term Range'}")
print(f"  {'-'*18}  {'-'*10}  {'-'*7}  {'-'*12}  {'-'*20}")

for name, info in tables.items():
    rows   = f"{info.get('rows', 0):,}"
    size   = f"{info.get('size_mb', 0):.1f} MB"
    as_of  = info.get("as_of_date") or "—"
    min_t  = info.get("min_term") or "?"
    max_t  = info.get("max_term") or "?"
    terms  = f"{min_t} – {max_t}" if min_t != max_t else min_t
    print(f"  {'cedar_'+name:<18}  {rows:>10}  {size:>7}  {as_of:>12}  {terms}")
PYEOF
fi

# ── Last parse run ────────────────────────────────────────────────────────────
hdr "Last Parse Run"

if [[ ! -f "$PARSE_LOG" ]]; then
  warn "parse-data-summary.log not found"
else
  python3 - "$PARSE_LOG" << 'PYEOF'
import sys, re

with open(sys.argv[1]) as f:
    content = f.read()

blocks = re.split(r'(?=---- parse-data summary ----)', content.strip())
blocks = [b.strip() for b in blocks if b.strip()]

if not blocks:
    print("  No parse runs found in log.")
    sys.exit(0)

last = blocks[-1]
lines = last.splitlines()

start = end = status = ""
reports = []
current_report = None

for line in lines:
    if m := re.match(r'Run start:\s+(.+)', line):
        start = m.group(1)
    elif m := re.match(r'Run end:\s+(.+)', line):
        end = m.group(1)
    elif m := re.match(r'Status:\s+(.+)', line):
        status = m.group(1).strip()
    elif m := re.match(r'\s{2}- (\w+)', line):
        current_report = {"name": m.group(1), "found": 0, "processed": 0, "as_of": None}
        reports.append(current_report)
    elif current_report and (m := re.match(r'\s+Files found \((\d+)\)', line)):
        current_report["found"] = int(m.group(1))
    elif current_report and (m := re.match(r'\s+Files processed \((\d+)\)', line)):
        current_report["processed"] = int(m.group(1))
    elif current_report and (m := re.match(r'\s+As of date:\s+(.+)', line)):
        current_report["as_of"] = m.group(1).strip()

icon = "✓" if status == "success" else "✗"
print(f"  {icon} {start}  →  {end}  [{status}]")
if reports:
    print()
    for r in reports:
        as_of_str = f"  as_of={r['as_of']}" if r['as_of'] else ""
        r_icon = "✓" if r["processed"] > 0 else "–"
        print(f"    {r_icon} {r['name']:<6}  {r['processed']} file(s) processed{as_of_str}")

total = len(blocks)
if total > 1:
    print(f"\n  {total} total runs in log.")
PYEOF
fi

# ── Sync check (cedar_ files vs intermediate files) ───────────────────────────
hdr "Pipeline Sync"

SYNC_OK=true

check_sync() {
  local cedar_file="$1"
  local src_file="$2"
  local cedar_path="$DATA_DIR/$cedar_file"
  local src_path="$DATA_DIR/$src_file"

  if [[ ! -f "$cedar_path" ]]; then
    err "$cedar_file  missing"
    SYNC_OK=false
    return
  fi
  if [[ ! -f "$src_path" ]]; then
    warn "$cedar_file  (source $src_file not found)"
    return
  fi

  local c_mtime s_mtime c_ts s_ts
  c_mtime=$(get_mtime "$cedar_path")
  s_mtime=$(get_mtime "$src_path")
  c_ts=$(get_mtime_str "$cedar_path")
  s_ts=$(get_mtime_str "$src_path")

  if [[ -z "$c_mtime" || -z "$s_mtime" ]]; then
    warn "Cannot read timestamps: $cedar_file"
    return
  fi

  if (( s_mtime > c_mtime )); then
    warn "$cedar_file (${c_ts}) older than $src_file (${s_ts}) — transform may need re-run"
    SYNC_OK=false
  else
    ok "$cedar_file (${c_ts})  ←  $src_file (${s_ts})"
  fi
}

check_sync "cedar_sections.qs"  "DESRs.qs"
check_sync "cedar_students.qs"  "class_lists.qs"
check_sync "cedar_programs.qs"  "academic_studies.qs"
check_sync "cedar_degrees.qs"   "degrees.qs"

# ── CSV / QS parity ───────────────────────────────────────────────────────────
hdr "CSV / QS Parity"

PARITY_OK=true

for qs_file in "$DATA_DIR"/*.qs; do
  [[ -f "$qs_file" ]] || continue
  base=$(basename "$qs_file" .qs)
  [[ "$base" == cedar_* ]] && continue       # cedar_ files have no paired CSV
  csv_file="$DATA_DIR/$base.csv"
  if [[ ! -f "$csv_file" ]]; then
    warn "$base.qs has no matching .csv"
    continue
  fi
  qs_mtime=$(get_mtime "$qs_file")
  csv_mtime=$(get_mtime "$csv_file")
  if [[ -z "$qs_mtime" || -z "$csv_mtime" ]]; then
    warn "Cannot read timestamps: $base"
    continue
  fi
  skew=$(( qs_mtime - csv_mtime ))
  (( skew < 0 )) && skew=$(( -skew ))
  if (( skew > 60 )); then
    warn "$base.qs and $base.csv differ by ${skew}s — may be out of sync"
    PARITY_OK=false
  else
    ok "$base  (.qs + .csv in sync)"
  fi
done

# ── Footer ────────────────────────────────────────────────────────────────────
echo ""
if $SYNC_OK && $PARITY_OK; then
  echo -e "${GREEN}${BOLD}All checks passed.${NC}"
else
  echo -e "${YELLOW}${BOLD}Some issues detected — see warnings above.${NC}"
fi
echo ""
