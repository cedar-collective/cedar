# What the tests in test-cache.R share: builders, option lists, constants.

# Override cache dir to a per-test tempdir so tests don't touch production data.
# Restore after each test.
with_temp_cache <- function(code) {
  tmp <- tempfile()
  dir.create(tmp)
  old_base <- cedar_base_dir
  assign("cedar_base_dir", dirname(tmp), envir = .GlobalEnv)
  # get_cache_dir() builds: cedar_base_dir/data/cache — create that path
  cache_path <- file.path(dirname(tmp), "data", "cache")
  dir.create(cache_path, recursive = TRUE)
  on.exit({
    assign("cedar_base_dir", old_base, envir = .GlobalEnv)
    unlink(file.path(dirname(tmp), "data"), recursive = TRUE)
  }, add = TRUE)
  force(code)
}
