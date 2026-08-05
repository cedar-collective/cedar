#!/bin/bash
set -e

# Force UTF-8 so shiny-server's R worker (and Plumber, if enabled) read qs2 data
# without "translating to UTF-8" locale warnings. Belt-and-suspenders with the
# ENV in Dockerfile.shiny, since shiny-server does not always pass it through.
export LANG=C.UTF-8 LC_ALL=C.UTF-8

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
log_watch_marker="/tmp/cedar-shiny-log-watch-start.$$"
touch "$log_watch_marker"
(
  declare -A offsets
  while true; do
    for f in /var/log/shiny-server/*.log; do
      [ -f "$f" ] || continue
      size=$(stat -c %s "$f" 2>/dev/null || true)
      [ -n "$size" ] || continue
      if [ -z "${offsets[$f]+x}" ]; then
        # Retained logs from a previous container run are not replayed.
        if [ "$f" -nt "$log_watch_marker" ]; then offsets[$f]=0; else offsets[$f]=$size; fi
      fi
      start=${offsets[$f]}
      if [ "$size" -lt "$start" ]; then start=0; fi
      if [ "$size" -gt "$start" ]; then
        tail -c +$((start + 1)) "$f" 2>/dev/null || true
        offsets[$f]=$size
      fi
    done
    sleep 2
  done
) &

# Start Shiny Server in the foreground (keeps the container alive)
exec /usr/bin/shiny-server
