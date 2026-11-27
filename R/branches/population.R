#' Population Building
#'
#' Isolated outcome detection functions + orchestrating build_population().
#' Each function is independently testable and returns a character vector
#' of student IDs (or a data frame for get_entry_pathways).
#'
# =============================================================================
# CONCEPTS — read this before reading the code
# =============================================================================
#
# The Pathways system is built on a small ontology. Every function in this
# file (and every cone that takes a `population` argument) assumes it.
#
# FOCAL PROGRAMS AND CANDIDATES
#   A "focal program" is the program (or set of programs) the analysis is
#   about — resolved from opt by resolve_focal_programs() to PROGRAM CODES,
#   never names: the codes selected, every code a confirmed whole succession
#   in code_history.csv joins to them (program_successions: LIBA was renamed
#   LAIS), and the pre-majors programs.csv says lead to them (leads_to). A
#   name is not an identity: one Banner name covers several programs (the
#   B.A. and B.S., an online code, a branch campus's), and one program has
#   several names. The resolution rides on the population as
#   attr(, "focal_programs") so a page can say which codes it counted. A
#   "candidate" is any student who EVER had a focal program record, declared
#   or pre-major. Candidates are the universe; everything below classifies
#   them.
#
# SIX OUTCOMES — every candidate gets exactly one
#   Assigned by the case_when in build_population(); FIRST MATCH WINS, so the
#   order below is a precedence rule, not just a list:
#
#     1. ongoing         — has a focal record in the newest data term
#                          (declared, or a pre-major who hasn't had the
#                          chance to declare yet)
#     2. graduated       — focal degree conferred within ~1 academic year of
#                          their last declared focal term
#     3. switched_out    — declared focal, then either declared another
#                          program or kept enrolling at UNM after their last
#                          focal term (they left the PROGRAM, not UNM)
#     4. chose_elsewhere — pre-major only; later declared a DIFFERENT program
#     5. left_undeclared — pre-major only; never declared any program
#     6. stopped_out     — A RESIDUAL, not a detection: declared candidates
#                          matching none of the above. It inherits every
#                          classification error and data gap (unrecorded
#                          degrees, transfers to other institutions, missing
#                          re-declarations). Treat counts as an upper bound.
#
#   Precedence matters: a student who graduated and later re-enrolled in the
#   newest term reads as "ongoing"; a graduate who later switched reads as
#   "graduated". The rule is "the most charitable durable state wins".
#
# THREE ENTRY AXES — independent classifications; do not conflate
#   origin        — who they were when they arrived AT UNM:
#                   "unm" | "transfer" | "unknown"
#   entry_method  — how they arrived AT THE FOCAL UNIT:
#                   "first_program" (unit was their first affiliation
#                   anywhere) | "switched_in" | "unclear" (see censoring)
#   entry_status  — what they were on arrival at the unit:
#                   "pre_major" | "major"
#   A transfer student can be first_program; a native-UNM student can be
#   switched_in. All 12 combinations occur in real data.
#
# SIX TIMESTAMPS — one student's timeline
#   Worked example (HIST is the focal unit):
#
#     term:     201980    202010     202080    202210     202280
#     activity: ENGL +    pre-HIST   declares  last HIST  enrolls in
#               MATH      pre-major  HIST      record     MGMT courses
#
#     first_unm_term     = 201980  first UNM enrollment anywhere
#     first_unit_term    = 202010  first FOCAL record (pre-major counts)
#     last_declared_term = 202210  last declared (non-pre-major) focal record
#     last_unit_term     = 202210  last focal record of ANY kind
#     last_record_term   = 202280  last UNM enrollment anywhere
#     relevant_until     = 202210  see below (outcome here: switched_out)
#
#   first_unm_term can predate first_unit_term (they were at UNM before the
#   unit); last_record_term can postdate last_unit_term (they stayed at UNM
#   after leaving the unit). Both UNM-wide bookends are read off
#   cedar_student_terms' `enrolled` rows (registered or withdrawn after
#   census, CEDAR's one definition; ADR-001 step 2) and are NA when the
#   table isn't supplied.
#
# THE relevant_until CONTRACT
#   relevant_until is the per-student enrollment ceiling for ANALYSIS: rows
#   after it are excluded so a student's post-departure career (the MGMT
#   terms above) isn't attributed to the focal population. NA = no ceiling
#   (ongoing students). Producers/consumers:
#     produced : here, in build_population()
#     enforced : apply_pathways_population_window() in branches/pathways.R
#     consumed : every Pathways-tab analysis via the module's
#                filtered_students()/filtered_attempts() reactives
#   If you build a new population-aware analysis, apply the window — a cone
#   that ignores relevant_until quietly mixes post-departure behavior in.
#
# TWO DATA BOUNDARIES (CENSORING)
#   left  — nothing before min(programs$term) is visible. A student whose
#           first focal record sits on that boundary gets entry_method
#           "unclear": we cannot tell first_program from switched_in.
#   right — outcomes that live in later terms (returned next term, later
#           declared, later took course B) are unobservable near the end of
#           the data. Analyses guard this with the shared observation-window
#           boundary (pathways_observation_boundary() in branches/pathways.R);
#           see the Pathways Methodology panel for the per-analysis rules.
# =============================================================================


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
#' @param focal_codes Character vector. Focal program codes, pre-majors
#'   included (resolve_focal_programs()).
#' @param max_data_term Integer. The most recent term in the data.
#' @return Character vector of student IDs.
get_ongoing_ids <- function(programs, focal_codes, max_data_term) {
  focal <- programs %>%
    filter(program_type %in% c("Major", "Second Major"),
           major_code %in% focal_codes)

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
#' Degrees are matched by `cedar_degrees$major_code`, the same short code
#' cedar_programs carries (every degree row has one), never by name: Banner's
#' degree "Major" and "Program" names cover several programs that share a
#' name ("Architecture" is ARCH, ARCT and its pre-major).
#'
#' @param programs Data frame. cedar_programs.
#' @param degrees Data frame or NULL. cedar_degrees. Returns empty vector if NULL.
#' @param focal_codes Character vector. Focal program codes; the declared ones
#'   anchor the window, and a degree in any of them counts.
#' @return Character vector of student IDs.
get_graduated_ids <- function(programs, degrees, focal_codes) {
  if (is.null(degrees) || nrow(degrees) == 0) return(character(0))
  if (!"major_code" %in% names(degrees))
    stop("[population.R:get_graduated_ids] cedar_degrees is missing the 'major_code' column. ",
         "Re-run transform-to-cedar.R to regenerate cedar_degrees from the Banner degrees export.")

  focal_declared <- programs %>%
    filter(program_type %in% c("Major", "Second Major"),
           major_code %in% focal_codes,
           !is_pre_major)

  # Last declared focal term per student (the graduation window anchor)
  last_focal <- focal_declared %>%
    group_by(student_id) %>%
    summarize(last_focal_term = max(term, na.rm = TRUE), .groups = "drop")

  if (nrow(last_focal) == 0) return(character(0))

  # UNM term codes are YYYYSS integers (10=spring, 60=summer, 80=fall).
  # Adding 100 gives an ~one-academic-year window regardless of starting semester:
  #   spring anchor (202010) → window closes at 202110 (next spring)
  #   fall anchor   (202080) → window closes at 202180 (next fall)
  #   summer anchor (202060) → window closes at 202160 (next summer)
  deg <- degrees[!is.na(degrees$major_code) & degrees$major_code %in% focal_codes, , drop = FALSE]
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
#' @param focal_codes Character vector. Focal program codes.
#' @return Character vector of student IDs.
get_switched_out_ids <- function(programs, focal_codes) {
  declared <- programs %>%
    filter(program_type %in% c("Major", "Second Major"),
           !is_pre_major)

  # Last declared focal term per student
  last_focal <- declared %>%
    filter(major_code %in% focal_codes) %>%
    group_by(student_id) %>%
    summarize(last_focal_term = max(term, na.rm = TRUE), .groups = "drop")

  if (nrow(last_focal) == 0) return(character(0))

  # Non-focal declared records for those students, after their last focal term
  declared %>%
    filter(!major_code %in% focal_codes,
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
#' @param focal_codes Character vector. Focal program codes, pre-majors included.
#' @param max_data_term Integer. The most recent term in the data.
#' @return Character vector of student IDs.
get_never_declared_ids <- function(programs, focal_codes, max_data_term) {
  focal <- programs %>%
    filter(program_type %in% c("Major", "Second Major"),
           major_code %in% focal_codes)

  # Students who ever declared the focal program
  ever_declared <- focal %>%
    filter(!is_pre_major) %>%
    pull(student_id) %>%
    unique()

  # Pre-major-only students and their last pre-major term
  pre_major_only <- focal %>%
    filter(is_pre_major, !student_id %in% ever_declared)

  if (nrow(pre_major_only) == 0) return(character(0))

  pre_major_only %>%
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
#' @param focal_codes Character vector. Focal program codes, pre-majors included.
#' @return Data frame with columns student_id (chr) and entry_pathway (chr).
get_entry_pathways <- function(programs, focal_codes) {
  focal_major <- programs %>%
    filter(program_type %in% c("Major", "Second Major"),
           major_code %in% focal_codes)

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
           !major_code %in% focal_codes,
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
# student_term_entry_type
# ---------------------------------------------------------------------------

#' How each student-term's record says the student arrived: first-time or transfer
#'
#' Reads `student_population`, which the registrar sets in the term a student
#' is new: a first-time student (a fall or spring beginner, or a summer one)
#' or a new transfer. Every other term's value (continuing, readmitted,
#' concurrent, a level change) is not an arrival and is left out.
#'
#' @param programs `cedar_programs`.
#' @return A tibble of `student_id`, `term` and `entry_type` (`"first_time"`
#'   or `"transfer"`), one row per student-term that records an arrival.
student_term_entry_type <- function(programs) {
  missing <- setdiff(c("student_id", "term", "student_population"), names(programs))
  if (length(missing) > 0) {
    stop("[population.R] student_term_entry_type: programs lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  programs %>%
    transmute(student_id, term = as.integer(term),
              entry_type = case_when(
                grepl("First Time.*Fresh|Beg[a-z]* Fresh", student_population, ignore.case = TRUE) ~ "first_time",
                grepl("New Transfer", student_population, ignore.case = TRUE) ~ "transfer",
                TRUE ~ NA_character_)) %>%
    filter(!is.na(entry_type)) %>%
    distinct(student_id, term, entry_type)
}


# ---------------------------------------------------------------------------
# student_arrival_as_of
# ---------------------------------------------------------------------------

#' How each student most recently arrived, as of a term
#'
#' The latest arrival the record holds for the student in or before `term`
#' (student_term_entry_type()): a student who started first-time, left and
#' came back as a new transfer reads transfer. A term recorded both ways
#' reads first-time, as get_major_tenure() reads it. An arrival recorded
#' after `term` is not yet one.
#'
#' @param programs `cedar_programs`.
#' @param term One term code.
#' @return A tibble of `student_id`, `arrived_term` and `entry_type`
#'   (`"first_time"` or `"transfer"`), one row per student with an arrival on
#'   record by `term`. A student the record never calls new by then
#'   (readmitted, moved from another campus or level, here before the records
#'   begin) has no row.
student_arrival_as_of <- function(programs, term) {
  as_of <- suppressWarnings(as.integer(term))
  if (length(as_of) != 1L || is.na(as_of)) {
    stop("[population.R] student_arrival_as_of: term must be one term code.", call. = FALSE)
  }
  student_term_entry_type(programs) %>%
    filter(term <= as_of) %>%
    arrange(desc(term), entry_type) %>%
    distinct(student_id, .keep_all = TRUE) %>%
    transmute(student_id, arrived_term = term, entry_type)
}


# ---------------------------------------------------------------------------
# student_term_semesters
# ---------------------------------------------------------------------------

#' Each student-term's semester since the student arrived
#'
#' The latest arrival the record holds in or before each term at the term's
#' student level, as student_arrival_as_of() reads it (a student who started
#' first-time, left and came back as a new transfer reads transfer; a term
#' recorded both ways reads first-time), and how many regular terms on the
#' term is. An arrival counts only at its own level, the level of the
#' declaration that records it: a graduate student is not counted from the
#' term they started as an undergraduate, as entering_students() reads it. The
#' arrival's own regular term is the 1st semester; a summer arrival's 1st
#' semester is the fall after it. The count is of terms passed, not terms
#' enrolled, as an entering class's semesters are counted
#' (get_entering_class_retention()): a student away for a year comes back in
#' their 5th semester, not their 3rd. Unlike classification it does not move
#' when the registrar's rules do (ISSUES I92).
#'
#' @param student_terms Rows with `student_id`, `term` and `student_level`
#'   (a level code).
#' @param programs `cedar_programs`, for the arrivals (student_term_entry_type())
#'   and their `student_level` (as academic studies names it; translated by
#'   cedar_level_code_from_source()).
#' @return A tibble of `student_id`, `term`, `student_level`, `entry_type`
#'   ("first_time" or "transfer"), `arrived_term` and `semester_here`
#'   (integer; NA for a summer term), one row per distinct student-term with
#'   an arrival at its level on record by then. A student-term with none
#'   (readmitted, moved from another campus or level, here before the records
#'   begin) has no row.
student_term_semesters <- function(student_terms, programs) {
  missing <- setdiff(c("student_id", "term", "student_level"), names(student_terms))
  if (length(missing) > 0) {
    stop("[population.R] student_term_semesters: student_terms lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  if (!"student_level" %in% names(programs)) {
    stop("[population.R] student_term_semesters: programs lacks student_level", call. = FALSE)
  }
  # Each level's arrivals, read by the one classifier.
  arrivals <- programs %>%
    mutate(student_level = cedar_level_code_from_source(student_level)) %>%
    group_by(student_level) %>%
    group_modify(~ student_term_entry_type(.x)) %>%
    ungroup()
  if (anyNA(arrivals$student_level)) {
    stop("[population.R] student_term_semesters: an arrival's level is not in student_levels.csv: ",
         paste(unique(programs$student_level[!is.na(programs$student_level) &
                                              is.na(cedar_level_code_from_source(programs$student_level))]), collapse = ", "),
         call. = FALSE)
  }
  arrivals <- arrivals %>%
    arrange(student_id, student_level, term, entry_type) %>%
    distinct(student_id, student_level, term, .keep_all = TRUE) %>%
    transmute(student_id, student_level, arrived_term = term, entry_type)
  student_terms %>%
    distinct(student_id, term, student_level) %>%
    mutate(term = as.integer(term)) %>%
    inner_join(arrivals, by = join_by(student_id, student_level, closest(term >= arrived_term)), na_matches = "never") %>%
    mutate(first_regular = if_else(arrived_term %% 100L == 60L, arrived_term + 20L, arrived_term),
           semester_here = term_diff(first_regular, term) + 1L,
           semester_here = if_else(is.na(semester_here) | semester_here < 1L, NA_integer_, as.integer(semester_here))) %>%
    select(student_id, term, student_level, entry_type, arrived_term, semester_here)
}


#' The earliest arrival a student in a semester of a term can have
#'
#' The inverse of student_term_semesters()'s count: the regular term
#' `semester - 1` regular terms before `term`, or, when that is a fall, the
#' summer before it (a summer arrival's 1st semester is the fall after). A
#' term's semester holds every student it should only when the arrival
#' records reach back this far.
#'
#' @param term Fall or spring term codes.
#' @param semester Semesters since arrival, 1 or more.
#' @return Integer term codes.
semester_earliest_arrival <- function(term, semester) {
  term <- as.integer(term)
  semester <- as.integer(semester)
  season <- dplyr::case_when(term %% 100L == 10L ~ 0L, term %% 100L == 80L ~ 1L, TRUE ~ NA_integer_)
  if (any(is.na(season) | is.na(semester) | semester < 1L)) {
    stop("[population.R] semester_earliest_arrival: terms must be falls or springs and semesters 1 or more.", call. = FALSE)
  }
  index <- (term %/% 100L) * 2L + season - (semester - 1L)
  (index %/% 2L) * 100L + if_else(index %% 2L == 1L, 60L, 10L)
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
#' @param focal_codes Character vector. Focal program codes, pre-majors included.
#' @param min_data_term Integer. Earliest term in the full programs table.
#' @return Data frame with columns student_id (chr) and entry_method (chr).
classify_entry_method <- function(programs, focal_codes, min_data_term) {
  focal_records <- programs %>%
    filter(program_type %in% c("Major", "Second Major"),
           major_code %in% focal_codes)

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
#' @param focal_codes Character vector. Focal program codes, pre-majors included.
#' @return Data frame with columns student_id (chr) and entry_status (chr).
classify_entry_status <- function(programs, focal_codes) {
  programs %>%
    filter(program_type %in% c("Major", "Second Major"),
           major_code %in% focal_codes) %>%
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
#' @param student_terms Data frame or NULL. cedar_student_terms. Its `enrolled`
#'   rows supply the UNM-wide enrollment bookends and the enrollment-based
#'   continuation evidence; without it both bookends are NA and no candidate
#'   is reclassified. Never cedar_registrations: a waitlist or an early drop is not
#'   an enrolled term.
#' @param opt List of options:
#'   type          — "preset", "dept", or "major". Default "preset".
#'   program_codes — required for the major type: program codes, each a
#'     declared program; a renamed program's other codes and its pre-majors
#'     are added by resolve_focal_programs().
#'   For the preset type, program_codes are a population group's declared
#'     codes (population_group_codes()), resolved the same way.
#'   dept_code     — required for dept type.
#'   program_successions, premajor_leads_to — override the mapping files'
#'     program_successions and premajor_leads_to (tests and what-ifs).
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
#' @return Data frame with one row per student, carrying
#'   attr(, "focal_programs"): resolve_focal_programs()'s list of the codes
#'   counted and why.
build_population <- function(programs, degrees = NULL, student_terms = NULL, opt = list()) {
  type <- opt$type %||% "preset"
  enrolled_terms <- .population_enrolled_terms(student_terms)

  if (type == "demographic") {
    return(build_demographic_population(programs, opt, student_terms = student_terms))
  }

  if (!"is_pre_major" %in% names(programs))
    stop("[population.R] cedar_programs missing is_pre_major column.")

  # Campus and level define who is eligible for the focal population. They do
  # not truncate the history used to classify those students: a later move to
  # another campus or level is precisely the evidence needed to distinguish
  # ongoing, switched-out, and stopped-out outcomes.
  all_programs <- programs
  scope_programs <- programs

  if (!is.null(opt$campus) && length(opt$campus) > 0)
    scope_programs <- filter(scope_programs, student_campus %in% opt$campus)

  # Student level filter (e.g., "Undergraduate" to exclude grad students)
  if (!is.null(opt$student_level) && length(opt$student_level) > 0) {
    if (!"student_level" %in% names(scope_programs))
      stop("[population.R] cedar_programs missing student_level column. ",
           "Re-run transform-to-cedar.R to regenerate cedar_programs.qs.")
    scope_programs <- filter(scope_programs, student_level %in% opt$student_level)
    message("[population.R] student_level filter applied: ",
            paste(opt$student_level, collapse = ", "))
  }

  # Identify focal programs: codes only, never names (see CONCEPTS).
  focal <- resolve_focal_programs(scope_programs, opt)
  focal_codes <- focal$codes$program_code
  selected_codes <- focal$codes$program_code[focal$codes$role == "selected"]
  # Names label the population; they never select a row.
  focal_names <- scope_programs %>%
    filter(program_type %in% c("Major", "Second Major"), !is_pre_major,
           major_code %in% selected_codes, !is.na(program_name)) %>%
    distinct(program_name) %>%
    pull(program_name)
  if (length(focal_names) == 0) focal_names <- selected_codes
  empty <- function() structure(.empty_population(), focal_programs = focal)
  if (length(selected_codes) == 0) {
    if (type == "dept") {
      message("[population.R] No declared-major records found for dept_code = '", opt$dept_code,
              "'. Check that cedar_programs has rows with program_type = 'Major' and ",
              "is_pre_major = FALSE for this department.")
    }
    return(empty())
  }
  message("[population.R] Building ", type, " population: ",
          paste(focal_names, collapse = ", "),
          " | codes: ", paste(focal_codes, collapse = ", "))

  # All candidates: ever appeared in a focal program (declared or pre-major).
  scoped_focal <- scope_programs %>%
    filter(program_type %in% c("Major", "Second Major"),
           major_code %in% focal_codes)

  candidate_ids <- unique(scoped_focal$student_id)
  if (length(candidate_ids) == 0) return(empty())

  # From this point on, restore complete program history for the eligible
  # students. Candidate membership stays scoped; classification does not.
  programs <- all_programs
  all_focal <- programs %>%
    filter(
      student_id %in% candidate_ids,
      program_type %in% c("Major", "Second Major"),
      major_code %in% focal_codes
    )

  # ── Outcome detection ──────────────────────────────────────────────────────
  # The detectors below return OVERLAPPING id sets (a student can qualify for
  # several); the case_when in the assembly step resolves overlaps by
  # precedence — see "SIX OUTCOMES" in the CONCEPTS block at the top of this
  # file. Rough decision tree per candidate:
  #
  #   focal record in newest term?            → ongoing
  #   else focal degree in the window?        → graduated
  #   else other program / UNM enrollment
  #        after last focal term?             → switched_out
  #   else never declared focal:
  #        declared elsewhere later?          → chose_elsewhere
  #        never declared anything?           → left_undeclared
  #   else (declared, no signal of anything)  → stopped_out  (residual)
  max_data_term <- max(programs$term, na.rm = TRUE)
  message("[population.R] max_data_term resolved to: ", max_data_term)

  ongoing_ids     <- get_ongoing_ids(programs, focal_codes, max_data_term)
  graduated_ids   <- get_graduated_ids(programs, degrees, focal_codes)
  switched_ids    <- get_switched_out_ids(programs, focal_codes)
  never_decl_ids  <- get_never_declared_ids(programs, focal_codes, max_data_term)

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

  # Enrollment-based switch detection: candidates who were enrolled at UNM in
  # any term AFTER their last focal term are still at UNM — reclassify as
  # switched_out even if they never formally declared another program. This
  # prevents students who quietly kept taking courses from being counted as
  # stop-outs just because Banner has no re-declaration record. Enrolled is
  # cedar_student_terms' `enrolled`: a waitlist-only or early-drop-only term
  # is not evidence of being at UNM. Only runs when the table is provided.
  if (!is.null(enrolled_terms)) {
    program_stopped_candidates <- setdiff(all_declared_ids,
                                          c(ongoing_ids, graduated_ids, switched_ids))
    if (length(program_stopped_candidates) > 0) {
      last_focal_by_student <- all_focal %>%
        filter(!is_pre_major, student_id %in% program_stopped_candidates) %>%
        group_by(student_id) %>%
        summarize(last_focal_term = max(term, na.rm = TRUE), .groups = "drop")

      enrollment_after <- enrolled_terms %>%
        filter(student_id %in% program_stopped_candidates) %>%
        inner_join(last_focal_by_student, by = "student_id") %>%
        filter(term > last_focal_term) %>%
        pull(student_id) %>%
        unique()

      if (length(enrollment_after) > 0) {
        message("[population.R] Enrollment-based switched_out: ", length(enrollment_after),
                " candidates reclassified: enrolled at UNM after their last focal term.")
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
  entry_meth_tbl <- classify_entry_method(programs, focal_codes, min_data_term)
  entry_stat_tbl <- classify_entry_status(programs, focal_codes)

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

  # first_unm_term / last_record_term — UNM-wide enrollment bookends, the
  # first and last term the student was enrolled anywhere at UNM
  # (cedar_student_terms). first_unm_term may predate first_unit_term for
  # students who were at UNM before declaring this program. last_record_term
  # may postdate last_unit_term for students who continued at UNM after
  # leaving the unit. Both are NA when the table is not available.
  unm_timing <- .population_enrollment_bookends(enrolled_terms)

  # ── Assemble outcome table ─────────────────────────────────────────────────
  # PRECEDENCE: first match wins, so this ordering is load-bearing — e.g. a
  # graduate with a focal record in the newest term reads as "ongoing", and a
  # graduate who later switched reads as "graduated". The rule is "the most
  # charitable durable state wins" (see CONCEPTS block).
  #
  # stopped_out is the RESIDUAL bucket, not a positive detection: it absorbs
  # every candidate the detectors above couldn't account for, including data
  # gaps (unrecorded degrees, transfers out, missing re-declarations). Treat
  # stopped_out counts as an upper bound.
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

  if (nrow(result) == 0) return(empty())

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
  attr(out, "focal_programs") <- focal
  out
}


# ---------------------------------------------------------------------------
# resolve_focal_programs  (shared helper, called by build_population)
# ---------------------------------------------------------------------------

#' The program codes a population build counts, and why each is in
#'
#' Codes, never names. The selected codes come from opt: the major and preset
#' types' `program_codes` as given (a preset's are a population group's), the
#' dept type's declared codes whose own `dept_code` is the department. To those it adds every code a confirmed whole
#' succession joins them to (code_history.csv, `program_successions`), then
#' the pre-majors that lead to any of them (programs.csv `leads_to`; FFDA is
#' named "FDMA" and leads to Film and Digital Arts, ISSUES.md I38) and, for a
#' department, the department's own pre-major codes.
#'
#' @param programs Data frame. cedar_programs, scoped to the eligible rows.
#' @param opt List of options (type, program_codes, dept_code,
#'   and the program_successions / premajor_leads_to overrides).
#' @return A list: `codes`, a tibble of program_code and role ("selected",
#'   "succession" or "pre_major") with `leads_to` on a pre-major; and
#'   `successions`, the code_history.csv rows that joined codes
#'   (from_code, to_code, effective_term).
#' @keywords internal
resolve_focal_programs <- function(programs, opt) {
  type <- opt$type %||% "preset"
  successions <- opt$program_successions %||% program_successions
  leads_to <- opt$premajor_leads_to %||% premajor_leads_to
  declared <- programs %>%
    filter(program_type %in% c("Major", "Second Major"), !is_pre_major)

  own_pre_majors <- character(0)
  selected <- if (type %in% c("major", "preset")) {
    if (length(opt[["program_names"]]) > 0)
      stop("[population.R] type = '", type, "' selects by major code: pass opt$program_codes, ",
           "not program_names (one name covers several programs).")
    if (length(opt$program_codes) == 0)
      stop("[population.R] opt$program_codes is required for type = '", type, "'")
    as.character(opt$program_codes)
  } else if (type == "dept") {
    dept <- opt$dept_code
    if (is.null(dept) || !nzchar(dept))
      stop("[population.R] opt$dept_code is required for type = 'dept'")
    if (!"dept_code" %in% names(programs))
      stop("[population.R] cedar_programs missing dept_code column. Re-run transform-to-cedar.R.")
    own_pre_majors <- programs$major_code[programs$program_type %in% c("Major", "Second Major") &
                                            programs$is_pre_major & programs$dept_code %in% dept]
    declared$major_code[declared$dept_code %in% dept]
  } else {
    stop("[population.R] resolve_focal_programs() not supported for type = '", type, "'")
  }
  selected <- sort(unique(stats::na.omit(selected)))

  family <- program_succession_family(selected, successions)
  joined <- sort(setdiff(family, selected))
  pre <- union(pre_major_codes_leading_to(family, leads_to),
               stats::na.omit(own_pre_majors))
  pre <- sort(setdiff(pre, family))

  used <- successions[successions$from_code %in% family & successions$to_code %in% family, ,
                      drop = FALSE]
  list(
    codes = tibble(
      program_code = c(selected, joined, pre),
      role = rep(c("selected", "succession", "pre_major"),
                 c(length(selected), length(joined), length(pre))),
      leads_to = c(rep(NA_character_, length(selected) + length(joined)),
                   unname(leads_to[pre]))
    ),
    successions = tibble(from_code = as.character(used$from_code),
                         to_code = as.character(used$to_code),
                         effective_term = as.integer(used$effective_term))
  )
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
#'   gender, campus, student_level, term.
#' @param student_terms Data frame or NULL. cedar_student_terms, whose
#'   `enrolled` rows give the UNM-wide first/last enrollment bookends.
#' @return Population tibble with one row per student. Program-specific outcome
#'   and entry fields are NA; UNM-wide bookends are populated when possible.
#' @keywords internal
build_demographic_population <- function(programs, opt = list(), student_terms = NULL) {
  df <- programs
  if (!is.null(opt$campus)) df <- filter(df, student_campus %in% opt$campus)
  if (!is.null(opt$student_level) && length(opt$student_level) > 0) {
    if (!"student_level" %in% names(df)) {
      stop("[population.R] cedar_programs missing student_level column. ",
           "Re-run transform-to-cedar.R to regenerate cedar_programs.qs.")
    }
    df <- filter(df, student_level %in% opt$student_level)
  }
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

  out <- tibble(
    student_id       = ids,
    population_label = label,
    outcome          = NA_character_,
    origin           = NA_character_,
    entry_method     = NA_character_,
    entry_status     = NA_character_,
    first_unm_term   = NA_integer_,
    first_unit_term  = NA_integer_,
    last_unit_term   = NA_integer_,
    last_declared_term = NA_integer_,
    last_record_term = NA_integer_,
    relevant_until   = NA_integer_
  )

  enrolled_terms <- .population_enrolled_terms(student_terms)
  if (!is.null(enrolled_terms)) {
    bookends <- .population_enrollment_bookends(enrolled_terms %>% filter(student_id %in% ids))
    out <- out %>%
      select(-first_unm_term, -last_record_term) %>%
      left_join(bookends, by = "student_id")
  }

  out
}


# The student-terms a population reads: one row per (student_id, term) the
# student was enrolled at UNM, off cedar_student_terms (ADR-001 step 2). NULL
# when no table was supplied, so callers without one get NA bookends and no
# reclassification, never a guess. A table without `enrolled` is refused, so
# cedar_registrations handed in its place cannot count a waitlist or an early drop
# as a term at UNM.
.population_enrolled_terms <- function(student_terms) {
  if (is.null(student_terms)) return(NULL)
  needed <- c("student_id", "term", "enrolled")
  missing_cols <- setdiff(needed, names(student_terms))
  if (length(missing_cols) > 0L) {
    stop("[population.R] student_terms is missing column(s): ",
         paste(missing_cols, collapse = ", "),
         ". Pass cedar_student_terms, not cedar_registrations.")
  }
  student_terms %>%
    filter(enrolled) %>%
    distinct(student_id, term)
}

# first_unm_term / last_record_term: the first and last term the student was
# enrolled anywhere at UNM. Empty, with the right columns, for NULL.
.population_enrollment_bookends <- function(enrolled_terms) {
  if (is.null(enrolled_terms)) {
    return(tibble(student_id = character(), first_unm_term = integer(),
                  last_record_term = integer()))
  }
  enrolled_terms %>%
    group_by(student_id) %>%
    summarize(
      first_unm_term   = as.integer(min(term, na.rm = TRUE)),
      last_record_term = as.integer(max(term, na.rm = TRUE)),
      .groups = "drop"
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


# ---------------------------------------------------------------------------
# Named population groups  (registry: R/lists/population-presets.R)
# ---------------------------------------------------------------------------
#
# One definition of "health professions", shared by Pathways, the projection
# growth scenario, and anything added later. Groups declare PROGRAM NAMES; these
# resolve them to the Banner major codes that class-list and program rows key on.
#
# Resolution is deliberately a union of two mechanisms, because neither is
# complete on its own:
#
#   1. name match  — a pre-major normally carries its major's program_name
#                    (FRAD and RADS are both "Radiologic Sciences"), so this
#                    picks up declared and pre-major codes together, including
#                    codes Banner added after this list was written.
#   2. leads_to   — catches pre-majors whose NAME has drifted from the major
#                    they lead to, which name matching alone would split
#                    (premajor_leads_to, from programs.csv; it replaced the
#                    premaj_canon list at ADR-002 Stage 4).
#
# ISSUES.md I7 documents the live example of each failing separately.

population_group_ids <- function() names(CEDAR_POPULATION_GROUPS)


population_group_choices <- function() {
  ids <- population_group_ids()
  stats::setNames(ids, ids)
}


#' The group a surface preselects
#'
#' @param surface One of CEDAR_POPULATION_GROUP_SURFACES ("pathways", "scenario").
#' @return The group id population_groups.csv marks default_for that surface,
#'   else the first group in the file. Documented, not a silent fallback: a file
#'   that names no default for a surface gets its first group.
population_group_default <- function(surface) {
  if (!surface %in% CEDAR_POPULATION_GROUP_SURFACES) {
    stop("[population.R] Unknown population group surface: ", surface, call. = FALSE)
  }
  if (surface %in% names(CEDAR_POPULATION_GROUP_DEFAULTS)) {
    return(unname(CEDAR_POPULATION_GROUP_DEFAULTS[[surface]]))
  }
  population_group_ids()[[1]]
}


#' The declared program codes population_groups.csv lists for a group
population_group_codes <- function(group_id) {
  group <- CEDAR_POPULATION_GROUPS[[group_id]]
  if (is.null(group)) {
    stop("[population.R] Unknown population group: ", group_id, call. = FALSE)
  }
  unique(group$codes)
}


#' The pre-major codes whose `leads_to` is one of the given program codes
#'
#' @param codes Declared program codes.
#' @param leads_to Named character vector, pre-major code -> the code it leads
#'   to (default `premajor_leads_to`, from programs.csv).
#' @return Character vector of pre-major codes; empty when none lead there.
pre_major_codes_leading_to <- function(codes, leads_to = premajor_leads_to) {
  names(leads_to)[!is.na(leads_to) & leads_to %in% codes]
}


#' Every program code a confirmed succession joins to the given codes
#'
#' @param codes Program codes.
#' @param successions from_code, to_code, effective_term: the confirmed whole
#'   program successions (default `program_successions`, from
#'   code_history.csv).
#' @return Character vector: `codes` and every code a chain of successions
#'   joins to one of them, in either direction (LIBA gives LIBA and LAIS).
program_succession_family <- function(codes, successions = program_successions) {
  .population_need_successions(successions)
  family <- unique(as.character(codes))
  repeat {
    linked <- c(successions$to_code[successions$from_code %in% family],
                successions$from_code[successions$to_code %in% family])
    grown <- union(family, linked)
    if (length(grown) == length(family)) return(family)
    family <- grown
  }
}


#' The program each code is: the last code of its succession chain
#'
#' A renamed program is one program across its codes, named by the newest
#' (LIBA and LAIS are LAIS). A code no succession names is its own id.
#'
#' @param codes Program codes.
#' @param successions As for program_succession_family().
#' @return Character vector parallel to `codes`.
program_id_of <- function(codes, successions = program_successions) {
  .population_need_successions(successions)
  succ <- stats::setNames(as.character(successions$to_code), successions$from_code)
  current <- as.character(codes)
  # validate_mapping_files() refuses a split or a cycle; one step more than
  # the rows could chain is a cycle it missed.
  for (i in seq_len(nrow(successions) + 1L)) {
    nxt <- unname(succ[current])
    moving <- !is.na(nxt)
    if (!any(moving)) return(current)
    current[moving] <- nxt[moving]
  }
  stop("[population.R] program_successions form a cycle; validate_mapping_files() should have refused it")
}


#' Picker choices for program codes: one per program, renames joined
#'
#' The one way a page offers programs to pick (Pathways' Majors, Headcount's
#' Major and Minor). Each choice is valued by its program id (program_id_of())
#' and labelled with programs.csv's name and every code it covers, so a
#' renamed program is one choice ("Liberal Arts & Integrative Studies (LAIS,
#' LIBA)") and two programs sharing a Banner name are two ("Architecture
#' (ARCH)", "Architecture (ARCT)"). A code programs.csv lacks is offered as
#' "[no programs.csv row] (CODE)", never named after itself.
#'
#' With `profile`, each label also says what tells programs of one name apart
#' (ISSUES: eight Nursing codes read alike): every degree its students
#' declared, most common first; their home campuses, most common first, as
#' codes where campuses.csv names the value; and the years it was declared.
#' "Nursing (NURS) · BS in Nursing, Master of Science in Nursing · ABQ, TA ·
#' 2018–2026". Descriptive only: the choice's value is the same program id.
#'
#' @param codes Program codes (NA dropped, repeats ignored).
#' @param dims The dimension tables (build_cedar_dims()).
#' @param successions As for program_succession_family().
#' @param profile Optional declaration rows (cedar_programs): `major_code`,
#'   `degree`, `student_campus`, `term`. A program's rows are those of every
#'   code its choice covers.
#' @return Named character vector, label to program id, in label order.
program_choices <- function(codes, dims, successions = program_successions, profile = NULL) {
  validate_cedar_dims(dims)
  codes <- sort(unique(stats::na.omit(as.character(codes))))
  codes <- codes[nzchar(codes)]
  if (length(codes) == 0) return(stats::setNames(character(0), character(0)))
  by_id <- split(codes, program_id_of(codes, successions))
  ids <- names(by_id)
  id_names <- name_program_codes(ids, dims)
  in_file <- ids %in% dims$programs$program_code
  if (!is.null(profile)) {
    missing <- setdiff(c("major_code", "degree", "student_campus", "term"), names(profile))
    if (length(missing)) {
      stop("[population.R] program_choices(): profile lacks ", paste(missing, collapse = ", "), call. = FALSE)
    }
    # Each program's declaration rows, found in one pass over the table: every
    # code belongs to one program, so its rows are that program's. Looking the
    # rows up once per program instead read the whole table once per program,
    # which was 3.4 of the 7.6 seconds a session spent starting (ISSUES I80).
    profile_code <- as.character(profile$major_code)
    in_scope <- which(profile_code %in% codes)
    code_program <- stats::setNames(rep(ids, lengths(by_id)), unlist(by_id, use.names = FALSE))
    profile_rows <- split(in_scope, unname(code_program[profile_code[in_scope]]))
    profile <- profile[, c("degree", "student_campus", "term"), drop = FALSE]
  }
  labels <- vapply(seq_along(ids), function(i) {
    id <- ids[i]
    covered <- c(id, setdiff(sort(by_id[[id]]), id))
    name <- if (in_file[i]) id_names[[id]] else "[no programs.csv row]"
    label <- paste0(name, " (", paste(covered, collapse = ", "), ")")
    if (is.null(profile)) return(label)
    rows <- profile_rows[[id]]
    if (length(rows) == 0L) return(label)
    paste(c(label, .program_profile_parts(profile[rows, , drop = FALSE])), collapse = " \u00b7 ")
  }, character(1))
  stats::setNames(ids, labels)[order(labels)]
}

# What tells one program's declarations apart: its degrees and home campuses,
# most common first, and the years declared. Parts with nothing known are left
# out, never guessed.
.program_profile_parts <- function(rows) {
  by_count <- function(x) {
    x <- as.character(x)
    x <- x[!is.na(x) & nzchar(x)]
    if (length(x) == 0L) return(character(0))
    counts <- table(x)
    names(counts)[order(-as.integer(counts), names(counts))]
  }
  degrees <- by_count(rows$degree)
  campuses <- by_count(rows$student_campus)
  coded <- cedar_campus_code_from_source(campuses)
  campuses <- unique(ifelse(is.na(coded), campuses, coded))
  years <- range(as.integer(rows$term) %/% 100L)
  parts <- character(0)
  if (length(degrees)) parts <- c(parts, paste(degrees, collapse = ", "))
  if (length(campuses)) parts <- c(parts, paste(campuses, collapse = ", "))
  c(parts, if (years[1] == years[2]) as.character(years[1]) else paste0(years[1], "\u2013", years[2]))
}


.population_need_successions <- function(successions) {
  missing <- setdiff(c("from_code", "to_code", "effective_term"), names(successions))
  if (!is.data.frame(successions) || length(missing))
    stop("[population.R] program successions need from_code, to_code and effective_term",
         call. = FALSE)
  if (anyDuplicated(successions$from_code))
    stop("[population.R] a program code succeeds to more than one code", call. = FALSE)
  invisible(successions)
}


#' Resolve a named population group to Banner major codes
#'
#' The group's declared codes (population_groups.csv), every code a confirmed
#' rename joins them to (code_history.csv), and the pre-majors that lead to
#' any of them (programs.csv leads_to). Codes only: a Banner name joins
#' nothing (ISSUES I62, M56).
#'
#' @param group_id Name of an entry in CEDAR_POPULATION_GROUPS.
#' @param include_pre_majors "lump" (default, declared + pre-major),
#'   "majors_only", or "pre_only". Matches build_population()'s vocabulary.
#' @param successions,leads_to Override program_successions and
#'   premajor_leads_to (tests and what-ifs).
#' @return Character vector of major codes, sorted.
population_group_major_codes <- function(group_id, include_pre_majors = "lump",
                                         successions = program_successions,
                                         leads_to = premajor_leads_to) {
  if (!include_pre_majors %in% c("lump", "majors_only", "pre_only")) {
    stop("[population.R] include_pre_majors must be lump, majors_only, or pre_only.",
         call. = FALSE)
  }
  declared <- program_succession_family(population_group_codes(group_id), successions)
  pre <- setdiff(pre_major_codes_leading_to(declared, leads_to), declared)
  sort(unique(switch(include_pre_majors,
    lump = c(declared, pre), majors_only = declared, pre_only = pre)))
}


#' Audit a named population group against real program data
#'
#' A group lists codes, so what drifts is Banner adding a code the file does not
#' list. The audit reports what the group resolved to, the codes no student
#' holds, and the near misses a code list is most likely to leave out: a
#' declared code sharing a group program's Banner name (a new online or
#' campus variant), and a pre-major with no leads_to whose name matches a group
#' program's once case, punctuation and a plural are set aside ("Radiologic
#' Science" beside "Radiologic Sciences"). Each is for a person to decide in
#' the file; none joins the group.
#'
#' @param group_id Name of an entry in CEDAR_POPULATION_GROUPS.
#' @param programs cedar_programs (major_code, program_name, is_pre_major).
#' @param successions,leads_to As for population_group_major_codes().
#' @return A list: `codes`, `unheld_codes`, `near_miss` (program_name,
#'   major_code, is_pre_major).
population_group_audit <- function(group_id, programs,
                                   successions = program_successions,
                                   leads_to = premajor_leads_to) {
  required <- c("major_code", "program_name", "is_pre_major")
  missing <- setdiff(required, names(programs))
  if (length(missing) > 0) {
    stop("[population.R] programs is missing: ", paste(missing, collapse = ", "),
         call. = FALSE)
  }
  codes <- population_group_major_codes(group_id, "lump", successions, leads_to)

  present <- programs %>%
    filter(!is.na(major_code), !is.na(program_name), nzchar(program_name)) %>%
    distinct(program_name, major_code, is_pre_major)

  normalize <- function(x) {
    x <- trimws(gsub("\\s+", " ", gsub("[^a-z0-9]+", " ", tolower(x))))
    sub("s$", "", x)
  }
  group_names <- unique(present$program_name[present$major_code %in% codes])

  list(
    codes = codes,
    unheld_codes = sort(setdiff(codes, present$major_code)),
    near_miss = present %>%
      filter(!major_code %in% codes,
             (!is_pre_major & program_name %in% group_names) |
               (is_pre_major & !major_code %in% names(leads_to)[!is.na(leads_to)] &
                  normalize(program_name) %in% normalize(group_names))) %>%
      arrange(program_name, major_code)
  )
}


# ---------------------------------------------------------------------------
# Registry annotations for a built population
# ---------------------------------------------------------------------------

#' Semantic annotations that apply to a population
#'
#' Looks up CEDAR_DATA_SEMANTICS (R/lists/data_semantics.R) for the programs this
#' population was built from and the terms it actually spans. A population whose
#' major code recorded intent rather than admission reads as heavy attrition, and
#' the reader has no way to know that from the outcome mix alone.
#'
#' Terms come from the population's own program rows rather than from a declared
#' range, so an annotation bounded at a term stops applying once the population
#' no longer reaches into it.
#'
#' @param population A population tibble from build_population(); its
#'   attr(, "focal_programs") names the codes in scope.
#'   Without it (a demographic population has none) every program the
#'   population's students held is in scope.
#' @param programs cedar_programs.
#' @return A list of registry entries, empty when nothing applies.
population_data_notes <- function(population, programs) {
  if (is.null(population) || nrow(population) == 0) return(list())
  required <- c("major_code", "program_name", "student_id", "term")
  missing <- setdiff(required, names(programs))
  if (length(missing) > 0) {
    stop("[population.R] programs is missing: ", paste(missing, collapse = ", "),
         call. = FALSE)
  }

  scoped <- programs %>% filter(student_id %in% population$student_id)
  focal_codes <- attr(population, "focal_programs")$codes$program_code
  if (length(focal_codes) > 0) {
    scoped <- scoped %>% filter(major_code %in% focal_codes)
  }
  if (nrow(scoped) == 0) return(list())

  cedar_semantic_notes(
    "cedar_programs",
    values = unique(stats::na.omit(scoped$major_code)),
    terms = unique(stats::na.omit(scoped$term))
  )
}
