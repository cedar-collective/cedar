# Tests for the small Data & Usage administration modules.

context("Admin modules")

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
})

source(file.path(cedar_base_dir, "R", "modules", "ui-helpers.R"))
source(file.path(cedar_base_dir, "R", "modules", "admin.R"))

test_that("Cache UI exposes the report timing reset control", {
  html <- as.character(cacheUI("cache"))

  expect_match(html, "Report Timing Estimates", fixed = TRUE)
  expect_match(html, "cache-refresh_timing_stats", fixed = TRUE)
  expect_match(html, "cache-reset_report_timings", fixed = TRUE)
  expect_match(html, "Reset Timing History", fixed = TRUE)
})

test_that("loading overlays request current timing estimates when opened", {
  html <- as.character(cedar_loading_overlay(
    "demo", "run",
    report_type = "demo-report",
    fresh_default = 8,
    cached_default = 2
  ))

  expect_match(html, "cedar_timing_estimate_request", fixed = TRUE)
  expect_match(html, "_timing_estimates", fixed = TRUE)
  expect_match(html, "demo-report", fixed = TRUE)
  expect_match(html, "cedar_client_render_timing", fixed = TRUE)
  expect_match(html, "payload_bytes", fixed = TRUE)
  expect_match(html, "fresh_range", fixed = TRUE)
  expect_match(html, "queue_delivery_sec", fixed = TRUE)
  expect_match(html, "browser_settle_sec", fixed = TRUE)
  expect_match(html, "operation_id", fixed = TRUE)
})

test_that("loading overlays can explain a multi-part preload", {
  html <- as.character(cedar_loading_overlay(
    "demo", "run",
    loading_label = "Preparing department trends…",
    loading_detail = "Loading the visible tabs now so they are ready later."
  ))

  expect_match(html, "Preparing department trends", fixed = TRUE)
  expect_match(html, "Loading the visible tabs now", fixed = TRUE)
  expect_match(html, 'role="dialog"', fixed = TRUE)
  expect_match(html, 'aria-modal="true"', fixed = TRUE)
})

test_that("loading overlays embed learned ranges before a report can block", {
  old_estimator <- report_time_estimates
  assign("report_time_estimates", function(...) list(
    fresh = 7L, cached = 2L,
    fresh_range = list(lower = 7L, upper = 29L),
    cached_range = list(lower = 2L, upper = 5L)
  ), envir = .GlobalEnv)
  on.exit(assign("report_time_estimates", old_estimator,
                 envir = .GlobalEnv), add = TRUE)

  html <- as.character(cedar_loading_overlay(
    "demo", "run", report_type = "demo-report",
    fresh_default = 8, cached_default = 2
  ))

  expect_match(html, 'var EXPECTED = 7, CACHED = 2', fixed = TRUE)
  expect_match(html, '{"lower":7,"upper":29}', fixed = TRUE)
})
