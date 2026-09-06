# Shared dependency setup for native R and Docker. Safe to source: no installs,
# library changes, data loading, or project activation happen until requested.
# CLI (from the repo root): Rscript --vanilla scripts/r-environment.R help

cedar_native_library <- function(root = getwd()) {
  file.path(root, "renv", "library", "cedar",
            paste0("R-", getRversion()), R.version$platform)
}

cedar_use_native_library <- function(root = getwd(), required = TRUE) {
  library <- cedar_native_library(root)
  if (!file.exists(file.path(library, ".cedar-ready"))) {
    if (required) stop("Native library is not prepared. Run: ",
                       "Rscript --vanilla scripts/r-environment.R restore", call. = FALSE)
    return(invisible(FALSE))
  }
  if (!identical(readLines(file.path(library, ".cedar-ready"), warn = FALSE),
                 unname(tools::md5sum(file.path(root, "renv.lock"))))) {
    stop("The native library was prepared for a different lockfile. Run the restore command.",
         call. = FALSE)
  }
  .libPaths(c(library, .Library))
  # Vanilla child R processes (including parser fixture tests) must use the
  # same pinned packages, not silently fall back to the host's system library.
  Sys.setenv(R_LIBS = library, R_LIBS_USER = library)
  invisible(TRUE)
}

cedar_dependency_lock <- function(root = getwd()) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("jsonlite is unavailable. Run the explicit restore command or use Docker.",
         call. = FALSE)
  }
  jsonlite::fromJSON(file.path(root, "renv.lock"), simplifyVector = FALSE)
}

cedar_dependency_status <- function(lock, installed = installed.packages(),
                                    r_version = as.character(getRversion())) {
  expected <- vapply(lock$Packages, `[[`, character(1), "Version")
  # Respect library precedence if installed.packages() returns duplicate names.
  installed <- installed[!duplicated(installed[, "Package"]), , drop = FALSE]
  actual <- setNames(installed[, "Version"], installed[, "Package"])[names(expected)]
  data.frame(package = c("R", names(expected)),
             expected = c(lock$R$Version, unname(expected)),
             installed = c(r_version, unname(actual)), stringsAsFactors = FALSE)
}

cedar_check_dependencies <- function(root = getwd(), library = .libPaths(),
                                     quiet = FALSE) {
  status <- cedar_dependency_status(cedar_dependency_lock(root),
                                   installed.packages(lib.loc = library))
  bad <- is.na(status$installed) | status$installed != status$expected
  if (any(bad)) {
    print(status[bad, ], row.names = FALSE)
    stop("R environment differs from renv.lock. Use the explicit restore command; ",
         "the check never installs or upgrades packages.", call. = FALSE)
  }
  if (!quiet) cat(nrow(status) - 1L, "pinned packages and R match renv.lock.\n")
  invisible(status)
}

cedar_bootstrap_renv <- function(root = getwd()) {
  # The committed autoloader owns the bootstrap version; never execute it here.
  # It would activate a project and might rewrite startup state.
  lines <- readLines(file.path(root, "renv", "activate.R"), warn = FALSE)
  version_line <- grep('^  version <- "[0-9.]+"$', lines, value = TRUE)
  if (length(version_line) != 1L) stop("Cannot resolve the pinned renv bootstrap version.")
  version <- sub('.*"([0-9.]+)"$', "\\1", version_line)
  if ("renv" %in% loadedNamespaces()) {
    if (as.character(getNamespaceVersion("renv")) != version) {
      stop("A different renv version is already loaded. Use a fresh Rscript --vanilla session.")
    }
    return(invisible(version))
  }
  # Inspect before loading: a newer system renv must not trap a fresh session
  # in the wrong namespace. Bootstrap the pinned version into a temporary library.
  available <- find.package("renv", quiet = TRUE)
  if (length(available) && as.character(packageVersion("renv")) == version) {
    requireNamespace("renv", quietly = TRUE)
    return(invisible(version))
  }
  bootstrap <- tempfile("cedar-renv-bootstrap-")
  dir.create(bootstrap)
  url <- sprintf("https://cloud.r-project.org/src/contrib/Archive/renv/renv_%s.tar.gz", version)
  install.packages(url, repos = NULL, type = "source", lib = bootstrap)
  .libPaths(c(bootstrap, .libPaths()))
  if (!requireNamespace("renv", quietly = TRUE) ||
      as.character(packageVersion("renv")) != version) stop("renv bootstrap failed.")
  invisible(version)
}

