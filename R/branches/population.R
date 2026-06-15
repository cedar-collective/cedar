#' Population Building (refactored)
#'
#' Isolated outcome detection functions + orchestrating build_population().
#' Each function is independently testable and returns a character vector
#' of student IDs (or a data frame for get_entry_pathways).
#'
#' Load order: this file replaces population.R once all tests pass.


# ---------------------------------------------------------------------------
# get_ongoing_ids
# ---------------------------------------------------------------------------

#' Get Ongoing Student IDs
#'
#' Returns all students currently engaged with a focal program in the most
#' recent data term. Includes two groups:
#'   - Declared focal students whose last program record is max_data_term
#'   - Pre-major-only students whose focal pre-major record is max_data_term
#'     (these students haven't had a chance to declare yet)
#'
#' @param programs Data frame. cedar_programs.
#' @param focal_names Character vector. Focal program names.
#' @param max_data_term Integer. The most recent term in the data.
#' @return Character vector of student IDs.
get_ongoing_ids <- function(programs, focal_names, max_data_term, focal_codes = character(0)) {
  focal <- programs %>%
    filter(program_type %in% c("Major", "Second Major"),
           major_code %in% focal_codes | program_name %in% focal_names)

  # Declared focal students present in max_data_term
  declared_ongoing <- focal %>%
    filter(!is_pre_major, term == max_data_term) %>%
    pull(student_id) %>%
    unique()

  # Students who ever declared focal (used to exclude from pre-major group)
  ever_declared <- focal %>%
    filter(!is_pre_major) %>%
    pull(student_id) %>%
    unique()

  # Pre-major-only students present in max_data_term
  current_premajor <- focal %>%
    filter(is_pre_major, term == max_data_term,
           !student_id %in% ever_declared) %>%
    pull(student_id) %>%
    unique()

  union(declared_ongoing, current_premajor)
}


# ---------------------------------------------------------------------------
# get_graduated_ids
# ---------------------------------------------------------------------------

#' Get Graduated Student IDs
#'
#' Returns students who received a focal-program degree within the graduation
#' window: [last_declared_term, last_declared_term + 100]. The +100 window covers
#' the typical 1–2 term lag between a student's last program record and when
#' their degree is formally conferred.
#'
#' Only counts graduation_status values that represent a real outcome:
#' "Awarded", "Pending", "Sought". Excludes "Hold Pending" (admin block)
#' and "Record Clear" (application withdrawn).
#'
#' @param programs Data frame. cedar_programs.
#' @param degrees Data frame or NULL. cedar_degrees. Returns empty vector if NULL.
#' @param focal_names Character vector. Focal program names.
#' @param focal_codes Character vector. Focal program codes (optional). When
#'   supplied and the degrees table has a major_code column, restricts matches
#'   to degrees in those codes.
#' @return Character vector of student IDs.
get_graduated_ids <- function(programs, degrees, focal_names) {
  if (is.null(degrees) || nrow(degrees) == 0) return(character(0))

  focal_declared <- programs %>%
    filter(program_type %in% c("Major", "Second Major"),
           program_name %in% focal_names,
           !is_pre_major)

  # Last declared focal term per student (the graduation window anchor)
  last_focal <- focal_declared %>%
    group_by(student_id) %>%
    summarize(last_focal_term = max(term, na.rm = TRUE), .groups = "drop")

  if (nrow(last_focal) == 0) return(character(0))

  # Focal program codes — fallback match key when program_name values differ
  # between cedar_programs and cedar_degrees. Banner's degrees export ("Program"
  # field) sometimes uses different formatting than the programs table
  # (e.g., "History, Bachelor of Arts" vs "History"), causing silent zero-
  # graduation counts if we rely on name alone. The short code ("HIST") is
  # consistent across both tables.
  focal_codes <- focal_declared %>%
    filter(!is.na(major_code)) %>%
    pull(major_code) %>%
    unique()

  # Three match strategies, tried together (OR):
  #
  # major_match: degrees$major (Banner "Major" field) — same source as
  #   cedar_programs$program_name (academic_studies "Major" field). Both say
  #   "History". Most reliable name match; use as primary.
  #
  # pcode_match: degrees$major_code ("HIST") — short catalog code, format-
  #   independent. Reliable after data is regenerated with current transform.
  #
  # pname_match: degrees$program_name (Banner "Program" field) says
  #   "History, Bachelor of Arts" — a different format that will never match
  #   cedar_programs$program_name ("History"). Kept only as a last resort for
  #   non-standard exports where major/major_code are both absent.
  #
  # UNM term codes are YYYYSS integers (10=spring, 60=summer, 80=fall).
  # Adding 100 gives an ~one-academic-year window regardless of starting semester:
  #   spring anchor (202010) → window closes at 202110 (next spring)
  #   fall anchor   (202080) → window closes at 202180 (next fall)
  #   summer anchor (202060) → window closes at 202160 (next summer)
  if (!"major" %in% names(degrees))
    stop("[population.R:get_graduated_ids] cedar_degrees is missing the 'major' column. ",
         "Re-run transform-to-cedar.R to regenerate cedar_degrees from the Banner degrees export.")
  if (!"major_code" %in% names(degrees))
    stop("[population.R:get_graduated_ids] cedar_degrees is missing the 'major_code' column. ",
         "Re-run transform-to-cedar.R to regenerate cedar_degrees from the Banner degrees export.")

  major_match <- !is.na(degrees$major) & degrees$major %in% focal_names
  pcode_match <- if (length(focal_codes) > 0)
    !is.na(degrees$major_code) & degrees$major_code %in% focal_codes else rep(FALSE, nrow(degrees))
  pname_match <- if ("program_name" %in% names(degrees))
    degrees$program_name %in% focal_names else rep(FALSE, nrow(degrees))

  deg <- degrees[major_match | pcode_match | pname_match, , drop = FALSE]
  if (nrow(deg) == 0) return(character(0))

  deg <- deg %>%
    inner_join(last_focal, by = "student_id") %>%
    filter(term >= last_focal_term,
           term <= last_focal_term + 100L)

  # Filter to valid graduation statuses when the column is present.
  # "Hold Pending" = admin block (not graduated), "Record Clear" = withdrawn.
  if ("graduation_status" %in% names(deg))
    deg <- filter(deg, graduation_status %in% c("Awarded", "Pending", "Sought"))

  pull(distinct(deg, student_id), student_id)
}


