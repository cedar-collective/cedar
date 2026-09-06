# Dependency/setup contracts use no institutional data or network access.
project_root <- normalizePath(file.path(getwd(), "../.."))
env <- new.env(parent = globalenv())
original_paths <- .libPaths()
sys.source(file.path(project_root, "scripts", "r-environment.R"), envir = env)

test_that("dependency helpers are inert when sourced", {
  expect_identical(.libPaths(), original_paths)
  expect_type(env$cedar_restore_dependencies, "closure")
  expect_output(env$cedar_r_environment_main("help"), "read-only")
  expect_error(env$cedar_r_environment_main("upgrade"), "Usage:")
  expect_error(env$cedar_r_environment_main(character()), "Usage:")
})

test_that("the lock pins the tested runtime, bootstrap, and compiled qs2 chain", {
  lock <- env$cedar_dependency_lock(project_root)
  docker <- readLines(file.path(project_root, "Dockerfile.shiny"))
  expect_match(docker[1], paste0("rocker/shiny:", lock$R$Version), fixed = TRUE)
  expect_identical(lock$Packages$renv$Version, "1.1.1")
  expect_identical(lock$Packages$shiny$Version, "1.10.0")
  expect_identical(lock$Packages$dplyr$Version, "1.1.4")
  expect_identical(lock$Packages$qs2$Version, "0.2.2")
  expect_true(all(c("RcppParallel", "stringfish", "testthat", "reactable", "tidyverse") %in%
                    names(lock$Packages)))
  expect_false(grepl("latest", lock$R$Repositories[[1]]$URL))
  activate <- paste(readLines(file.path(project_root, "renv", "activate.R")), collapse = "\n")
  expect_match(activate, paste0('version <- "', lock$Packages$renv$Version, '"'), fixed = TRUE)
  restore <- grep("restore-docker", docker)
  expect_length(restore, 1)
  expect_lt(restore, grep("COPY . .", docker, fixed = TRUE))
  expect_true(any(grepl("COPY renv.lock", docker, fixed = TRUE)))
  expect_false(any(grepl("install.packages", docker, fixed = TRUE)))
  expect_false(jsonlite::fromJSON(file.path(project_root, "renv", "settings.json"))$use.cache)
})

test_that("drift checks report wrong R, wrong packages, missing packages, and precedence", {
  lock <- env$cedar_dependency_lock(project_root)
  lock$Packages <- lock$Packages[c("dplyr", "qs2", "renv")]
  installed <- rbind(c("dplyr", "0.0.0"), c("dplyr", "1.1.4"), c("qs2", "0.2.2"))
  colnames(installed) <- c("Package", "Version")
  status <- env$cedar_dependency_status(lock, installed, r_version = "0.0.0")
  expect_identical(status$package, c("R", "dplyr", "qs2", "renv"))
  expect_identical(status$installed[1:3], c("0.0.0", "0.0.0", "0.2.2"))
  expect_true(is.na(status$installed[4]))
  expect_identical(status$expected, c("4.4.2", "1.1.4", "0.2.2", "1.1.1"))
})

test_that("native selection is explicit and rejects absent or stale readiness markers", {
  root <- withr::local_tempdir()
  before <- .libPaths()
  expect_false(env$cedar_use_native_library(root, required = FALSE))
  expect_identical(.libPaths(), before)
  expect_error(env$cedar_use_native_library(root), "not prepared")
  library <- env$cedar_native_library(root)
  expect_true(startsWith(library, file.path(root, "renv", "library", "cedar")))
  expect_match(library, R.version$platform, fixed = TRUE)
  dir.create(library, recursive = TRUE)
  file.copy(file.path(project_root, "renv.lock"), file.path(root, "renv.lock"))
  writeLines("stale", file.path(library, ".cedar-ready"))
  expect_error(env$cedar_use_native_library(root), "different lockfile")
  expect_identical(.libPaths(), before)
  withr::local_libpaths(before)
  withr::local_envvar(c(R_LIBS = NA, R_LIBS_USER = NA))
  writeLines(unname(tools::md5sum(file.path(root, "renv.lock"))),
             file.path(library, ".cedar-ready"))
  expect_true(env$cedar_use_native_library(root))
  expect_identical(.libPaths()[1], normalizePath(library))
  expect_identical(Sys.getenv("R_LIBS"), library)
  expect_identical(Sys.getenv("R_LIBS_USER"), library)
})

