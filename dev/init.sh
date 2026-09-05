#!/usr/bin/env bash
set -euo pipefail
Rscript --vanilla dev/generate-demo.R
mkdir -p data/logs output app_cache
chown -R shiny:shiny data output app_cache