# ---------------------------------------------------------------------------
# get_switched_out_ids
# ---------------------------------------------------------------------------

#' Get Switched-Out Student IDs (detection only)
#'
#' Returns students who have a declared non-focal program record at any term
#' strictly after their last declared focal term. This is a detection function —
#' priority over other outcomes (ongoing, graduated) is applied by the
#' orchestrator, not here.
#'
#' @param programs Data frame. cedar_programs.
#' @param focal_names Character vector. Focal program names.
#' @return Character vector of student IDs.
get_switched_out_ids <- function(programs, focal_names, focal_codes = character(0)) {
  declared <- programs %>%
    filter(program_type %in% c("Major", "Second Major"),
           !is_pre_major)

  # Last declared focal term per student
  last_focal <- declared %>%
    filter(major_code %in% focal_codes | program_name %in% focal_names) %>%
    group_by(student_id) %>%
    summarize(last_focal_term = max(term, na.rm = TRUE), .groups = "drop")

  if (nrow(last_focal) == 0) return(character(0))

  # Non-focal declared records for those students, after their last focal term
  declared %>%
    filter(!major_code %in% focal_codes, !program_name %in% focal_names,
           student_id %in% last_focal$student_id) %>%
    inner_join(last_focal, by = "student_id") %>%
    filter(term > last_focal_term) %>%
    pull(student_id) %>%
    unique()
}


# ---------------------------------------------------------------------------
# get_never_declared_ids
# ---------------------------------------------------------------------------

#' Get Never-Declared Student IDs
#'
#' Returns students who appeared only as a pre-major in the focal program —
#' never declared — and whose last focal pre-major record predates
#' max_data_term. Students with a pre-major record IN max_data_term are
#' classified as ongoing (current pre-majors), not never_declared.
#'
#' @param programs Data frame. cedar_programs.
#' @param focal_names Character vector. Focal program names.
#' @param max_data_term Integer. The most recent term in the data.
#' @return Character vector of student IDs.
get_never_declared_ids <- function(programs, focal_names, max_data_term, focal_codes = character(0)) {
  focal <- programs %>%
    filter(program_type %in% c("Major", "Second Major"),
           major_code %in% focal_codes | program_name %in% focal_names)

  # Students who ever declared the focal program
  ever_declared <- focal %>%
    filter(!is_pre_major) %>%
    pull(student_id) %>%
    unique()

  # Pre-major-only students and their last pre-major term
  focal %>%
    filter(is_pre_major, !student_id %in% ever_declared) %>%
    group_by(student_id) %>%
    summarize(last_pre_term = max(term, na.rm = TRUE), .groups = "drop") %>%
    filter(last_pre_term < max_data_term) %>%
    pull(student_id)
}


