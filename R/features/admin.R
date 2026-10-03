# Small display payloads for Admin. Never load or scan institutional tables here.
build_admin_data_status <- function(summary, current_term) {
  terms <- summary$display_terms
  datasets <- c(sections = "Sections", students = "Students", programs = "Programs",
                degrees = "Degrees", faculty = "Faculty")
  rows <- lapply(names(datasets), function(key) {
    count <- summary[[paste0(key, "_count")]]
    dates <- summary[[paste0(key, "_term_dates")]]
    values <- vapply(as.character(terms), function(term) {
      value <- dates[[term]]
      if (is.null(value) || length(value) != 1L || is.na(value) ||
          value %in% c("-Inf", "Inf", "NA", "")) "Not available" else as.character(value)
    }, character(1))
    c(Dataset = datasets[[key]],
      Rows = if (is.null(count) || is.na(count) || count == 0L) "Not loaded" else
        format(count, big.mark = ",", scientific = FALSE, trim = TRUE), values)
  })
  display <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  names(display) <- c("Dataset", "Rows", vapply(terms, fmt_term, character(1)))
  list(table = display, current_column = match(current_term, terms) + 2L,
       computed_at = summary$computed_at)
}


#' Every mapping issue the Admin > Mappings panel shows
#'
#' Startup exclusions from cedar_mapping_issues, plus the runtime screens that
#' find what a clean program_map cannot: a program whose dept_code fell back to
#' its own major code is "mapped" as far as the map knows, and names a
#' department that does not exist.
#'
#' A screen that fails must fail loudly. This used to sit in server.R inside a
#' tryCatch that returned only the startup rows on error, so a broken screen
#' read as "no mapping issues" -- the page meant to catch silent failures
#' would itself have failed silently.
#'
#' @param startup cedar_mapping_issues, or NULL/empty.
#' @param programs cedar_programs, or NULL/empty when not loaded.
#' @param known_departments Real department codes, normally
#'   `subj_dept_map$dept_code`. Never `dept_name_lookup`: it lists self-named
#'   codes as departments, so the screen would pass them.
#' @return Data frame in the cedar_mapping_issues shape.
build_admin_mapping_issues <- function(startup, programs, known_departments) {
  startup <- if (is.null(startup) || nrow(startup) == 0) {
    as.data.frame(.anomaly_frame(), stringsAsFactors = FALSE)
  } else {
    as.data.frame(startup, stringsAsFactors = FALSE)
  }
  if (is.null(programs) || nrow(programs) == 0) return(startup)
  if (length(known_departments) == 0) {
    stop("[admin.R] known_departments is required to screen for identity-fallback departments.")
  }

  detected <- dplyr::bind_rows(
    detect_pre_major_self_mapping(programs, known_departments),
    detect_identity_fallback_departments(programs, known_departments)
  )
  dplyr::bind_rows(startup, as.data.frame(detected, stringsAsFactors = FALSE))
}

