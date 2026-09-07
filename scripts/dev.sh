#!/usr/bin/env bash
# Docker-only first-hour workflow. No production Compose file or .env is read.
set -euo pipefail
cd "$(dirname "$0")/.."
action="${1:-help}"
case "$action" in
  up|restart|test|logs|down) ;;
  help|--help|-h)
    echo "Usage: bash scripts/dev.sh {up|restart|test|logs|down}"
    echo "Synthetic demo: http://localhost:${CEDAR_DEV_PORT:-3838}/"
    echo "up builds/prepares data; restart reloads edits; down preserves demo data."
    exit 0 ;;
  *) echo "Unknown command: $action" >&2; exit 2 ;;
esac
command -v docker >/dev/null || { echo "Install and start Docker Desktop first." >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker is not running. Start Docker and retry." >&2; exit 1; }
compose=(docker compose --env-file /dev/null -p cedar-demo -f compose.dev.yml)
case "$action" in
  up)
    # Do not let a running worker read a half-published new synthetic bundle.
    "${compose[@]}" stop cedar-dev
    "${compose[@]}" up -d --build --force-recreate
    echo "Open http://localhost:${CEDAR_DEV_PORT:-3838}/ (first app load takes a little longer)."
    echo "Save edits, then: bash scripts/dev.sh restart"
    ;;
  restart)
    "${compose[@]}" restart cedar-dev
    echo "Refresh http://localhost:${CEDAR_DEV_PORT:-3838}/ to load your edits."
    ;;
  test)
    # Fresh, disposable source snapshot: tests may write diagnostic fixtures.
    # Standard data/output and .env/.Renviron paths are Docker-ignored.
    # The fixture gate does not load machine-local production configuration.
    docker build --platform linux/amd64 -f Dockerfile.shiny --target app -t cedar-demo-tests .
    docker run --rm --platform linux/amd64 --user root --entrypoint bash cedar-demo-tests ./run-tests.sh
    ;;
  logs) "${compose[@]}" logs --tail 100 -f cedar-dev demo-init ;;
  down) "${compose[@]}" down ;;
esac