# ---------------------------------------------------------------------------
# get_entry_pathways
# ---------------------------------------------------------------------------

#' Get Entry Pathways for Declared Focal Students
#'
#' Returns a data frame of student_id + entry_pathway for every student who
#' ever declared the focal program. Pre-major-only students are excluded.
#'
#' Pathway rules (applied in priority order):
#'   pre_major   — had a focal pre-major record strictly before first declaration
#'   switched_in — had a non-focal declared major strictly before first declaration
#'   direct      — everything else (first UNM major was the focal program)
#'
#' Note: never_declared is NOT an entry_pathway returned by this function —
#' it is assigned by build_population() to historical pre-major-only students.
#'
#' @param programs Data frame. cedar_programs.
#' @param focal_names Character vector. Focal program names.
#' @return Data frame with columns student_id (chr) and entry_pathway (chr).
get_entry_pathways <- function(programs, focal_names, focal_codes = character(0)) {
  focal_major <- programs %>%
    filter(program_type %in% c("Major", "Second Major"),
           major_code %in% focal_codes | program_name %in% focal_names)

  # Declared focal students and their first declaration term
  declared_focal <- focal_major %>%
    filter(!is_pre_major) %>%
    group_by(student_id) %>%
    summarize(first_decl_term = min(term, na.rm = TRUE), .groups = "drop")

  if (nrow(declared_focal) == 0)
    return(tibble(student_id = character(), entry_pathway = character()))

  # Focal pre-major records before first declaration → pre_major pathway
  had_focal_pre <- focal_major %>%
    filter(is_pre_major,
           student_id %in% declared_focal$student_id) %>%
    inner_join(select(declared_focal, student_id, first_decl_term),
               by = "student_id") %>%
    filter(term < first_decl_term) %>%
    distinct(student_id) %>%
    mutate(is_pre_major_path = TRUE)

  # Non-focal declared records before first declaration → switched_in pathway
  had_nonfocal_prior <- programs %>%
    filter(program_type %in% c("Major", "Second Major"),
           !major_code %in% focal_codes, !program_name %in% focal_names,
           !is_pre_major,
           student_id %in% declared_focal$student_id) %>%
    inner_join(select(declared_focal, student_id, first_decl_term),
               by = "student_id") %>%
    filter(term < first_decl_term) %>%
    distinct(student_id) %>%
    mutate(is_switched_in = TRUE)

  declared_focal %>%
    left_join(had_focal_pre,      by = "student_id") %>%
    left_join(had_nonfocal_prior, by = "student_id") %>%
    mutate(entry_pathway = case_when(
      is_pre_major_path ~ "pre_major",
      is_switched_in    ~ "switched_in",
      TRUE               ~ "direct"
    )) %>%
    select(student_id, entry_pathway)
}


# ---------------------------------------------------------------------------
# classify_origin
# ---------------------------------------------------------------------------

#' Classify Student UNM Origin
#'
#' Returns "transfer", "unm", or "unknown" for each student based on the
#' student_population field in cedar_programs. Uses the student's earliest
#' term across ALL programs — not just focal — so a student who enrolled at
#' UNM as a transfer before declaring the focal program is correctly classified.
#'
#' @param programs Data frame. cedar_programs (all programs, not just focal).
#' @param candidate_ids Character vector. Student IDs to classify.
#' @return Data frame with columns student_id (chr) and origin (chr).
classify_origin <- function(programs, candidate_ids) {
  if (!"student_population" %in% names(programs)) {
    message("[population.R] student_population column absent; origin = 'unknown' for all students.")
    return(tibble(student_id = candidate_ids, origin = "unknown"))
  }
  programs %>%
    filter(student_id %in% candidate_ids) %>%
    group_by(student_id) %>%
    filter(term == min(term)) %>%
    summarize(
      origin = if_else(
        any(grepl("transfer", student_population, ignore.case = TRUE), na.rm = TRUE),
        "transfer", "unm"
      ),
      .groups = "drop"
    )
}


# ---------------------------------------------------------------------------
# classify_entry_method
# ---------------------------------------------------------------------------

