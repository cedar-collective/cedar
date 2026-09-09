# data-anomalies.R — rules that FIND data problems, rather than waiting for
# someone to trip over one.
#
# The registry in R/lists/data_semantics.R records what we already know. These
# are the other half: screens that surface candidates for review. Both rules
# here come from defects that were found by accident and cost real time.
#
# Every rule returns rows in the cedar_mapping_issues shape so the Admin >
# Mappings surface can show them beside the existing program-map issues.
#
# A screen produces CANDIDATES, never verdicts. The selective-admission rule
# flags Spanish alongside Radiologic Sciences; one is a competitive-entry health
# program and the other is something else entirely, and only a person can say
# which is which. Anything that acted on these automatically would be inventing
# conclusions from a ratio.

.anomaly_frame <- function() {
  tibble::tibble(
    issue_type = character(), severity = character(), review_status = character(),
    program_code = character(), major_code = character(), college_code = character(),
    dept_code = character(), degree_level = character(), program_type = character(),
    details = character()
  )
}


#' Pre-majors whose department is their own major code
#'
#' The dept_code chain ends in an identity fallback so the column is never NA.
#' For a declared major that is often right -- RADS really is the RADS
#' department. For a PRE-major it is always a mapping failure: a pre-major leads
#' to a program, it is not a department. The result is indistinguishable from a
#' correct answer and cedar_mapping_issues never sees it, because the row is
#' mapped. That is how Radiologic Sciences came to report 35 students at
#' department level when it had 229 (ISSUES.md I7).
#'
#' @param programs cedar_programs.
#' @return Rows in the cedar_mapping_issues shape, one per offending code.
detect_pre_major_self_mapping <- function(programs, known_departments = NULL) {
  required <- c("major_code", "dept_code", "is_pre_major", "program_name")
  missing <- setdiff(required, names(programs))
  if (length(missing) > 0) {
    stop("[data-anomalies.R] programs is missing: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  offenders <- programs %>%
    dplyr::filter(
      is_pre_major,
      !is.na(major_code), !is.na(dept_code),
      dept_code == major_code
    ) %>%
    dplyr::count(major_code, dept_code, program_name, name = "rows") %>%
    dplyr::arrange(dplyr::desc(rows)) %>%
    # A code can be BOTH a pre-major code and a genuine department -- FCS is
    # pre-Computer Science and the Family and Child Studies department. That is a
    # harder problem than a missing mapping and the reader has to be told, or
    # they will try to map the code and find it already resolves.
    dplyr::mutate(
      is_real_department = major_code %in% unique(stats::na.omit(known_departments))
    )
  if (nrow(offenders) == 0) return(.anomaly_frame())

  offenders %>%
    dplyr::transmute(
      issue_type = "pre_major_self_mapped_department",
      severity = "warning",
      review_status = "needs_review",
      program_code = NA_character_,
      major_code, college_code = NA_character_, dept_code,
      degree_level = NA_character_, program_type = NA_character_,
      details = paste0(
        "Pre-major '", program_name, "' resolves to a department named after ",
        "itself (", rows, " program rows). A pre-major leads to a program and ",
        "is not a department, so this is the dept_code identity fallback, not a ",
        "real mapping. Map it in R/lists/program_code_maps.R.",
        dplyr::if_else(
          is_real_department,
          paste0(" NOTE: '", major_code, "' is ALSO a real department code, so ",
                 "this is a namespace collision rather than a missing mapping. ",
                 "It cannot be fixed by mapping the code alone -- it needs a ",
                 "major_college_to_dept entry keyed on the college."),
          ""
        )
      )
    )
}


#' Programs whose department is the identity fallback rather than a real one
#'
#' The last tier of the dept_code chain assigns the major code itself, so the
#' column is never NA. The cost is that an unmapped program is indistinguishable
#' from a mapped one: it names a department that does not exist, and nothing
#' errors. This finds every row that reached that tier -- a dept_code equal to
#' its own major_code where that code is not a known department.
#'
#' Pre-majors are excluded because detect_pre_major_self_mapping() reports them
#' separately and with more certainty: for a pre-major the identity fallback is
#' always wrong, while a declared program occasionally shares its code with a
#' genuine department.
#'
#' @param programs cedar_programs.
#' @param known_departments Character vector of real department codes, normally
#'   `subj_dept_map$dept_code`.
#' @param department_less Major codes that legitimately have no department, so
#'   the screen does not report them forever. Defaults to the curated list in
#'   `R/lists/program_code_maps.R`.
#' @return Rows in the cedar_mapping_issues shape.
detect_identity_fallback_departments <- function(
    programs, known_departments,
    department_less = get0("department_less_major_codes", ifnotfound = character(0))) {
  required <- c("major_code", "dept_code", "is_pre_major", "program_name")
  missing <- setdiff(required, names(programs))
  if (length(missing) > 0) {
    stop("[data-anomalies.R] programs is missing: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  known <- unique(stats::na.omit(as.character(known_departments)))
  offenders <- programs %>%
    dplyr::filter(
      !is_pre_major,
      !is.na(major_code), !is.na(dept_code),
      dept_code == major_code,
      !dept_code %in% .env$known,
      !major_code %in% .env$department_less
    ) %>%
    dplyr::count(major_code, dept_code, program_name, name = "rows") %>%
    dplyr::arrange(dplyr::desc(rows))
  if (nrow(offenders) == 0) return(.anomaly_frame())

  offenders %>%
    dplyr::transmute(
      issue_type = "identity_fallback_department",
      severity = "warning",
      review_status = "needs_review",
      program_code = NA_character_,
      major_code, college_code = NA_character_, dept_code,
      degree_level = NA_character_, program_type = NA_character_,
      details = paste0(
        "'", program_name, "' has no department mapping (", rows,
        " program rows), so dept_code fell back to the major code itself. ",
        "That names a department which does not exist, and every dept-scoped ",
        "report silently excludes these students from their real unit. Map it ",
        "in R/lists/program_code_maps.R and regenerate program_map.qs."
      )
    )
}


#' Programs whose declared-major headcount far exceeds their graduates
#'
#' A multi-year program always carries more majors than it graduates in a year;
#' the typical CEDAR program sits near 2. A far higher ratio means the major
#' code is being carried by students who will not complete it -- most often
#' because it records intent to enter a competitive program rather than
#' admission to it. Surfaces that report such a program's outcomes as
#' "attrition" are describing an admission funnel.
#'
#' Counts DISTINCT students and one award level, because cedar_degrees carries
#' several award rows per student across levels; comparing raw row counts to an
#' undergraduate headcount overstates graduates by two to three times.
#'
#' @param programs cedar_programs.
#' @param degrees cedar_degrees.
#' @param opt from_term, min_majors, min_graduates, min_years, min_ratio,
#'   award_category.
#' @return Rows in the cedar_mapping_issues shape, one per flagged program.
detect_selective_admission_signal <- function(programs, degrees, opt = list()) {
  required_programs <- c("major_code", "term", "student_id", "is_pre_major",
                         "program_type", "program_name", "student_level")
  missing <- setdiff(required_programs, names(programs))
  if (length(missing) > 0) {
    stop("[data-anomalies.R] programs is missing: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  required_degrees <- c("major_code", "term", "student_id", "award_category")
  missing <- setdiff(required_degrees, names(degrees))
  if (length(missing) > 0) {
    stop("[data-anomalies.R] degrees is missing: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }

  from_term <- as.integer(opt$from_term %||% 202410L)
  min_majors <- as.numeric(opt$min_majors %||% 40)
  min_graduates <- as.numeric(opt$min_graduates %||% 3)
  min_years <- as.integer(opt$min_years %||% 3L)
  # 4.0 is roughly the 90th percentile of the measured distribution (median 2.2,
  # 95th 5.3) -- about twice a typical program. See docs/developers/data-anomalies.md.
  min_ratio <- as.numeric(opt$min_ratio %||% 4.0)
  # The award category and the student level are ONE choice, not two. Counting
  # graduate majors against baccalaureate degrees inflates the ratio for every
  # program with a large graduate population -- Special Education scored 13.4
  # and Physics 9.9 that way, both artifacts. Change them together or not at all.
  award <- opt$award_category %||% "Baccalaureate Degree"
  level <- opt$student_level %||% "Undergraduate"

  major_counts <- programs %>%
    dplyr::filter(
      term >= from_term, !is_pre_major, !is.na(major_code),
      program_type %in% c("Major", "Second Major"),
      student_level %in% level
    ) %>%
    dplyr::group_by(major_code, term) %>%
    dplyr::summarise(n = dplyr::n_distinct(student_id), .groups = "drop") %>%
    dplyr::group_by(major_code) %>%
    dplyr::summarise(avg_majors = mean(n), .groups = "drop")

  graduate_counts <- degrees %>%
    dplyr::filter(term >= from_term, !is.na(major_code), award_category %in% award) %>%
    dplyr::mutate(year = term %/% 100L) %>%
    dplyr::group_by(major_code, year) %>%
    dplyr::summarise(n = dplyr::n_distinct(student_id), .groups = "drop") %>%
    dplyr::group_by(major_code) %>%
    dplyr::summarise(avg_graduates = mean(n), n_years = dplyr::n_distinct(year),
                     .groups = "drop")

  names_by_code <- programs %>%
    dplyr::filter(!is.na(major_code), !is.na(program_name), nzchar(program_name)) %>%
    dplyr::count(major_code, program_name) %>%
    dplyr::group_by(major_code) %>%
    dplyr::slice_max(n, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::select(major_code, program_name)

  flagged <- major_counts %>%
    dplyr::inner_join(graduate_counts, by = "major_code") %>%
    dplyr::filter(
      avg_majors >= min_majors, avg_graduates >= min_graduates,
      n_years >= min_years, avg_majors / avg_graduates >= min_ratio
    ) %>%
    dplyr::mutate(ratio = avg_majors / avg_graduates) %>%
    dplyr::left_join(names_by_code, by = "major_code") %>%
    dplyr::arrange(dplyr::desc(ratio))
  if (nrow(flagged) == 0) return(.anomaly_frame())

  flagged %>%
    dplyr::transmute(
      issue_type = "declared_majors_far_exceed_graduates",
      severity = "info",
      review_status = "needs_review",
      program_code = NA_character_,
      major_code, college_code = NA_character_, dept_code = NA_character_,
      degree_level = NA_character_, program_type = NA_character_,
      details = paste0(
        dplyr::coalesce(program_name, major_code), " carries ",
        round(avg_majors), " declared majors per term against ",
        round(avg_graduates, 1), " graduates a year (ratio ",
        round(ratio, 1), "; a typical program is near 2). Check whether the ",
        "major code records intent rather than admission before reporting this ",
        "program's outcome mix as attrition."
      )
    )
}


#' Run every anomaly screen and return one report
build_data_anomaly_report <- function(programs, degrees, opt = list(),
                                      known_departments = NULL) {
  dplyr::bind_rows(
    detect_pre_major_self_mapping(programs, known_departments),
    if (!is.null(known_departments)) {
      detect_identity_fallback_departments(programs, known_departments)
    },
    detect_selective_admission_signal(programs, degrees, opt)
  )
}
