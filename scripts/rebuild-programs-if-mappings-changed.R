# Deploy-time gate: rebuild cedar_programs only when the MAPPING source moved.
#
#   Rscript --vanilla scripts/rebuild-programs-if-mappings-changed.R
#
# Same shape as the enrollment-projection model gate, and for the same reason.
# cedar_programs$dept_code is derived at transform time, so editing a mapping
# list changes nothing until the table is rebuilt -- and nothing says the two
# have drifted, because the stored dept_code stays plausible. A mapping fix can
# sit in the repository while production serves the old departments.
#
# The check is cheap on purpose: it hashes five files and reads one attribute,
# touching no CEDAR table, so a deploy that changed no mapping costs about a
# second. Data-driven staleness stays with the morning refresh.

# The stamp asserts "these departments were produced by this mapping source".
# Anything that rebuilds cedar_programs must therefore regenerate program_map.qs
# as well, or the assertion becomes false and this gate will happily skip a
# rebuild that is genuinely needed. `force` exists to recover from exactly that:
# a table stamped by a build that did not regenerate the map.
rebuild_programs_if_mappings_changed <- function(
    data_dir = NULL, base_dir = getwd(), rebuild = NULL, force = FALSE) {
  SOURCED_FROM_PARSE_DATA <<- TRUE
  source(file.path(base_dir, "config", "config.R"))
  source(file.path(base_dir, "R", "trunk", "load-funcs.R"))
  load_funcs(base_dir, modules = FALSE)
  source(file.path(base_dir, "R", "data-parsers", "transform-to-cedar.R"))

  is_docker <- Sys.getenv("docker") == "TRUE" || file.exists("/.dockerenv")
  if (is.null(data_dir)) {
    data_dir <- if (is_docker && exists("cedar_data_docker_dir")) {
      cedar_data_docker_dir
    } else if (exists("cedar_shared_data_dir")) {
      cedar_shared_data_dir
    } else {
      "data/"
    }
  }
  programs_file <- file.path(data_dir, "cedar_programs.qs")

  drift <- if (isTRUE(force)) "rebuild forced" else {
    cedar_programs_mapping_drift(programs_file, base_dir)
  }
  if (is.null(drift)) {
    message("[mappings] Mapping source unchanged since cedar_programs was built; ",
            "no rebuild. Data-driven staleness is handled by the morning refresh.")
    return(invisible(FALSE))
  }

  message("[mappings] Rebuilding cedar_programs because the ", drift)

  # program_map.qs MUST be regenerated first, not merely reloaded. The mapping
  # lists feed generate_program_map(), and transform_to_cedar() only regenerates
  # when the file is absent -- given a file it loads it, so rebuilding
  # cedar_programs alone would apply the new lists to a map built from the old
  # ones and report success. That is the trap this gate exists to close, so it
  # must not fall into it. Removing program_map from the session is necessary but
  # not sufficient; the artifact itself has to be rewritten.
  source_export <- file.path(data_dir, paste0("academic_studies", ".qs"))
  if (!file.exists(source_export)) {
    stop("[mappings] Cannot regenerate program_map: no academic_studies at ",
         source_export, call. = FALSE)
  }
  message("[mappings] Regenerating program_map from ", source_export)
  new_map <- generate_program_map(
    source_export, ".qs", subj_dept_map, premaj_canon, xvar_explicit, extra_p2d,
    known_suffixes, real_F_progs, get_lev, ad_major_to_dept,
    allowed_unmapped_program_codes
  )
  qs2::qs_save(new_map, file.path(data_dir, "program_map.qs"))
  message("[mappings] program_map regenerated: ", nrow(new_map), " rows")
  if (exists("program_map", envir = .GlobalEnv)) {
    rm("program_map", envir = .GlobalEnv)
  }

  rebuild <- rebuild %||% function() transform_to_cedar(data_dir = data_dir,
                                                       tables = "programs")
  rebuild()
  message("[mappings] cedar_programs rebuilt.")
  invisible(TRUE)
}

if (sys.nframe() == 0L) {
  rebuild_programs_if_mappings_changed(
    force = "--force" %in% commandArgs(trailingOnly = TRUE)
  )
}