#' Classify How a Student First Arrived at the Focal Unit
#'
#' Returns one of three values for each student:
#'   first_program — no prior program record of any kind (declared or pre-major,
#'                   in any unit) before their first focal record. This is their
#'                   first academic program affiliation.
#'   switched_in   — had at least one prior program record somewhere before
#'                   arriving at the focal unit.
#'   unclear       — their first focal record coincides with the earliest term
#'                   in the full programs table, so prior history is unobservable.
#'
#' The unclear flag applies only to students who appear "direct" — if a student
#' already has positive evidence of a prior program (switched_in) or a focal
#' pre-major record, that evidence stands regardless of the data boundary.
#'
#' @param programs Data frame. cedar_programs (all programs, not just focal).
#' @param focal_names Character vector. Focal program names.
#' @param min_data_term Integer. Earliest term in the full programs table.
#' @return Data frame with columns student_id (chr) and entry_method (chr).
classify_entry_method <- function(programs, focal_names, min_data_term, focal_codes = character(0)) {
  focal_records <- programs %>%
    filter(program_type %in% c("Major", "Second Major"),
           major_code %in% focal_codes | program_name %in% focal_names)

  first_focal <- focal_records %>%
    group_by(student_id) %>%
    summarize(first_unit_term = min(term, na.rm = TRUE), .groups = "drop")

  if (nrow(first_focal) == 0)
    return(tibble(student_id = character(), entry_method = character()))

  # Any program record (any unit, pre-major or declared) before first focal term
  had_prior <- programs %>%
    filter(program_type %in% c("Major", "Second Major"),
           student_id %in% first_focal$student_id) %>%
    inner_join(first_focal, by = "student_id") %>%
    filter(term < first_unit_term) %>%
    distinct(student_id) %>%
    pull(student_id)

  first_focal %>%
    mutate(entry_method = case_when(
      student_id %in% had_prior        ~ "switched_in",
      first_unit_term <= min_data_term ~ "unclear",
      TRUE                             ~ "first_program"
    )) %>%
    select(student_id, entry_method)
}


# ---------------------------------------------------------------------------
# classify_entry_status
# ---------------------------------------------------------------------------

#' Classify Whether a Student First Engaged as a Pre-Major or Declared Major
#'
#' Returns "pre_major" if the student's first focal program record was a
#' pre-major record, "major" if it was a declared major. Purely about their
#' first record — does not consider later declarations.
#'
#' @param programs Data frame. cedar_programs (all programs, not just focal).
#' @param focal_names Character vector. Focal program names.
#' @return Data frame with columns student_id (chr) and entry_status (chr).
classify_entry_status <- function(programs, focal_names, focal_codes = character(0)) {
  programs %>%
    filter(program_type %in% c("Major", "Second Major"),
           major_code %in% focal_codes | program_name %in% focal_names) %>%
    group_by(student_id) %>%
    filter(term == min(term)) %>%
    summarize(
      # "major" wins when a student has both declared and pre-major records in
      # their first focal term (i.e., declared on the same day they appear as pre-major).
      entry_status = if_else(any(!is_pre_major), "major", "pre_major"),
      .groups = "drop"
    )
}


# ---------------------------------------------------------------------------
# build_population  (orchestrator)
# ---------------------------------------------------------------------------

