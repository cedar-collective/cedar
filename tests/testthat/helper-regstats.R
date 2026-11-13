# What the tests in test-regstats.R share: builders, option lists, constants.

regstats_history_opt <- function(term = 202080L) {
  list(term = term, bypass_cache = TRUE,
       thresholds = list(min_impacted = 1, pct_sd = 1, chronic_fill_rate = .60,
                         min_sat_terms = 1, min_wait = 1, section_proximity = .3))
}