cedar_seed_library <- function(lock, target, installed = installed.packages()) {
  # renv treats matching packages in R's own .Library as already restored.
  # Copy exact matches into the target first so native setup is self-contained,
  # without reinstalling usable binaries or touching the source library.
  for (package in names(lock$Packages)) {
    if (dir.exists(file.path(target, package))) next
    match <- which(installed[, "Package"] == package &
                     installed[, "Version"] == lock$Packages[[package]]$Version)
    if (!length(match)) next
    source <- normalizePath(file.path(installed[match[1L], "LibPath"], package))
    if (!file.copy(source, target, recursive = TRUE)) {
      stop("Could not copy the installed package ", package, " into ", target)
    }
  }
  invisible(NULL)
}

cedar_restore_dependencies <- function(root = getwd(), docker = FALSE) {
  root <- normalizePath(root, mustWork = TRUE)
  # BuildKit does not expose /.dockerenv during RUN. Require an explicit,
  # build-step-only flag and the known Linux image directory instead.
  if (docker && !(identical(Sys.getenv("CEDAR_IMAGE_BUILD"), "1") &&
                  grepl("linux", R.version$os) &&
                  identical(root, "/srv/shiny-server/cedar"))) {
    stop("restore-docker is only for an image build; it must not change host libraries.")
  }
  target <- if (docker) .libPaths()[1L] else cedar_native_library(root)
  bootstrap_version <- cedar_bootstrap_renv(root)
  lock <- renv::lockfile_read(file.path(root, "renv.lock"))
  if (as.character(getRversion()) != lock$R$Version) {
    stop("This lockfile requires R ", lock$R$Version, "; running R ", getRversion(),
         ". Install the matching R version or use Docker.")
  }
  if (lock$Packages$renv$Version != bootstrap_version) {
    stop("renv.lock and renv/activate.R disagree about the bootstrap version.")
  }
  # A disposable restore project keeps renv from managing the checkout's
  # .Rprofile, ignore files, or old project library. Never clean unrelated packages.
  restore_project <- tempfile("cedar-restore-")
  dir.create(restore_project)
  dir.create(target, recursive = TRUE, showWarnings = FALSE)
  old <- options(renv.config.cache.enabled = FALSE,
                 renv.config.cache.symlinks = FALSE,
                 renv.config.auto.snapshot = FALSE)
  on.exit(options(old), add = TRUE)
  cedar_seed_library(lock, target)
  renv::restore(project = restore_project, lockfile = file.path(root, "renv.lock"),
                library = target, prompt = FALSE, clean = FALSE)
  .libPaths(c(target, .Library))
  cedar_check_dependencies(root, library = target)
  pinned_paths <- file.path(target, names(lock$Packages))
  links <- Sys.readlink(pinned_paths)
  if (any(!is.na(links) & nzchar(links))) {
    stop("Managed packages must be copies, not cache symlinks.")
  }
  if (!docker) writeLines(unname(tools::md5sum(file.path(root, "renv.lock"))),
                          file.path(target, ".cedar-ready"))
  cat("Prepared library:", target, "\n")
  invisible(target)
}

cedar_r_environment_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  if (length(args) != 1L || !args %in% c("help", "check", "check-native", "restore", "restore-docker")) {
    stop("Usage: Rscript --vanilla scripts/r-environment.R ",
         "{help|check|check-native|restore|restore-docker}", call. = FALSE)
  }
  switch(args,
    help = cat("check: report drift in the current library (read-only)\n",
               "restore: prepare a copied, project-local native library\n",
               "check-native: check that prepared library (read-only)\n",
               "restore-docker: image-build installation only\n", sep = ""),
    check = cedar_check_dependencies(),
    `check-native` = {
      cedar_use_native_library()
      cedar_check_dependencies(library = cedar_native_library())
    },
    restore = cedar_restore_dependencies(),
    `restore-docker` = cedar_restore_dependencies(docker = TRUE))
  invisible(NULL)
}

if (sys.nframe() == 0L) cedar_r_environment_main()