#' Build a Student Population
#'
#' Constructs a population data frame from cedar_programs using the
#' outcome-oriented pipeline. Returns one row per student with:
#'   student_id, population_label, outcome,
#'   origin (unm/transfer/unknown),
#'   entry_method (first_program/switched_in/unclear),
#'   entry_status (pre_major/major),
#'   first_unm_term, first_unit_term, last_unit_term, last_declared_term,
#'   last_record_term, relevant_until
#'
#' @param programs Data frame. cedar_programs.
#' @param degrees Data frame or NULL. cedar_degrees.
#' @param students Data frame or NULL. cedar_students (reserved for future use).
#' @param opt List of options:
#'   type          — "preset", "dept", or "major". Default "preset".
#'   program_names — required for preset/major types.
#'   dept_code     — required for dept type.
#'   outcomes      — character vector of outcomes to include. Default: all six outcomes
#'     (graduated, switched_out, stopped_out, ongoing, chose_elsewhere, left_undeclared).
#'   split_by      — "none" (default), "outcome", "entry", "entry_status", or
#'     "transfer". When "entry", population_label is set to entry_method per
#'     student. When "entry_status", population_label is set to whether the
#'     student first appeared as a declared major or pre-major. When "transfer",
#'     population_label is set to origin per student.
#'   campus        — character vector. Filter by student_campus. Optional.
#'   student_level — character vector. Filter by student_level before outcome
#'     detection. Common values: "Undergraduate", "Graduate". When omitted,
#'     all levels are included and undergrad/grad students are mixed in a
#'     single population. Pass "Undergraduate" to build a clean undergrad
#'     cohort for a department that also has grad programs.
#' @return Data frame with one row per student.
#' @return Data frame with one row per student.
build_population <- function(programs, degrees = NULL, students = NULL, opt = list()) {
  type <- opt$type %||% "preset"

  if (type == "demographic") return(build_demographic_population(programs, opt))

  if (!"is_pre_major" %in% names(programs))
    stop("[population.R] cedar_programs missing is_pre_major column.")

  # Campus filter
  if (!is.null(opt$campus) && length(opt$campus) > 0)
    programs <- filter(programs, student_campus %in% opt$campus)

  # Student level filter (e.g., "Undergraduate" to exclude grad students)
  if (!is.null(opt$student_level) && length(opt$student_level) > 0) {
    if (!"student_level" %in% names(programs))
      stop("[population.R] cedar_programs missing student_level column. ",
           "Re-run transform-to-cedar.R to regenerate cedar_programs.qs.")
    programs <- filter(programs, student_level %in% opt$student_level)
    message("[population.R] student_level filter applied: ",
            paste(opt$student_level, collapse = ", "))
  }

  # Identify focal programs
  focal_programs <- get_focal_programs(programs, opt)
  if (nrow(focal_programs) == 0) {
    if (type == "dept") {
      message("[population.R] No declared-major records found for dept_code = '", opt$dept_code,
              "'. Check that cedar_programs has rows with program_type = 'Major' and ",
              "is_pre_major = FALSE for this department.")
    } else {
      message("[population.R] No declared-major records matched program_names = '",
              paste(opt$program_names, collapse = ", "), "'. ",
              "Check program_names spelling against cedar_programs$program_name.")
    }
    return(.empty_population())
  }
  focal_names <- focal_programs$program_name
  focal_codes <- unique(na.omit(focal_programs$major_code))
  message("[population.R] Building ", type, " population: ",
          paste(focal_names, collapse = ", "),
          " | codes: ", if (length(focal_codes)) paste(focal_codes, collapse = ", ") else "(none)")

  # All candidates: ever appeared in a focal program (declared or pre-major).
  # Code-first matching; name fallback covers un-coded records in older data.
  all_focal <- programs %>%
    filter(program_type %in% c("Major", "Second Major"),
           major_code %in% focal_codes | program_name %in% focal_names)

  candidate_ids <- unique(all_focal$student_id)
  if (length(candidate_ids) == 0) return(.empty_population())

  # ── Outcome detection ──────────────────────────────────────────────────────
  max_data_term <- max(programs$term, na.rm = TRUE)
  message("[population.R] max_data_term resolved to: ", max_data_term)

  ongoing_ids     <- get_ongoing_ids(programs, focal_names, max_data_term, focal_codes = focal_codes)
  graduated_ids   <- get_graduated_ids(programs, degrees, focal_names)
  switched_ids    <- get_switched_out_ids(programs, focal_names, focal_codes = focal_codes)
  never_decl_ids  <- get_never_declared_ids(programs, focal_names, max_data_term, focal_codes = focal_codes)

  # Split never_declared into two meaningful sub-outcomes:
  #   chose_elsewhere — had a focal pre-major but declared a different program
  #   left_undeclared — had a focal pre-major and never declared any program
  if (length(never_decl_ids) > 0) {
    last_pre_terms <- all_focal %>%
      filter(student_id %in% never_decl_ids, is_pre_major) %>%
      group_by(student_id) %>%
      summarize(last_pre_term = max(term, na.rm = TRUE), .groups = "drop")

    declared_after <- programs %>%
      filter(program_type %in% c("Major", "Second Major"),
             !is_pre_major,
             student_id %in% never_decl_ids) %>%
      inner_join(last_pre_terms, by = "student_id") %>%
      filter(term >= last_pre_term) %>%
      pull(student_id) %>%
      unique()

    chose_elsewhere_ids <- intersect(never_decl_ids, declared_after)
    left_undeclared_ids <- setdiff(never_decl_ids, declared_after)
  } else {
    chose_elsewhere_ids <- character(0)
    left_undeclared_ids <- character(0)
  }

  # stopped_out = all declared candidates not accounted for above
  all_declared_ids <- all_focal %>%
    filter(!is_pre_major) %>%
    pull(student_id) %>%
    unique()

  # Enrollment-based switch detection: candidates who have any enrollment
  # record in cedar_students AFTER their last focal term are still at UNM —
  # reclassify as switched_out even if they never formally declared another
  # program. This prevents students who quietly kept taking courses from being
  # counted as stop-outs just because Banner has no re-declaration record.
  # Only runs when cedar_students is provided (students param).
  if (!is.null(students) && nrow(students) > 0 && "term" %in% names(students)) {
    program_stopped_candidates <- setdiff(all_declared_ids,
                                          c(ongoing_ids, graduated_ids, switched_ids))
    if (length(program_stopped_candidates) > 0) {
      last_focal_by_student <- all_focal %>%
        filter(!is_pre_major, student_id %in% program_stopped_candidates) %>%
        group_by(student_id) %>%
        summarize(last_focal_term = max(term, na.rm = TRUE), .groups = "drop")

      enrollment_after <- students %>%
        filter(student_id %in% program_stopped_candidates) %>%
        distinct(student_id, term) %>%
        inner_join(last_focal_by_student, by = "student_id") %>%
        filter(term > last_focal_term) %>%
        pull(student_id) %>%
        unique()

      if (length(enrollment_after) > 0) {
        message("[population.R] Enrollment-based switched_out: ", length(enrollment_after),
                " candidates reclassified via cedar_students enrollment after last focal term.")
        switched_ids <- union(switched_ids, enrollment_after)
      }
    }
  }

  stopped_ids          <- setdiff(all_declared_ids, c(ongoing_ids, graduated_ids, switched_ids))
  current_premajor_ids <- setdiff(ongoing_ids, all_declared_ids)

  message("[population.R] ongoing=", length(ongoing_ids),
          " graduated=", length(graduated_ids),
          " switched_out=", length(switched_ids),
          " stopped_out=", length(stopped_ids),
          " chose_elsewhere=", length(chose_elsewhere_ids),
          " left_undeclared=", length(left_undeclared_ids))

  # ── Entry classification ────────────────────────────────────────────────────
  min_data_term  <- min(programs$term, na.rm = TRUE)
  origin_tbl     <- classify_origin(programs, candidate_ids)
  entry_meth_tbl <- classify_entry_method(programs, focal_names, min_data_term, focal_codes = focal_codes)
  entry_stat_tbl <- classify_entry_status(programs, focal_names, focal_codes = focal_codes)

  # ── Timing: unit entry, unit exit, and UNM-wide records ───────────────────
  # first_unit_term   = first term in any focal program record (declared or pre-major)
  # last_declared_term= last term with a declared (non-pre-major) focal record; NA for
  #                     pre-major-only students. Used internally for graduation windows
  #                     and relevant_until.
  # last_unit_term    = last term in any focal program record (declared or pre-major).
  #                     Includes pre-major so the unit sees the full window of their
  #                     potential students.
  timing <- all_focal %>%
    group_by(student_id) %>%
    summarize(
      first_unit_term    = as.integer(min(term, na.rm = TRUE)),
      last_declared_term = {
        vals <- term[!is_pre_major]
        if (length(vals) > 0L) as.integer(max(vals, na.rm = TRUE)) else NA_integer_
      },
      last_unit_term     = as.integer(max(term, na.rm = TRUE)),
      has_declared       = any(!is_pre_major),
      .groups = "drop"
    )

  # first_unm_term / last_record_term — UNM-wide enrollment bookends from
  # cedar_students. first_unm_term may predate first_unit_term for students who
  # were at UNM before declaring this program. last_record_term may postdate
  # last_unit_term for students who continued at UNM after leaving the unit.
  # Both are NA when cedar_students is not available.
  unm_timing <- if (!is.null(students) && nrow(students) > 0L &&
                    "term" %in% names(students)) {
    students %>%
      group_by(student_id) %>%
      summarize(
        first_unm_term   = as.integer(min(term, na.rm = TRUE)),
        last_record_term = as.integer(max(term, na.rm = TRUE)),
        .groups = "drop"
      )
  } else {
    tibble(student_id = character(), first_unm_term = integer(), last_record_term = integer())
  }

  # ── Assemble outcome table ─────────────────────────────────────────────────
  outcome_tbl <- tibble(student_id = candidate_ids) %>%
    mutate(outcome = case_when(
      student_id %in% ongoing_ids         ~ "ongoing",
      student_id %in% graduated_ids       ~ "graduated",
      student_id %in% switched_ids        ~ "switched_out",
      student_id %in% chose_elsewhere_ids ~ "chose_elsewhere",
      student_id %in% left_undeclared_ids ~ "left_undeclared",
      TRUE                                ~ "stopped_out"
    ))

  result <- outcome_tbl %>%
    left_join(timing,         by = "student_id") %>%
    left_join(unm_timing,     by = "student_id") %>%
    left_join(origin_tbl,     by = "student_id") %>%
    left_join(entry_meth_tbl, by = "student_id") %>%
    left_join(entry_stat_tbl, by = "student_id") %>%
    mutate(origin = coalesce(origin, "unknown")) %>%
    mutate(
      # relevant_until = the last term whose enrollment rows are included in
      # analysis for this student. NA means no ceiling (ongoing students).
      # For non-ongoing declared students it is their last_declared_term, which
      # means any enrollment AFTER they left the focal program is excluded.
      # For pre-major-only students it falls back to last_unit_term.
      # Note: graduated students may have taken courses during their final
      # semester that post-date their last Banner program record — those rows
      # are intentionally excluded here to avoid attributing post-degree
      # activity to the focal program population.
      relevant_until = case_when(
        outcome == "ongoing"         ~ NA_integer_,
        !is.na(last_declared_term)  ~ as.integer(last_declared_term),
        TRUE                         ~ as.integer(last_unit_term)
      )
    )

  # ── Capture pre-major conversion stats before scope filter ──────────────────
  # entry_status is populated for all candidates here. Attaching these counts
  # so pop_audit_ui can show accurate conversion rates even when scope = "pre_only"
  # hides the declared outcomes from the analysis population.
  .conv_stats <- list(
    n_converted       = sum(!is.na(result$entry_status) &
                              result$entry_status == "pre_major" &
                              result$outcome %in% c("ongoing", "graduated",
                                                    "switched_out", "stopped_out"),
                            na.rm = TRUE),
    n_chose_elsewhere = sum(result$outcome == "chose_elsewhere", na.rm = TRUE),
    n_left_undeclared = sum(result$outcome == "left_undeclared", na.rm = TRUE)
  )

  # ── Filter by outcome ──────────────────────────────────────────────────────
  valid_outcomes <- c("graduated", "switched_out", "stopped_out",
                      "ongoing", "chose_elsewhere", "left_undeclared")
  # Default scope is declared students only.
  # Pre-major sub-outcomes (chose_elsewhere, left_undeclared) must be
  # requested explicitly — they were part of never_declared before bcc3fed.
  outcomes_keep <- opt$outcomes %||%
    c("graduated", "switched_out", "stopped_out", "ongoing")

  unknown <- setdiff(outcomes_keep, valid_outcomes)
  if (length(unknown) > 0)
    stop("[population.R] Unknown outcome values: ", paste(unknown, collapse = ", "))

  result <- filter(result, outcome %in% outcomes_keep)

  if (nrow(result) == 0) return(.empty_population())

  # ── Assign population_label ────────────────────────────────────────────────
  split_by   <- opt$split_by %||% "none"
  label_base <- if (type == "dept") {
    opt$dept_code %||% "dept"
  } else if (type == "major") {
    n <- length(focal_names)
    if (n == 1) focal_names[1]
    else if (n == 2) paste(focal_names, collapse = " / ")
    else paste0(focal_names[1], " / +", n - 1L, " more")
  } else {
    type
  }

  result <- mutate(result, population_label = case_when(
    split_by == "outcome"  ~ outcome,
    split_by == "entry"    ~ entry_method,
    split_by == "entry_status" ~ entry_status,
    split_by == "transfer" ~ origin,
    TRUE                   ~ label_base
  ))

  out <- select(result, student_id, population_label, outcome,
                origin, entry_method, entry_status,
                first_unm_term, first_unit_term, last_unit_term, last_declared_term,
                last_record_term, relevant_until)
  attr(out, "conversion_stats") <- .conv_stats
  out
}


