#!/usr/bin/env bash
# Reproducible dev loop for the dockerized CEDAR Shiny app.
#
#   ./rebuild-and-test.sh [tab-slug]
#
# Rebuilds the image from the current source and restarts the container, then
# waits until the app answers. The R-package layer in Dockerfile.shiny is cached,
# so only the `COPY . .` layer re-runs on a code change — fast after the first
# (cold) build. Pass a tab slug (e.g. registration, pathways, waitlists) to print
# a deep link straight to that tab.
#
# Requires CEDAR_DATA_DIR in .env (already set) for the data volume mount.
set -euo pipefail
cd "$(dirname "$0")"

URL="http://localhost:3838/"

echo "[rebuild] building image + (re)starting container…"
docker compose up -d --build

echo "[rebuild] waiting for app at ${URL} …"
# Shiny Server answers the app HTML with 200 once the worker is reachable. The
# first websocket connection then runs global.R (the heavy data load), so the
# browser may still show a brief loading state after this returns.
up=0
for _ in $(seq 1 120); do
  if curl -sf -o /dev/null "${URL}"; then up=1; echo "[rebuild] app is up."; break; fi
  sleep 3
done
[ "${up}" -eq 1 ] || { echo "[rebuild] timed out waiting for app"; docker compose logs --tail 40; exit 1; }

tab="${1:-}"
if [ -n "${tab}" ]; then
  echo "[rebuild] browse: ${URL}?tab=${tab}"
else
  echo "[rebuild] browse: ${URL}"
fi
