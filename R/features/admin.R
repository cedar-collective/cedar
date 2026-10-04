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


#' programs.csv rows awaiting a person's decision, for Admin > Mappings
#'
#' Every `proposed` row, with how many students carry the code (so the ones
#' that matter come first) and a link to the row's line in the institution's
#' repository, where the decision is made. Decisions are edits to the file, not
#' to the app: the running container holds a copy of the source that the next
#' deploy replaces, and a change made there would never be reviewed.
#'
#' @param files The list read_institution_mappings() returns.
#' @param programs cedar_programs; supplies the student counts.
#' @return Tibble: program_code, college_code, program_name, suggested_unit,
#'   basis, students, last_term, evidence, line_url. One row per proposed row,
#'   most students first.
build_program_mapping_review <- function(files, programs) {
  needed <- c("student_id", "term", "major_code")
  missing <- setdiff(needed, names(programs))
  if (length(missing)) {
    stop("[admin.R] build_program_mapping_review: cedar_programs lacks ",
         paste(missing, collapse = ", "))
  }
  pr <- files$programs
  # Row i of the file is line i + 1; read_institution_file() guarantees it.
  pr$line <- seq_len(nrow(pr)) + 1L
  pending <- pr[pr$status == "proposed", ]
  counts <- programs %>%
    dplyr::filter(major_code %in% pending$program_code) %>%
    dplyr::group_by(major_code) %>%
    dplyr::summarize(students = dplyr::n_distinct(student_id),
                     last_term = max(term), .groups = "drop")
  tibble::as_tibble(pending) %>%
    dplyr::left_join(counts, by = c("program_code" = "major_code")) %>%
    dplyr::mutate(students = dplyr::coalesce(students, 0L),
                  line_url = mapping_file_url(files, "programs", line)) %>%
    dplyr::arrange(dplyr::desc(students), program_code) %>%
    dplyr::select(program_code, college_code, program_name,
                  suggested_unit = unit_code, basis, students, last_term,
                  evidence, line_url)
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