# ---------------------------------------------------------------------------
# get_focal_programs  (shared helper, called by build_population)
# ---------------------------------------------------------------------------

#' Get Focal Program Names for a Population Build
#'
#' Resolves focal program names from opt depending on type. Returns a data frame
#' of distinct program_name + major_code values that are in scope.
#'
#' @param programs Data frame. cedar_programs.
#' @param opt List of options (type, program_names, dept_code).
#' @return Data frame with columns program_name and major_code.
#' @keywords internal
get_focal_programs <- function(programs, opt) {
  type <- opt$type %||% "preset"

  if (type %in% c("preset", "major")) {
    pnames <- opt$program_names
    if (is.null(pnames) || length(pnames) == 0)
      stop("[population.R] opt$program_names is required for type = '", type, "'")
    programs %>%
      filter(program_type %in% c("Major", "Second Major"),
             program_name %in% pnames, !is_pre_major) %>%
      distinct(program_name, major_code)

  } else if (type == "dept") {
    dept <- opt$dept_code
    if (is.null(dept) || !nzchar(dept))
      stop("[population.R] opt$dept_code is required for type = 'dept'")
    if (!"dept_code" %in% names(programs))
      stop("[population.R] cedar_programs missing dept_code column. Re-run transform-to-cedar.R.")
    programs %>%
      filter(program_type %in% c("Major", "Second Major"),
             dept_code == dept, !is_pre_major) %>%
      distinct(program_name, major_code)

  } else {
    stop("[population.R] get_focal_programs() not supported for type = '", type, "'")
  }
}