test_that("startup cannot install packages or activate the old cache-linked library", {
  profile <- paste(readLines(file.path(project_root, ".Rprofile")), collapse = "\n")
  expect_false(grepl("install.packages\\(|renv::|source\\(\"renv/activate|p_load\\(", profile))
  expect_match(profile, "cedar_use_native_library(required = FALSE)", fixed = TRUE)
  expect_match(profile, "load_global_data(opt = NULL)", fixed = TRUE)
  expect_match(profile, "interactive() && !shiny_startup && !in_docker", fixed = TRUE)
  expect_match(profile, 'file.exists("config/config.R")', fixed = TRUE)
  expect_error(parse(text = profile), NA)
})

test_that("matching installed binaries are copied, not linked or silently substituted", {
  root <- withr::local_tempdir()
  source <- file.path(root, "source")
  target <- file.path(root, "target")
  dir.create(file.path(source, "qs2"), recursive = TRUE)
  dir.create(target)
  writeLines("original", file.path(source, "qs2", "payload"))
  lock <- env$cedar_dependency_lock(project_root)
  lock$Packages <- lock$Packages["qs2"]
  installed <- matrix(c("qs2", "0.0.0", source), nrow = 1,
                      dimnames = list(NULL, c("Package", "Version", "LibPath")))
  env$cedar_seed_library(lock, target, installed)
  expect_false(dir.exists(file.path(target, "qs2")))
  installed[1, "Version"] <- lock$Packages$qs2$Version
  env$cedar_seed_library(lock, target, installed)
  expect_identical(readLines(file.path(target, "qs2", "payload")), "original")
  writeLines("changed", file.path(target, "qs2", "payload"))
  expect_identical(readLines(file.path(source, "qs2", "payload")), "original")
  env$cedar_seed_library(lock, target, installed)
  expect_identical(readLines(file.path(target, "qs2", "payload")), "changed")
})

test_that("a newer installed renv does not block bootstrapping the pinned version", {
  # Test installation decisions without network access or changing libraries.
  sandbox <- new.env(parent = env)
  bootstrap <- env$cedar_bootstrap_renv
  environment(bootstrap) <- sandbox
  installed <- FALSE
  sandbox$loadedNamespaces <- function() character()
  sandbox$find.package <- function(...) "/existing/renv"
  sandbox$packageVersion <- function(...) package_version(if (installed) "1.1.1" else "1.2.4")
  sandbox$requireNamespace <- function(...) installed
  sandbox$install.packages <- function(pkgs, repos, type, lib) {
    expect_match(pkgs, "renv_1.1.1.tar.gz", fixed = TRUE)
    expect_null(repos)
    expect_identical(type, "source")
    installed <<- TRUE
  }
  sandbox$.libPaths <- function(...) original_paths
  temporary <- withr::local_tempdir()
  sandbox$tempfile <- function(...) file.path(temporary, "bootstrap")
  expect_identical(bootstrap(project_root), "1.1.1")
  expect_true(installed)
  sandbox$loadedNamespaces <- function() "renv"
  sandbox$getNamespaceVersion <- function(...) package_version("1.2.4")
  expect_error(bootstrap(project_root), "fresh Rscript --vanilla")
})

test_that("the canonical gate keeps system R by default and offers pinned native R", {
  runner <- file.path(project_root, "run-tests.sh")
  text <- paste(readLines(runner), collapse = "\n")
  expect_match(text, "PROJECT_LIBRARY=0", fixed = TRUE)
  expect_match(text, "--project-library) PROJECT_LIBRARY=1", fixed = TRUE)
  expect_match(text, "cedar_check_dependencies(library = cedar_native_library())", fixed = TRUE)
  expect_equal(system2("bash", c("-n", shQuote(runner))), 0)
  expect_equal(system2("bash", c(shQuote(runner), "--project-library", "--test-image", "fake"),
                       stdout = FALSE, stderr = FALSE), 2)
})
