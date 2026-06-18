#!/bin/bash
set -e

# Optional Plumber JSON API (plumber.R, GET /dashboard) — DISABLED by default.
# It runs as a second R process that loads the full dataset into memory, so we
# don't run it unless something actually consumes it. To re-enable: uncomment the
# line below, add 8000 back to EXPOSE (Dockerfile.shiny) and the port mapping
# (docker-compose.yml), then rebuild.
# Rscript -e "plumber::plumb('/srv/shiny-server/cedar/plumber.R')\$run(host='0.0.0.0', port=8000)" &

# Forward shiny-server R process logs to Docker stdout as they appear.
# Shiny Server writes each session's R stderr to a new timestamped file in
# /var/log/shiny-server/. This loop tails any new .log files so they appear
# in `docker logs` / the terminal window.
mkdir -p /var/log/shiny-server
(
  declare -A seen
  while true; do
    for f in /var/log/shiny-server/*.log; do
      [ -f "$f" ] || continue
      if [ -z "${seen[$f]+x}" ]; then
        seen[$f]=1
        tail -F "$f" --pid=$$ 2>/dev/null &
      fi
    done
    sleep 2
  done
) &

# Start Shiny Server in the foreground (keeps the container alive)
exec /usr/bin/shiny-server