# ---------------------------------------------------------------------------
# build_demographic_population  (separate dispatch, not outcome-based)
# ---------------------------------------------------------------------------

#' Build a Demographic Population
#'
#' Identifies students based on demographic indicators stored in cedar_programs.
#' Membership is resolved as "ever" — a student qualifies if they had the
#' indicator in ANY term, not just the most recent.
#'
#' @param programs Data frame. cedar_programs.
#' @param opt Options list: pell_eligible, first_gen, time_status, ipeds_race,
#'   gender, campus, term.
#' @return tibble with student_id, population_label, and stub columns
#'   outcome = NA, origin/entry_method/entry_status = NA, relevant_until = NA.
#' @keywords internal
build_demographic_population <- function(programs, opt = list()) {
  df <- programs
  if (!is.null(opt$campus)) df <- filter(df, student_campus %in% opt$campus)
  if (!is.null(opt$term))   df <- filter(df, term %in% opt$term)

  id_sets     <- list()
  label_parts <- character(0)

  if (isTRUE(opt$pell_eligible)) {
    if (!"pell_eligible" %in% names(df))
      stop("[population.R] cedar_programs does not have a pell_eligible column. ",
           "Re-run transform-to-cedar.R to regenerate cedar_programs.qs.")
    id_sets[["pell"]] <- df %>%
      filter(!is.na(pell_eligible) & pell_eligible) %>%
      distinct(student_id) %>% pull(student_id)
    label_parts <- c(label_parts, "pell")
  }

  if (isTRUE(opt$first_gen)) {
    if (!"first_gen" %in% names(df))
      stop("[population.R] cedar_programs does not have a first_gen column. ",
           "Re-run transform-to-cedar.R to regenerate cedar_programs.qs.")
    id_sets[["first_gen"]] <- df %>%
      filter(!is.na(first_gen) & first_gen) %>%
      distinct(student_id) %>% pull(student_id)
    label_parts <- c(label_parts, "first_gen")
  }

  if (!is.null(opt$time_status) && length(opt$time_status) > 0) {
    id_sets[["time_status"]] <- df %>%
      filter(time_status %in% opt$time_status) %>%
      distinct(student_id) %>% pull(student_id)
    label_parts <- c(label_parts, paste(opt$time_status, collapse = "+"))
  }

  if (!is.null(opt$ipeds_race) && length(opt$ipeds_race) > 0) {
    id_sets[["ipeds_race"]] <- df %>%
      filter(ipeds_race %in% opt$ipeds_race) %>%
      distinct(student_id) %>% pull(student_id)
    label_parts <- c(label_parts, paste(opt$ipeds_race, collapse = "+"))
  }

  if (!is.null(opt$gender) && length(opt$gender) > 0) {
    id_sets[["gender"]] <- df %>%
      filter(gender %in% opt$gender) %>%
      distinct(student_id) %>% pull(student_id)
    label_parts <- c(label_parts, paste(opt$gender, collapse = "+"))
  }

  if (length(id_sets) == 0)
    stop("[population.R] build_demographic_population() requires at least one filter ",
         "(pell_eligible, first_gen, time_status, ipeds_race, or gender).")

  ids   <- Reduce(intersect, id_sets)
  label <- paste(label_parts, collapse = "_")
  message("[population.R] Demographic population (", label, "): ", length(ids), " students")

  tibble(
    student_id       = ids,
    population_label = label,
    outcome          = NA_character_,
    origin           = NA_character_,
    entry_method     = NA_character_,
    entry_status     = NA_character_,
    relevant_until   = NA_integer_
  )
}


.empty_population <- function() {
  tibble(
    student_id         = character(),
    population_label   = character(),
    outcome            = character(),
    origin             = character(),
    entry_method       = character(),
    entry_status       = character(),
    first_unm_term     = integer(),
    first_unit_term    = integer(),
    last_unit_term     = integer(),
    last_declared_term = integer(),
    last_record_term   = integer(),
    relevant_until     = integer()
  )
}
