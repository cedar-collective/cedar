#!/usr/bin/env Rscript
#
# warm-cas-dept-profiles.R
#
# Pre-generates the active Dept Trends headcount cache for all College of Arts &
# Sciences departments. Run weekly (after the cache key rolls over on Monday) so
# profiles are ready before anyone opens the app.
#
# Usage:
#   Rscript scripts/warm-cas-dept-profiles.R
#   OR
#   source("scripts/warm-cas-dept-profiles.R")
#
# The dept profile cache key uses an ISO week number (YYYY-WNN), so it expires
# at the start of each new week. Run this script once a week - e.g., as a cron
# job on Monday morning - to warm the cache before users arrive.
#
# To clear dept profile cache files:
#   source("R/trunk/cache.R")
#   clear_dept_cache()

# ── Setup ─────────────────────────────────────────────────────────────────────

if (basename(getwd()) == "scripts") setwd("..")

suppressMessages(source("global.R"))

# ── CAS Department List ───────────────────────────────────────────────────────
#
# Derived from hr_org_desc_to_dept (mappings.R): entries whose HR org description
# starts with "AS " belong to the College of Arts & Sciences.
# Collapse duplicates (e.g. "AS Biology" and "AS Biology General Administrative"
# both map to BIOL).

cas_depts <- sort(unique(unname(
  hr_org_desc_to_dept[grep("^AS ", names(hr_org_desc_to_dept))]
)))

message("\n[warm-cas-dept-profiles] CAS departments to warm (", length(cas_depts), "):")
message("  ", paste(cas_depts, collapse = ", "))

# ── Pre-generate ──────────────────────────────────────────────────────────────

results  <- character(length(cas_depts))
names(results) <- cas_depts
t_start  <- proc.time()

for (dept in cas_depts) {
  message("\n--- ", dept, " ---")
  t_dept <- proc.time()

  tryCatch({
    # Check whether a valid cache entry already exists for this week.
    existing <- load_dept_headcount_cache(dept, data_objects)
    if (!is.null(existing)) {
      message("[warm-cas-dept-profiles] Cache already current for ", dept, " - skipping.")
      results[dept] <- "skipped"
      next
    }

    # MUST be dept_code: create_dept_report_base() reads opt[["dept_code"]].
    # With `dept` it built a NULL-department payload and cache_dept_headcount()
    # then stored it under the CORRECT dept key — poisoning the Dept Trends
    # cache with empty data rather than simply missing.
    opt  <- list(shiny = TRUE, dept_code = dept)
    data <- create_dept_report_base(data_objects, opt)
    ok   <- cache_dept_headcount(dept, data, data_objects)

    elapsed <- round((proc.time() - t_dept)[["elapsed"]], 1)
    if (ok) {
      message("[warm-cas-dept-profiles] ", dept, " cached (", elapsed, "s)")
      results[dept] <- "ok"
    } else {
      message("[warm-cas-dept-profiles] ", dept, " generated but cache write failed")
      results[dept] <- "cache_failed"
    }

  }, error = function(e) {
    message("[warm-cas-dept-profiles] ERROR for ", dept, ": ", e$message)
    results[dept] <<- paste0("error: ", e$message)
  })
}

# ── Summary ───────────────────────────────────────────────────────────────────

total_elapsed <- round((proc.time() - t_start)[["elapsed"]])
message("\n============================")
message("[warm-cas-dept-profiles] Done in ", total_elapsed, "s")
message("  ok:      ", sum(results == "ok"))
message("  skipped: ", sum(results == "skipped"))
message("  failed:  ", sum(!results %in% c("ok", "skipped")))

failed <- names(results)[!results %in% c("ok", "skipped")]
if (length(failed) > 0) {
  message("\nFailed departments:")
  for (d in failed) message("  ", d, ": ", results[d])
}
