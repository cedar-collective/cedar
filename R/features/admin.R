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


# Short names for what each mapping-issue screen found, for the Problem column.
# The screens' own text is long and ends in advice for the old lists; it stays
# available as the column's hover text. identity_fallback_department has no
# label: the Today column already says "phantom".
ADMIN_PROBLEM_LABELS <- c(
  program_dropped_unknown_college_suffix = "unknown college suffix; dropped from program_map",
  malformed_program_map_row              = "program_map row lacks a major or college code",
  unmapped_program_code                  = "no department in program_map",
  pre_major_self_mapped_department       = "pre-major mapped to itself",
  declared_majors_far_exceed_graduates   = "far more majors than graduates",
  identity_fallback_department           = NA
)

#' Every program awaiting a person's decision, for Admin > Mappings
#'
#' One row per program to decide: each `proposed` row of programs.csv, plus any
#' program a mapping issue names that has no row in the file at all. Each
#' carries the department CEDAR reports for it today -- until the transform
#' reads programs.csv (ADR-002 Stage 3) that still comes from
#' program_code_maps.R, so "today" can be a phantom department named after the
#' code -- and the problem the issue screens found with it.
#'
#' Decisions are edits to the file in the repository, reviewed as a diff, never
#' to the app: the running container holds a copy of the source that the next
#' deploy replaces. Issues on a program already confirmed in the file are not
#' listed -- there is nothing left to decide -- but are counted, because they
#' persist in today's departments until Stage 3.
#'
#' @param files The list read_institution_mappings() returns.
#' @param programs cedar_programs.
#' @param issues build_admin_mapping_issues() output.
#' @param known_units Real unit codes (units.csv); any other "today" department
#'   is a phantom.
#' @return List: `queue`, a tibble (line_url, program_code, program_name,
#'   students, last_term, today, suggested_unit, basis, problem,
#'   problem_detail, evidence),
#'   most students first; and `n_decided_issues`, issues on confirmed programs.
build_program_mapping_queue <- function(files, programs, issues, known_units) {
  needed <- c("student_id", "term", "major_code", "program_type", "program_name", "dept_code")
  missing <- setdiff(needed, names(programs))
  if (length(missing)) {
    stop("[admin.R] build_program_mapping_queue: cedar_programs lacks ",
         paste(missing, collapse = ", "))
  }
  if (length(known_units) == 0) stop("[admin.R] build_program_mapping_queue: known_units is required")
  pr <- files$programs
  # Row i of the file is line i + 1; read_institution_file() guarantees it.
  # Its own line, not program_line_url(): a college-specific row is proposed
  # separately from its code's every-college row.
  pr$line <- seq_len(nrow(pr)) + 1L

  issues <- tibble::as_tibble(issues) %>%
    dplyr::mutate(code = dplyr::coalesce(major_code, program_code)) %>%
    dplyr::filter(!is.na(code))
  confirmed <- unique(pr$program_code[pr$status == "confirmed"])
  pending   <- pr[pr$status == "proposed", ]
  no_row    <- setdiff(issues$code, pr$program_code)
  codes     <- union(pending$program_code, no_row)

  held <- programs %>%
    dplyr::filter(!grepl("Concentration", program_type), major_code %in% codes)
  counts <- held %>% dplyr::group_by(major_code) %>%
    dplyr::summarize(students = dplyr::n_distinct(student_id), last_term = max(term),
                     data_name = names(sort(table(program_name), decreasing = TRUE))[1],
                     .groups = "drop")
  # The department most of the code's rows carry today.
  today <- held %>% dplyr::count(major_code, dept_code) %>%
    dplyr::group_by(major_code) %>% dplyr::slice_max(n, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::transmute(major_code, today = dplyr::case_when(
      is.na(dept_code)                ~ "none",
      !dept_code %in% known_units     ~ paste(dept_code, "(phantom)"),
      TRUE                            ~ dept_code))
  unknown <- setdiff(issues$issue_type, names(ADMIN_PROBLEM_LABELS))
  if (length(unknown)) {
    stop("[admin.R] No Problem label for issue type(s): ", paste(unknown, collapse = ", "),
         ". Add them to ADMIN_PROBLEM_LABELS.")
  }
  problems <- issues %>% dplyr::filter(code %in% codes) %>%
    dplyr::mutate(label = dplyr::if_else(
      issue_type == "unmapped_program_code" & review_status == "reviewed_exception",
      "reviewed exception: no owner yet", unname(ADMIN_PROBLEM_LABELS[issue_type]))) %>%
    dplyr::group_by(code) %>%
    dplyr::summarize(
      problem = paste(unique(stats::na.omit(label)), collapse = "; "),
      problem_detail = paste(unique(details), collapse = "\n\n"), .groups = "drop") %>%
    dplyr::mutate(problem = dplyr::na_if(problem, ""))

  from_file <- tibble::tibble(
    program_code = pending$program_code, program_name = pending$program_name,
    suggested_unit = pending$unit_code, basis = pending$basis,
    evidence = pending$evidence,
    line_url = mapping_file_url(files, "programs", pending$line))
  # A code with no row is named by the Banner program codes the issue came
  # from: the old parser can read a code out of the wrong part ("FPMD-UC" gave
  # major code "UC"), and the full code shows what the row really is.
  banner_codes <- issues %>% dplyr::filter(code %in% no_row) %>%
    dplyr::group_by(code) %>%
    dplyr::summarize(banner = paste(sort(unique(stats::na.omit(program_code))), collapse = ", "),
                     .groups = "drop")
  missing_rows <- tibble::tibble(
    program_code = no_row, suggested_unit = "",
    basis = "no row in programs.csv", evidence = "", line_url = NA_character_) %>%
    dplyr::left_join(banner_codes, by = c("program_code" = "code")) %>%
    dplyr::mutate(program_name = dplyr::if_else(nzchar(banner),
                                                 paste("Banner program", banner), NA_character_)) %>%
    dplyr::select(-banner)

  queue <- dplyr::bind_rows(from_file, missing_rows) %>%
    dplyr::left_join(counts, by = c("program_code" = "major_code")) %>%
    dplyr::left_join(today, by = c("program_code" = "major_code")) %>%
    dplyr::left_join(problems, by = c("program_code" = "code")) %>%
    dplyr::mutate(
      program_name = dplyr::coalesce(program_name, data_name),
      # A code in the file but not in cedar_programs (degrees only) holds no
      # program-table students: zero is measured, not missing.
      students = dplyr::coalesce(students, 0L),
      today = dplyr::coalesce(today, "none")) %>%
    dplyr::arrange(dplyr::desc(students), program_code) %>%
    dplyr::select(line_url, program_code, program_name, students, last_term, today,
                  suggested_unit, basis, problem, problem_detail, evidence)

  list(queue = queue,
       n_decided_issues = sum(issues$code %in% confirmed & !issues$code %in% codes))
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

