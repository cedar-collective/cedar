# health-whatif.R
#
# Health Enrollment What-If Analysis
#
# Answers the question: if we increase the number of students in selected health
# programs by X%, which courses will see additional demand, how much, and when?
#
# ── HOW THE NUMBERS ARE CALCULATED ───────────────────────────────────────────
#
# The core insight is that each program has a stable pattern of *when* its
# students take each course. A nursing student has, say, a 14% chance of
# taking BIOL 1140 in their first year. If we add 100 nursing students, we
# expect roughly 14 more BIOL 1140 enrollments in year-1 courses.
#
# This rate is computed from historical data: across all nursing students in
# the baseline period, what fraction took BIOL 1140 when they had 0–30
# credits earned? That fraction is the "course-taking rate." It is computed
# separately for fall and spring because course offerings differ by semester.
#
# To project forward in time, we map credit bands onto calendar semesters
# starting from the selected start term:
#
#   Credit band 1 (0–30 credits, year 1)  → fall of start year
#   Credit band 1 (0–30 credits, year 1)  → spring of start year + 1
#   Credit band 2 (31–60 credits, year 2) → fall of start year + 1
#   ...
#
# The model is cross-sectional: the same flat delta appears in every projected
# semester. No cohort accumulation across years.
#
# ── KEY TERMS ────────────────────────────────────────────────────────────────
#
#   course-taking rate   — fraction of program students at a given credit level
#                          who enroll in a course during a given term type
#                          (e.g. 0.137 = 13.7% of nursing students take BIOL 1140
#                          in their first fall)
#
#   credit band          — a 30-credit window grouping students by academic
#                          progress. Band 1 = 0–30 credits (year 1), Band 2 =
#                          31–60 credits (year 2), etc. Earned credits (not
#                          semesters) are used so that transfer students are
#                          placed correctly regardless of when they enrolled.
#
#   delta students       — the additional students projected for a course in a
#                          given calendar semester: sum across all programs of
#                          (additional_students_in_program × course-taking rate)
#
#   sections fraction    — delta_students / avg_section_size. A value of 1.5
#                          means the additional demand equals 1.5 average sections.
#                          The UI flags this and colors cells by threshold.
#
# ── TRACEABILITY ─────────────────────────────────────────────────────────────
#
# Every number in the output matrix can be traced back to:
#   1. get_health_course_rates()  — where course-taking rates come from
#   2. get_section_size_lookup()  — where section sizes come from
#   3. project_health_increase()  — the projection arithmetic (see inline comments)
#
# All three functions are independently callable from the R console for
# spot-checking. See "RStudio Exploration" examples below.
#
# ── DEPENDENCIES ─────────────────────────────────────────────────────────────
#
# Calls:
#   get_course_timing()    — from cones/pathway.R; computes course-taking rates
#   build_population()     — from branches/population.R; defines the student cohort
#   STATUS_REGISTERED      — from lists/status_codes.R
#
# ── RStudio Exploration ───────────────────────────────────────────────────────
#
# library(qs2); library(dplyr)
# cedar_programs <- qs_read("data/cedar_programs.qs")
# cedar_students <- qs_read("data/cedar_students.qs")
# cedar_sections <- qs_read("data/cedar_sections.qs")
# source("R/trunk/load-funcs.R"); load_funcs(".")
#
# # Step 1: build the course-taking rate table for nursing
# rates <- get_health_course_rates(
#   programs    = cedar_programs,
#   students    = cedar_students,
#   program_names = c("Nursing"),
#   n_baseline_terms = 6   # use last 6 fall + 6 spring terms
# )
# # Inspect: what fraction of nursing students take BIOL 1140 in year 1, fall?
# rates[rates$subject_course == "BIOL 1140" & rates$credit_band == 1 & rates$term_type == "fall", ]
#
# # Step 2: build section size lookup
# sizes <- get_section_size_lookup(cedar_sections, n_baseline_falls = 3)
# sizes["BIOL 1140"]  # average enrolled per section
#
# # Step 3: project a 10% increase in nursing starting fall 2026
# proj <- project_health_increase(
#   rates       = rates,
#   sizes       = sizes,
#   start_term  = 202680,
#   delta_pct   = 10,
#   n_years     = 4,
#   goal        = "enrollments",
#   attrition   = 0,
#   threshold   = 0.85
# )
# # The matrix: rows = courses, cols = calendar semesters
# head(proj$matrix_long)
# proj$matrix_wide


# =============================================================================
# get_health_course_rates()
# =============================================================================

#' Build Cross-Sectional Course-Taking Rate Table for Health Programs
#'
#' Computes two weighted average course-taking rates per (program, course, term_type):
#'
#'   rate            — weighted by the steady-state band distribution (fraction of
#'                     all enrolled student-term observations at each band). Correct
#'                     assumption for "what does the existing enrolled population need?"
#'
#'   entry_rate      — weighted by the entry band distribution (credit band at first
#'                     appearance in the program, averaged across all new entrants in
#'                     the baseline window). Correct assumption for "what will additional
#'                     new students need?" — naturally captures the mix of true freshmen,
#'                     transfer students, and program switchers without a transfer flag.
#'
#' Both rates use the same per-band course-taking rates; only the band weights differ.
#' Attrition is already implicit in both: rates are computed from students who were
#' actually registered, so students who left simply stopped contributing observations.
#'
#' No cohort progression is modeled. The assumption is that the historical band
#' distribution of new entrants is stable and representative of future new entrants.
#'
#' @param programs    Data frame. cedar_programs.
#' @param students    Data frame. cedar_students.
#' @param program_names Character vector. Program names to include.
#' @param n_baseline_terms Integer. Historical fall and spring terms to use.
#'   Default: 6 (≈ 3 years each).
#' @param min_n Integer. Minimum student-term observations at a credit band
#'   for a band-level rate to be included. Default: 10.
#' @param max_term Integer or NULL. If set, restrict to terms <= max_term
#'   (hindcast mode).
#'
#' @return Data frame with columns: program_name, subject_course, subject_code,
#'   course_title, term_type, rate (steady-state weighted), entry_rate (entry-band
#'   weighted), n_students, n_eligible, cohort_size. Attribute "band_rates"
#'   contains the per-band detail for modal breakdowns. Attribute "entry_band_dist"
#'   contains the entry band distribution per (program, term_type) for audit.
#'
#' @export
get_health_course_rates <- function(programs, students, program_names,
                                    n_baseline_terms = 6L, min_n = 10L,
                                    max_term = NULL) {

  if (!is.null(max_term)) {
    programs <- programs %>% filter(term <= max_term)
    students <- students %>% filter(term <= max_term)
    message("[health-whatif.R] Hindcast: restricting to terms ≤ ", max_term)
  }

  message("[health-whatif.R] Building cross-sectional course rates for ",
          length(program_names), " program(s): ",
          paste(program_names, collapse = ", "))

  # ── Baseline terms ─────────────────────────────────────────────────────────
  all_terms     <- sort(unique(programs$term))
  fall_terms    <- tail(all_terms[grepl("80$", as.character(all_terms))], n_baseline_terms)
  spring_terms  <- tail(all_terms[grepl("10$", as.character(all_terms))], n_baseline_terms)
  baseline_terms <- c(fall_terms, spring_terms)

  message("[health-whatif.R] Baseline falls:   ", paste(fall_terms,   collapse = ", "))
  message("[health-whatif.R] Baseline springs: ", paste(spring_terms, collapse = ", "))

  # ── Program snapshots ──────────────────────────────────────────────────────
  # One row per (student, program, term) for selected programs in baseline.
  # Includes both majors and pre-majors. credit_band from overall_credits_earned
  # at time of enrollment, so each row correctly reflects that term's credit level.
  prog_snap <- programs %>%
    filter(program_name %in% program_names, term %in% baseline_terms) %>%
    mutate(
      term_type   = if_else(grepl("80$", as.character(term)), "fall", "spring"),
      credit_band = dplyr::case_when(
        overall_credits_earned <  31 ~ 1L,
        overall_credits_earned <  61 ~ 2L,
        overall_credits_earned <  91 ~ 3L,
        overall_credits_earned < 121 ~ 4L,
        TRUE                         ~ 5L
      )
    ) %>%
    # One row per student × program × term (deduplicates major/pre-major rows)
    distinct(student_id, program_name, term, term_type, credit_band)

  # ── Band distribution ──────────────────────────────────────────────────────
  # Steady-state distribution: fraction of student-term observations at each
  # credit band per (program, term_type). Using student-terms (not distinct
  # students) correctly weights bands by how much time students spend there.
  # E.g., if most students spend 2 terms at band 1 and 1 at band 2, band 1
  # gets roughly twice the weight.
  band_dist <- prog_snap %>%
    count(program_name, term_type, credit_band, name = "n_obs") %>%
    group_by(program_name, term_type) %>%
    mutate(band_frac = n_obs / sum(n_obs)) %>%
    ungroup() %>%
    filter(band_frac > 0) %>%
    select(program_name, term_type, credit_band, band_frac)

  message("[health-whatif.R] Band distribution computed.")

  # ── Course enrollments ─────────────────────────────────────────────────────
  # Registered enrollments in baseline terms for program students.
  all_pop_ids <- unique(prog_snap$student_id)

  # Join on student_id + term only (not term_type) because cedar_students$term_type
  # may differ in casing or value from the "fall"/"spring" we derive from the term
  # code in prog_snap. Since baseline_terms contains only fall and spring terms,
  # term already uniquely determines term_type; prog_snap's value is authoritative.
  stu_courses <- students %>%
    filter(student_id %in% all_pop_ids,
           registration_status_code %in% STATUS_REGISTERED,
           term %in% baseline_terms) %>%
    select(student_id, term, subject_course, subject_code, course_title)

  # Each row = one student taking one course in one term while in one program.
  # (A student in two selected programs appears once per program.)
  prog_courses <- prog_snap %>%
    inner_join(stu_courses, by = c("student_id", "term"))

  # ── Eligible counts ────────────────────────────────────────────────────────
  # Student-term observations per (program, credit_band, term_type).
  # This is the denominator: how many student-semester slots were at this band.
  eligible <- prog_snap %>%
    count(program_name, credit_band, term_type, name = "n_eligible")

  # ── Taker counts ──────────────────────────────────────────────────────────
  # Student-term-course observations per (program, course, credit_band, term_type).
  # Numerator: of all student-semester slots at band B, how many took course C?
  takers <- prog_courses %>%
    count(program_name, subject_course, subject_code, course_title,
          credit_band, term_type, name = "n_students")

  # ── Band-level course rates ────────────────────────────────────────────────
  # rate = takers / eligible for each (program, course, band, term_type).
  # Filtered to bands with at least min_n eligible observations (for reliability).
  band_rates <- takers %>%
    left_join(eligible, by = c("program_name", "credit_band", "term_type")) %>%
    filter(!is.na(n_eligible), n_eligible >= min_n) %>%
    mutate(band_rate = n_students / n_eligible) %>%
    filter(band_rate > 0) %>%
    left_join(band_dist, by = c("program_name", "term_type", "credit_band")) %>%
    filter(!is.na(band_frac))

  # ── Weighted average rate per (program, course, term_type) ─────────────────
  # weighted_rate = sum over bands of (band_frac × band_rate)
  # This is the expected fraction of program students (in any term) taking
  # course C — the right multiplier for "additional students → additional demand."
  weighted_rates <- band_rates %>%
    group_by(program_name, subject_course, subject_code, course_title, term_type) %>%
    summarise(
      rate       = sum(band_frac * band_rate, na.rm = TRUE),
      n_students = sum(n_students),
      n_eligible = sum(n_eligible),
      .groups    = "drop"
    ) %>%
    filter(rate > 0)

  # ── First appearance per (student, program) ───────────────────────────────
  # Needed by both entry_band_dist (below) and cohort_size_tbl (further below).
  # Computed here — before either consumer — to avoid a forward-reference error.
  pop_ids_by_prog <- prog_snap %>%
    group_by(program_name) %>%
    summarise(pop_ids = list(unique(student_id)), .groups = "drop")

  first_terms_all <- programs %>%
    filter(program_name %in% program_names, program_type == "Major") %>%
    semi_join(pop_ids_by_prog %>% select(program_name), by = "program_name") %>%
    group_by(student_id, program_name) %>%
    summarise(first_term = min(term), .groups = "drop")

  # ── Entry band distribution ────────────────────────────────────────────────
  # Credit band at first appearance per (student, program) in baseline terms.
  # "First appearance" is min(term) across ALL history (not just baseline) so
  # students who entered before the baseline window are excluded — we only know
  # their entry band if their first term falls within baseline_terms.
  # This naturally captures: true freshmen (band 1), CC transfers (band 2),
  # program-switchers from within UNM (band 2-4), without any transfer flag.
  entry_band_dist <- first_terms_all %>%
    filter(first_term %in% baseline_terms) %>%
    left_join(
      prog_snap %>% select(student_id, program_name, term, term_type, credit_band),
      by = c("student_id", "program_name", "first_term" = "term")
    ) %>%
    filter(!is.na(credit_band), !is.na(term_type)) %>%
    count(program_name, term_type, credit_band, name = "n_entrants") %>%
    group_by(program_name, term_type) %>%
    mutate(entry_band_frac = n_entrants / sum(n_entrants)) %>%
    ungroup()

  message("[health-whatif.R] Entry band distribution (fall entrants):")
  entry_band_dist %>%
    filter(term_type == "fall") %>%
    arrange(program_name, credit_band) %>%
    purrr::pwalk(function(program_name, credit_band, n_entrants, entry_band_frac, ...) {
      message("  ", program_name, " band ", credit_band, ": ",
              round(entry_band_frac * 100), "% (n=", n_entrants, ")")
    })

  # ── Entry-weighted rates per (program, course, term_type) ──────────────────
  # Same band-level rates as the steady-state model; only the weights differ.
  # entry_rate answers: "of additional new students distributed as historical
  # entrants, what fraction will take this course in this semester type?"
  entry_weighted_rates <- band_rates %>%
    left_join(entry_band_dist %>% select(program_name, term_type, credit_band, entry_band_frac),
              by = c("program_name", "term_type", "credit_band")) %>%
    filter(!is.na(entry_band_frac)) %>%
    group_by(program_name, subject_course, subject_code, course_title, term_type) %>%
    summarise(
      entry_rate = sum(entry_band_frac * band_rate, na.rm = TRUE),
      .groups    = "drop"
    ) %>%
    filter(entry_rate > 0)

  # ── Headcount and cohort size per program ─────────────────────────────────
  # avg_headcount = average total students enrolled per term in the baseline.
  #   This is the right multiplier for the weighted rate: rate was computed from
  #   ALL enrolled students, so delta = avg_headcount × delta_pct/100 × rate.
  # cohort_size   = average NEW students entering per term (kept for reference).
  # ── Average enrolled headcount per (program, term_type) ─────────────────────
  # Count distinct students per (program, term_type, term), then average across
  # terms. Done as a single group_by — avoids one filter pass per program.
  avg_headcount_tbl <- prog_snap %>%
    group_by(program_name, term_type, term) %>%
    summarise(n = n_distinct(student_id), .groups = "drop") %>%
    group_by(program_name, term_type) %>%
    summarise(avg_headcount = mean(n), .groups = "drop")

  # ── Average new entrants per (program, term_type) ────────────────────────────
  # first_terms_all already computed above (before entry_band_dist).
  # Count how many first-terms fall in each baseline fall/spring window.
  cohort_size_tbl <- bind_rows(
    first_terms_all %>%
      filter(first_term %in% fall_terms) %>%
      count(program_name, first_term, name = "n") %>%
      group_by(program_name) %>%
      summarise(cohort_size = mean(n), .groups = "drop") %>%
      mutate(term_type = "fall"),
    first_terms_all %>%
      filter(first_term %in% spring_terms) %>%
      count(program_name, first_term, name = "n") %>%
      group_by(program_name) %>%
      summarise(cohort_size = mean(n), .groups = "drop") %>%
      mutate(term_type = "spring")
  )

  prog_sizes <- avg_headcount_tbl %>%
    left_join(cohort_size_tbl, by = c("program_name", "term_type")) %>%
    mutate(cohort_size = coalesce(cohort_size, 0))

  message("[health-whatif.R] Program sizes (avg fall headcount):")
  prog_sizes %>%
    filter(term_type == "fall") %>%
    arrange(desc(avg_headcount)) %>%
    purrr::pwalk(function(program_name, avg_headcount, cohort_size, ...) {
      message("  ", program_name, ": enrolled = ", round(avg_headcount),
              "  new admits/fall = ", round(cohort_size))
    })

  # ── Assemble final result ──────────────────────────────────────────────────
  # Left-join entry_rate: courses with no entry-band data (program too new, or
  # all entrants pre-date the baseline window) get entry_rate = NA and fall back
  # to steady-state rate in project_health_increase().
  result <- weighted_rates %>%
    left_join(entry_weighted_rates %>% select(program_name, subject_course,
                                              term_type, entry_rate),
              by = c("program_name", "subject_course", "term_type")) %>%
    inner_join(prog_sizes, by = c("program_name", "term_type")) %>%
    filter(avg_headcount >= 1)

  # Attach band-level rates as attribute for modal breakdowns in project_health_increase()
  attr(result, "band_rates") <- band_rates %>%
    select(program_name, subject_course, subject_code, course_title,
           term_type, credit_band, band_frac, band_rate, n_students, n_eligible)

  # Attach entry band distribution for audit trail in the module
  attr(result, "entry_band_dist") <- entry_band_dist

  message("[health-whatif.R] Cross-sectional rate table: ",
          format(nrow(result), big.mark = ","), " rows, ",
          n_distinct(result$subject_course), " unique courses, ",
          n_distinct(result$program_name), " programs.")

  result
}


# =============================================================================
# get_section_size_lookup()
# =============================================================================

#' Average Section Enrollment Lookup by Course
#'
#' For each course, computes the average number of students enrolled per section
#' across recent fall terms. This is used as the denominator when converting
#' "additional students" into "additional sections needed."
#'
#' We use `enrolled` (actual enrollment) not `capacity` (administrative maximum).
#' Capacity values include outliers like 99999 from crosslisted section shells.
#' Enrolled counts reflect the real operating size of sections.
#'
#' We exclude crosslist partner sections (crosslist_role == "partner") to avoid
#' double-counting enrollments that are already captured in the primary section.
#'
#' @param sections Data frame. cedar_sections.
#' @param n_baseline_falls Integer. Number of recent fall terms to average over.
#'   Default: 3.
#'
#' @return Named numeric vector: names are subject_course (e.g. "BIOL 1140"),
#'   values are average enrolled per section. Courses with no sections or zero
#'   average enrollment are excluded.
#'
#' @export
get_section_size_lookup <- function(sections, n_baseline_falls = 3L,
                                     min_section_size = 5L) {

  # Use the most recent N fall terms available in cedar_sections
  fall_terms <- sections %>%
    filter(term_type == "fall") %>%
    pull(term) %>%
    unique() %>%
    sort() %>%
    tail(n_baseline_falls)

  message("[health-whatif.R] Section size baseline falls: ", paste(fall_terms, collapse = ", "))

  sizes <- sections %>%
    filter(
      term_type       == "fall",
      term            %in% fall_terms,
      # Exclude crosslist partners — their enrolled count duplicates the primary.
      # Use is.na() OR != "partner" because non-crosslisted sections have NA role.
      (is.na(crosslist_role) | crosslist_role != "partner"),
      enrolled         > 0
    ) %>%
    group_by(subject_course) %>%
    summarise(
      avg_section_size = mean(enrolled, na.rm = TRUE),
      n_sections       = n(),          # how many section-terms this is based on
      .groups          = "drop"
    ) %>%
    # Exclude courses with tiny average sections — these are thesis, directed
    # research, or individual supervision sections (e.g. avg 1–4 students).
    # sections_fraction is meaningless for courses that don't scale as classrooms.
    filter(avg_section_size >= min_section_size)

  result <- setNames(sizes$avg_section_size, sizes$subject_course)

  message("[health-whatif.R] Section size lookup: ", length(result),
          " courses (min section size >= ", min_section_size, ").")
  result
}


# =============================================================================
# project_health_increase()
# =============================================================================

#' Project Course Enrollment Impact of a Health Program Increase
#'
#' Cross-sectional model: for each future semester, the additional demand for
#' a course = sum over programs of (additional_students × weighted_rate).
#' weighted_rate comes from get_health_course_rates() and already captures
#' the steady-state band distribution. No cohort progression is tracked.
#'
#' ── HOW THE PROJECTION WORKS ─────────────────────────────────────────────────
#'
#' Each future semester is independent. No cohort tracking, no progression.
#'
#'   delta(course, semester) = sum over programs of:
#'     additional_students × effective_rate
#'
#' where:
#'   additional_students = avg_headcount × delta_pct/100 × attrition_scale
#'   effective_rate      = entry_rate (credit-band distribution of new program entrants)
#'                         falls back to steady-state rate when no entry data exists
#'   entry_rate          = band-level rates weighted by the historical credit-band
#'                         distribution at first program appearance — captures the
#'                         real mix of freshmen, CC transfers, and program-switchers
#'
#' Every projected semester is independent. The same flat delta appears in
#' every fall and spring across the n_years window. No cohort accumulation.
#'
#' ─────────────────────────────────────────────────────────────────────────────
#'
#' @param rates      Data frame. Output of get_health_course_rates().
#' @param sizes      Named numeric vector. Output of get_section_size_lookup().
#' @param start_term Integer. First fall term (Banner format, e.g. 202680).
#' @param delta_pct  Numeric. Percent increase in new admits (e.g. 10 = 10% more).
#' @param n_years    Integer. Years to project. Default: 4.
#' @param goal       "enrollments" or "graduates". Default: "enrollments".
#' @param attrition  Numeric 0–1. Used only when goal = "graduates". Default: 0.20.
#' @param threshold       Numeric 0–1. Sections fraction flag threshold. Default: 0.85.
#'
#' @return List: matrix_long, matrix_wide, assumptions.
#'
#' @export
project_health_increase <- function(rates, sizes,
                                    start_term, delta_pct, n_years = 4L,
                                    goal            = "enrollments",
                                    attrition       = 0.20,
                                    threshold       = 0.85,
                                    per_prog_override = NULL) {

  if (!grepl("80$", as.character(start_term))) {
    stop("[health-whatif.R] start_term must be a fall term (ending in '80'). Got: ",
         start_term)
  }

  start_year <- as.integer(substr(as.character(start_term), 1, 4))

  # ── Calendar semesters ────────────────────────────────────────────────────
  # Cross-sectional steady-state model: every projected semester uses the same
  # delta (additional_base × rate). There is no compounding year over year —
  # the delta_pct increase is a flat shift in steady-state headcount, not a
  # growing one. compound_factor is fixed at 1.0 for all years.
  calendar_semesters <- purrr::map_dfr(seq_len(n_years), function(i) {
    year_fall   <- start_year + i - 1L
    year_spring <- start_year + i
    bind_rows(
      tibble(calendar_term  = as.integer(paste0(year_fall,   "80")),
             term_label     = paste("Fall",   year_fall),
             term_type      = "fall",
             compound_factor = 1.0),
      tibble(calendar_term  = as.integer(paste0(year_spring, "10")),
             term_label     = paste("Spring", year_spring),
             term_type      = "spring",
             compound_factor = 1.0)
    )
  })

  # ── Attrition scalar ───────────────────────────────────────────────────────
  attrition_scale <- if (goal == "graduates" && attrition > 0) 1 / (1 - attrition) else 1.0

  message("[health-whatif.R] Projection (cross-sectional, no cohort tracking): ",
          delta_pct, "% ", goal, " goal, attrition_scale = ",
          round(attrition_scale, 3))

  # ── Additional students per (program, term_type) ──────────────────────────
  # Normal mode: additional_base = avg_headcount × delta_pct/100 × attrition_scale.
  # Hindcast override: use per-program observed headcount change (actual_delta_n)
  # so the projection reflects each program's real growth independently.
  # Spring additional_base scales from fall by the spring/fall headcount ratio.
  prog_additional <- if (!is.null(per_prog_override)) {
    # Fall basis: use each program's observed absolute headcount change.
    # Spring basis: apply the same proportional change (actual_delta_n / baseline_hc)
    # to spring's avg_headcount.
    fall_basis <- rates %>%
      distinct(program_name, avg_headcount, cohort_size) %>%
      filter(program_name %in% rates$program_name[rates$term_type == "fall"]) %>%
      left_join(
        per_prog_override %>% select(program_name, actual_delta_n, baseline_hc),
        by = "program_name"
      ) %>%
      mutate(delta_frac = if_else(baseline_hc > 0, actual_delta_n / baseline_hc, 0))

    rates %>%
      distinct(program_name, term_type, avg_headcount, cohort_size) %>%
      left_join(fall_basis %>% select(program_name, delta_frac), by = "program_name") %>%
      mutate(
        additional_base = coalesce(delta_frac, 0) * avg_headcount * attrition_scale
      )
  } else {
    rates %>%
      distinct(program_name, term_type, avg_headcount, cohort_size) %>%
      mutate(additional_base = avg_headcount * (delta_pct / 100) * attrition_scale)
  }

  message("[health-whatif.R] Additional students per program (fall, year 1):")
  prog_additional %>%
    filter(term_type == "fall") %>%
    distinct(program_name, avg_headcount, additional_base) %>%
    arrange(desc(additional_base)) %>%
    purrr::pwalk(function(program_name, avg_headcount, additional_base, ...) {
      message("  ", program_name, ": enrolled = ", round(avg_headcount),
              " → +", round(additional_base, 1), " additional")
    })

  # ── Select effective rate ──────────────────────────────────────────────────
  # Always use entry_rate (credit-band distribution of new program entrants).
  # Falls back to steady-state rate when entry_rate is NA — this happens when
  # a program is too new or all entrants pre-date the baseline window.
  rate_tbl <- rates %>%
    select(program_name, subject_course, subject_code, course_title,
           term_type, rate, entry_rate) %>%
    mutate(effective_rate = coalesce(entry_rate, rate))

  n_entry <- sum(!is.na(rates$entry_rate))
  n_ss    <- sum(is.na(rates$entry_rate))
  message("[health-whatif.R] Band weighting: entry distribution (",
          n_entry, " rows); steady-state fallback (", n_ss, " rows with no entry data).")

  # ── Delta per (semester, program, course) ─────────────────────────────────
  # For each semester: delta = additional_base × compound_factor × effective_rate.
  # Each semester is independent — no accumulation, no progression.
  delta_long <- calendar_semesters %>%
    left_join(
      rate_tbl %>% select(program_name, subject_course, subject_code, course_title,
                          term_type, rate, entry_rate, effective_rate),
      by           = "term_type",
      relationship = "many-to-many"
    ) %>%
    left_join(
      prog_additional %>% distinct(program_name, term_type, avg_headcount,
                                   cohort_size, additional_base),
      by = c("program_name", "term_type")
    ) %>%
    filter(!is.na(effective_rate)) %>%
    mutate(
      effective_students = additional_base * compound_factor,
      delta_from_prog    = effective_students * effective_rate
    )

  # ── Aggregate per (course, semester) ──────────────────────────────────────
  delta_summary <- delta_long %>%
    group_by(subject_course, course_title, subject_code,
             calendar_term, term_label, term_type) %>%
    summarise(
      delta_students = sum(delta_from_prog, na.rm = TRUE),
      program_contributions = list(
        pick(program_name, avg_headcount, cohort_size, additional_base,
             compound_factor, effective_students, rate, entry_rate,
             effective_rate, delta_from_prog) %>%
          distinct() %>%
          arrange(desc(delta_from_prog))
      ),
      .groups = "drop"
    )

  # ── Baseline demand per (course, term_type) ────────────────────────────────
  # Expected health-student enrollment from CURRENT enrolled population, assuming
  # headcount stays at the observed baseline level (no growth, no attrition).
  # Formula: sum over programs of (avg_headcount × rate).
  # This is the answer to "what do our current students need?" — the delta above
  # is what additional NEW students would need on top of this.
  baseline_by_course <- rates %>%
    group_by(subject_course, term_type) %>%
    summarise(
      baseline_students = sum(avg_headcount * rate, na.rm = TRUE),
      .groups = "drop"
    )

  # ── Section sizes and sections_fraction ───────────────────────────────────
  matrix_long <- delta_summary %>%
    left_join(baseline_by_course, by = c("subject_course", "term_type")) %>%
    mutate(
      baseline_students = coalesce(baseline_students, 0),
      total_students    = baseline_students + delta_students,
      avg_section_size  = sizes[subject_course],
      sections_fraction = if_else(
        !is.na(avg_section_size) & avg_section_size > 0,
        delta_students / avg_section_size,
        NA_real_
      ),
      needs_flag = !is.na(sections_fraction) & sections_fraction >= threshold
    ) %>%
    arrange(calendar_term, desc(delta_students))

  # ── Wide matrix ───────────────────────────────────────────────────────────
  matrix_wide <- matrix_long %>%
    select(subject_course, course_title, term_label, sections_fraction) %>%
    tidyr::pivot_wider(names_from = term_label, values_from = sections_fraction) %>%
    mutate(
      peak_impact = pmax(!!!rlang::syms(
        setdiff(names(.), c("subject_course", "course_title"))
      ), na.rm = TRUE)
    ) %>%
    arrange(desc(peak_impact)) %>%
    select(-peak_impact)

  # ── Assumptions record ─────────────────────────────────────────────────────
  first_fall <- min(calendar_semesters$calendar_term[calendar_semesters$term_type == "fall"])
  prog_deltas <- delta_long %>%
    filter(calendar_term == first_fall) %>%
    distinct(program_name, avg_headcount, cohort_size, additional_base) %>%
    mutate(delta = round(additional_base, 1))

  assumptions <- list(
    programs        = unique(rates$program_name),
    start_term      = start_term,
    delta_pct       = delta_pct,
    goal            = goal,
    attrition       = if (goal == "graduates") attrition else 0,
    attrition_scale = round(attrition_scale, 3),
    n_years         = n_years,
    threshold       = threshold,
    model           = "cross-sectional",
    program_deltas  = prog_deltas %>%
      select(program_name, avg_headcount, cohort_size, delta) %>%
      as.list()
  )

  message("[health-whatif.R] Projection complete: ",
          n_distinct(matrix_long$subject_course), " courses × ",
          n_distinct(matrix_long$calendar_term), " semesters.")

  list(
    matrix_long = matrix_long,
    matrix_wide = matrix_wide,
    assumptions = assumptions
  )
}


# =============================================================================
# get_premajor_pipeline()
# =============================================================================

#' Pre-Major Pipeline Analysis for Health Programs
#'
#' Tracks pre-major vs. declared major headcount per program per fall term.
#' Pre-majors are students enrolled in the university who are working toward
#' admission to a competitive program. They are already taking courses and
#' driving enrollment demand — but their course-taking pattern differs from
#' admitted majors (prereqs vs. clinical/upper-division courses).
#'
#' A structural break is flagged when a program's pre-major count changes by
#' more than 200% in a single year. This indicates a programmatic change
#' (new pre-major pathway formalized, policy change, data reclassification)
#' rather than gradual growth. Structural breaks make simple linear trend
#' extrapolation unreliable and should be highlighted for planners.
#'
#' @param programs      Data frame. cedar_programs.
#' @param program_names Character vector. Program names to include.
#' @param n_trend_falls Integer. Number of recent fall terms to include.
#'   Default: 7.
#'
#' @return Named list:
#'   \describe{
#'     \item{`pipeline`}{Wide data frame: program_name, term, year,
#'       n_majors, n_premajors, total, pct_premajor. One row per
#'       (program, fall term).}
#'     \item{`structural_breaks`}{Data frame of (program_name, term, break_year)
#'       where pre-major count changed > 200% in one year.}
#'   }
#'
#' @export
get_premajor_pipeline <- function(programs, program_names, n_trend_falls = 7L) {

  all_falls <- programs %>%
    pull(term) %>% unique() %>%
    keep(~ grepl("80$", as.character(.x))) %>%
    sort()
  trend_falls <- tail(all_falls, n_trend_falls)

  pipeline <- programs %>%
    filter(program_name %in% program_names, term %in% trend_falls) %>%
    group_by(program_name, term, is_pre_major) %>%
    summarise(n = n_distinct(student_id), .groups = "drop") %>%
    mutate(
      year   = as.integer(substr(as.character(term), 1, 4)),
      status = if_else(is_pre_major, "n_premajors", "n_majors")
    ) %>%
    tidyr::pivot_wider(
      id_cols     = c(program_name, term, year),
      names_from  = status,
      values_from = n,
      values_fill = 0L
    ) %>%
    mutate(
      total        = n_majors + n_premajors,
      pct_premajor = if_else(total > 0, n_premajors / total, 0)
    ) %>%
    arrange(program_name, term)

  # Flag structural breaks: pre-major count changed > 200% in a single year
  # (≥ 5 pre-majors baseline to avoid flagging tiny programs with small swings)
  flagged <- pipeline %>%
    group_by(program_name) %>%
    mutate(
      prev_premajors  = lag(n_premajors),
      pct_chg         = if_else(
        !is.na(prev_premajors) & prev_premajors >= 5L,
        (n_premajors - prev_premajors) / prev_premajors * 100,
        NA_real_
      )
    ) %>%
    ungroup()

  structural_breaks <- flagged %>%
    filter(!is.na(pct_chg), abs(pct_chg) > 200) %>%
    select(program_name, term, break_year = year, n_premajors, prev_premajors, pct_chg)

  if (nrow(structural_breaks) > 0) {
    message("[health-whatif.R] Structural breaks in pre-major count (>200% change):")
    purrr::pwalk(structural_breaks, function(program_name, break_year, pct_chg, ...) {
      message("  ", program_name, " Fall ", break_year,
              ": ", round(pct_chg, 0), "% change in pre-major headcount")
    })
  }

  list(
    pipeline          = pipeline,
    structural_breaks = structural_breaks
  )
}


# =============================================================================
# get_health_course_trends()
# =============================================================================

#' Trend-Based Health-Student Course Enrollment Forecasting
#'
#' For each course taken by selected health programs, fits a linear trend to
#' actual health-student enrollment across recent fall terms and projects
#' forward. This is the foundational "load-bearing course" analysis: which
#' courses are growing in health-student demand, how fast, and how does that
#' compare to section capacity?
#'
#' Unlike the what-if model (which asks "what happens if we add X% more
#' students?"), this function asks "what does the actual historical data say
#' about where demand is headed?" The two approaches are complementary:
#' the trend shows the baseline trajectory; the what-if shows marginal impact.
#'
#' @param programs     Data frame. cedar_programs.
#' @param students     Data frame. cedar_students.
#' @param sections     Data frame. cedar_sections.
#' @param program_names Character vector. Program names to include.
#' @param n_trend_falls Integer. Historical fall terms to fit the trend.
#'   Default: 7. More = more stable trend; fewer = more recent.
#' @param project_falls Integer. How many future fall terms to project.
#'   Default: 4.
#'
#' @return Named list:
#'   \describe{
#'     \item{`trends`}{Data frame per course: slope, intercept, R², recent_n,
#'       avg_section_size, sections_per_year, and one projected-enrollment
#'       column per future fall year. Sorted by slope descending.}
#'     \item{`history`}{Long-format data frame: actual health-student enrollment
#'       per (subject_course, term). Use for plotting or audit.}
#'     \item{`trend_falls`}{Integer vector of fall term codes used for fitting.}
#'     \item{`proj_years`}{Integer vector of projected fall years.}
#'   }
#'
#' @export
get_health_course_trends <- function(programs, students, sections, program_names,
                                      n_trend_falls = 7L, project_falls = 4L) {

  message("[health-whatif.R] Computing health-student enrollment trends for ",
          length(program_names), " program(s).")

  # All students in selected programs
  all_pop_ids <- programs %>%
    filter(program_name %in% program_names) %>%
    pull(student_id) %>%
    unique()

  if (length(all_pop_ids) == 0) {
    message("[health-whatif.R] No students found for selected programs — returning NULL.")
    return(NULL)
  }

  # Historical fall terms for trend fitting
  all_falls <- programs %>%
    pull(term) %>% unique() %>%
    keep(~ grepl("80$", as.character(.x))) %>%
    sort()

  trend_falls <- tail(all_falls, n_trend_falls)
  last_year   <- as.integer(substr(as.character(max(trend_falls)), 1, 4))

  message("[health-whatif.R] Trend falls: ", paste(trend_falls, collapse = ", "))

  # Actual health-student enrollment per (course, fall term)
  enrollment_history <- students %>%
    filter(student_id %in% all_pop_ids,
           registration_status_code %in% STATUS_REGISTERED,
           term %in% trend_falls) %>%
    group_by(subject_course, course_title, subject_code, term) %>%
    summarise(n_health = n_distinct(student_id), .groups = "drop") %>%
    mutate(year = as.integer(substr(as.character(term), 1, 4)))

  message("[health-whatif.R] Enrollment history: ",
          format(nrow(enrollment_history), big.mark = ","),
          " course-term observations, ",
          n_distinct(enrollment_history$subject_course), " unique courses.")

  # Fit linear trend per course (need ≥ 2 fall observations)
  # Uses group_modify to call lm() once per course — avoids redundant model fits.
  trend_fits <- enrollment_history %>%
    group_by(subject_course, course_title, subject_code) %>%
    filter(n() >= 2L) %>%
    group_modify(function(data, ...) {
      fit  <- lm(n_health ~ year, data = data)
      cf   <- coef(fit)
      tibble(
        n_terms     = nrow(data),
        recent_year = max(data$year),
        recent_n    = data$n_health[which.max(data$year)],
        slope       = cf[["year"]],
        intercept   = cf[["(Intercept)"]],
        r_squared   = summary(fit)$r.squared
      )
    }) %>%
    ungroup()

  message("[health-whatif.R] Trend fits: ", nrow(trend_fits),
          " courses with ≥ 2 fall observations.")

  # Future fall years to project
  proj_years <- seq(last_year + 1L, last_year + project_falls)

  # Section size and section count from cedar_sections
  sizes <- get_section_size_lookup(sections, n_baseline_falls = 3L)

  recent_3_falls <- tail(all_falls, 3L)
  n_sections_by_course <- sections %>%
    filter(
      term_type == "fall",
      term %in% recent_3_falls,
      (is.na(crosslist_role) | crosslist_role != "partner"),
      enrolled > 0
    ) %>%
    group_by(subject_course, term) %>%
    summarise(n_sec = n_distinct(crn), .groups = "drop") %>%
    group_by(subject_course) %>%
    summarise(avg_n_sections = mean(n_sec, na.rm = TRUE), .groups = "drop")

  # Build result table: trend metrics + projected values per future year
  trends <- trend_fits %>%
    left_join(n_sections_by_course, by = "subject_course") %>%
    mutate(
      avg_section_size  = sizes[subject_course],
      sections_per_year = if_else(
        !is.na(avg_section_size) & avg_section_size > 0,
        slope / avg_section_size,
        NA_real_
      )
    )

  # Add one column per projected fall year
  for (yr in proj_years) {
    col_nm        <- paste0("proj_", yr)
    trends[[col_nm]] <- pmax(0, round(trends$intercept + trends$slope * yr, 1))
  }

  trends <- trends %>% arrange(desc(slope))

  list(
    trends      = trends,
    history     = enrollment_history,
    trend_falls = trend_falls,
    proj_years  = proj_years,
    last_year   = last_year
  )
}


# =============================================================================
# get_course_pressure()
# =============================================================================

#' Course Capacity Pressure Indicators for Health Program Cohorts
#'
#' Identifies courses at risk of becoming enrollment bottlenecks by combining
#' four independent signals, each detectable from existing data without
#' waitlist records:
#'
#' 1. **Fill rate**: sections running near or at capacity (enrolled/capacity).
#'    High fill rate = no slack to absorb demand growth. Rising fill rate =
#'    the buffer is shrinking.
#'
#' 2. **Health-student share**: health program students as a fraction of total
#'    course enrollment. High share means program growth directly drives course
#'    demand — there is no dilution from other majors.
#'
#' 3. **Take rate decline**: the fraction of program students who enroll in the
#'    course, compared between early and recent baseline terms. A declining rate
#'    at the expected credit band suggests students who need the course are not
#'    getting it and may be deferring, substituting, or giving up.
#'
#' 4. **Band drift**: the average credit band at which health students enroll in
#'    the course, compared early vs. recent. Rightward drift (students taking it
#'    later) is consistent with repeated failed attempts before finally getting
#'    a seat.
#'
#' No single signal is conclusive. The pressure score counts how many flags a
#' course trips simultaneously — 3 or 4 flags indicates a course that likely
#' warrants capacity attention.
#'
#' @param programs       Data frame. cedar_programs.
#' @param students       Data frame. cedar_students.
#' @param sections       Data frame. cedar_sections.
#' @param program_names  Character vector. Health program names to include.
#' @param n_baseline_terms Integer. Fall terms to include. Split evenly into
#'   early and recent halves for trend signals. Default: 8.
#' @param min_health_n   Integer. Minimum avg health students per term for a
#'   course to appear. Default: 10.
#'
#' @return Data frame, one row per course, sorted by n_flags descending.
#'   Columns: subject_course, course_title, avg_fill, fill_slope, flag_fill,
#'   avg_health_share, avg_health_n, flag_share, rate_early, rate_recent,
#'   rate_change_pct, flag_rate_drop, band_early, band_recent, band_drift,
#'   flag_band_drift, n_flags.
#'
#' @export
get_course_pressure <- function(programs, students, sections, program_names,
                                 n_baseline_terms = 8L, min_health_n = 10L,
                                 season = "fall", undergrad_only = TRUE) {

  season <- match.arg(season, c("fall", "spring"))
  term_suffix <- if (season == "fall") "80$" else "10$"

  message("[health-whatif.R] Computing course pressure indicators for ",
          length(program_names), " program(s), season = ", season,
          ", undergrad_only = ", undergrad_only, ".")

  all_terms      <- programs %>% pull(term) %>% unique() %>%
    keep(~ grepl(term_suffix, as.character(.x))) %>% sort()
  baseline_terms <- tail(all_terms, n_baseline_terms)
  n_half         <- max(2L, n_baseline_terms %/% 2L)
  early_falls    <- head(baseline_terms, n_half)
  recent_falls   <- tail(baseline_terms, n_half)
  baseline_falls <- baseline_terms

  message("[health-whatif.R] Pressure: early falls = ",
          paste(early_falls, collapse = ", "))
  message("[health-whatif.R] Pressure: recent falls = ",
          paste(recent_falls, collapse = ", "))

  # Apply undergrad filter to programs and students once up front.
  # cedar_programs uses "Undergraduate"; cedar_students uses "UG".
  # cedar_sections uses level %in% c("upper","lower") — applied per signal below.
  if (undergrad_only) {
    programs <- programs %>% filter(student_level == "Undergraduate")
    students <- students %>% filter(student_level == "UG")
  }

  pop_ids <- programs %>%
    filter(program_name %in% program_names) %>%
    pull(student_id) %>% unique()

  # Pre-filter students to the cohort and all baseline terms once so that
  # Signals 2, 3, and 4 can reuse this table without redundant scans.
  pop_students_baseline <- students %>%
    filter(student_id %in% pop_ids,
           registration_status_code %in% STATUS_REGISTERED,
           term %in% baseline_falls)

  # ── Signal 1: Section fill rate ──────────────────────────────────────────
  # capacity in cedar_sections is unreliable: many rows have 99999 or NA as
  # Banner sentinels for "no hard cap". Use `available` instead — Banner sets
  # this directly as (effective_cap - enrolled), so it is correct even when
  # capacity is 99999.
  #
  # fill_rate per section = enrolled / (enrolled + pmax(available, 0))
  #   pmax(available, 0) treats over-enrolled sections as 100% full.
  #   Sections with enrolled = 0 contribute 0% fill (not excluded).
  #
  # Per-course per-term: weighted average fill rate across sections, weighted
  # by enrolled count so large lecture-equivalent sections dominate correctly.
  #
  # avg_fill:  mean across baseline falls.
  # fill_slope: OLS slope — positive = sections filling up year over year.
  # Flag: avg_fill >= 0.85 OR fill_slope >= 0.01/yr.
  fill_by_term <- sections %>%
    filter(term %in% baseline_falls, term_type == season,
           is.na(crosslist_role) | crosslist_role != "partner",
           !is.na(available), enrolled > 0,
           if (undergrad_only) level %in% c("upper", "lower") else TRUE) %>%
    mutate(
      effective_cap = enrolled + pmax(available, 0L),
      section_fill  = if_else(effective_cap > 0,
                              enrolled / effective_cap,
                              NA_real_)
    ) %>%
    filter(!is.na(section_fill)) %>%
    group_by(subject_course, term) %>%
    summarise(
      # weighted mean: bigger sections count more
      fill_rate = sum(section_fill * enrolled) / sum(enrolled),
      .groups   = "drop"
    ) %>%
    mutate(year = as.integer(substr(as.character(term), 1, 4)))

  fill_signal <- fill_by_term %>%
    group_by(subject_course) %>%
    filter(n() >= 2L) %>%
    group_modify(function(d, ...) {
      fit <- lm(fill_rate ~ year, data = d)
      tibble(avg_fill   = mean(d$fill_rate),
             fill_slope = coef(fit)[["year"]])
    }) %>%
    ungroup() %>%
    mutate(flag_fill = avg_fill >= 0.85 | fill_slope >= 0.01)

  # ── Signal 2: Health-student share of total course enrollment ─────────────
  # How dependent is this course on health program students?
  # High share = program headcount growth translates directly to course demand.
  # Flag: avg health share >= 30% in recent falls.
  health_n <- pop_students_baseline %>%
    filter(term %in% recent_falls) %>%
    group_by(subject_course, term) %>%
    summarise(n_health = n_distinct(student_id), .groups = "drop")

  total_n <- sections %>%
    filter(term %in% recent_falls, term_type == season,
           is.na(crosslist_role) | crosslist_role != "partner",
           enrolled > 0,
           if (undergrad_only) level %in% c("upper", "lower") else TRUE) %>%
    group_by(subject_course, term) %>%
    summarise(total = sum(enrolled, na.rm = TRUE), .groups = "drop")

  share_signal <- health_n %>%
    inner_join(total_n, by = c("subject_course", "term")) %>%
    filter(total > 0) %>%
    mutate(share = n_health / total) %>%
    group_by(subject_course) %>%
    summarise(avg_health_share = mean(share,   na.rm = TRUE),
              avg_health_n     = mean(n_health, na.rm = TRUE),
              .groups = "drop") %>%
    filter(avg_health_n >= min_health_n) %>%
    mutate(flag_share = avg_health_share >= 0.30)

  # ── Signal 3: Take rate decline ───────────────────────────────────────────
  # Overall take rate = (health students taking course in term) / (health students enrolled that term).
  # Compares early vs recent baseline windows.
  # A drop > 15% suggests students who need the course are increasingly not getting it.
  prog_headcount <- programs %>%
    filter(program_name %in% program_names, term %in% baseline_falls) %>%
    group_by(term) %>%
    summarise(n_prog = n_distinct(student_id), .groups = "drop")

  takers <- pop_students_baseline %>%
    group_by(subject_course, term) %>%
    summarise(n_takers = n_distinct(student_id), .groups = "drop")

  rate_by_term <- takers %>%
    left_join(prog_headcount, by = "term") %>%
    filter(n_prog > 0) %>%
    mutate(rate   = n_takers / n_prog,
           period = if_else(term %in% early_falls, "early", "recent"))

  rate_signal <- rate_by_term %>%
    group_by(subject_course, period) %>%
    summarise(avg_rate = mean(rate, na.rm = TRUE), .groups = "drop") %>%
    tidyr::pivot_wider(names_from = period, values_from = avg_rate,
                       names_prefix = "rate_") %>%
    filter(!is.na(rate_early), !is.na(rate_recent), rate_early > 0) %>%
    mutate(rate_change_pct = (rate_recent - rate_early) / rate_early,
           flag_rate_drop  = rate_change_pct <= -0.15)

  # ── Signal 4: Band drift ──────────────────────────────────────────────────
  # Average credit band at which health students enroll in this course,
  # compared early vs recent. Rightward drift (later bands) is consistent with
  # students deferring enrollment because they can't get a seat when expected.
  prog_snap <- programs %>%
    filter(program_name %in% program_names, term %in% baseline_falls) %>%
    mutate(credit_band = dplyr::case_when(
      overall_credits_earned <  31 ~ 1L,
      overall_credits_earned <  61 ~ 2L,
      overall_credits_earned <  91 ~ 3L,
      overall_credits_earned < 121 ~ 4L,
      TRUE                         ~ 5L
    )) %>%
    distinct(student_id, term, credit_band)

  band_enrollments <- pop_students_baseline %>%
    inner_join(prog_snap, by = c("student_id", "term")) %>%
    mutate(period = if_else(term %in% early_falls, "early", "recent"))

  band_signal <- band_enrollments %>%
    group_by(subject_course, period) %>%
    summarise(avg_band = mean(credit_band, na.rm = TRUE), .groups = "drop") %>%
    tidyr::pivot_wider(names_from = period, values_from = avg_band,
                       names_prefix = "band_") %>%
    filter(!is.na(band_early), !is.na(band_recent)) %>%
    mutate(band_drift      = band_recent - band_early,
           flag_band_drift = band_drift >= 0.3)

  # ── Combine all signals ───────────────────────────────────────────────────
  # Anchor on courses with meaningful health-student presence (share_signal).
  # All other signals joined left so courses without section or rate data still appear.
  course_titles <- students %>%
    distinct(subject_course, course_title) %>%
    group_by(subject_course) %>%
    slice(1L) %>%
    ungroup()

  result <- share_signal %>%
    left_join(fill_signal,     by = "subject_course") %>%
    left_join(rate_signal,     by = "subject_course") %>%
    left_join(band_signal,     by = "subject_course") %>%
    left_join(course_titles,   by = "subject_course") %>%
    mutate(
      flag_fill       = coalesce(flag_fill,       FALSE),
      flag_share      = coalesce(flag_share,       FALSE),
      flag_rate_drop  = coalesce(flag_rate_drop,   FALSE),
      flag_band_drift = coalesce(flag_band_drift,  FALSE),
      n_flags = as.integer(flag_fill) + as.integer(flag_share) +
                as.integer(flag_rate_drop) + as.integer(flag_band_drift)
    ) %>%
    arrange(desc(n_flags), desc(avg_health_share)) %>%
    select(subject_course, course_title,
           avg_fill, fill_slope, flag_fill,
           avg_health_share, avg_health_n, flag_share,
           rate_early, rate_recent, rate_change_pct, flag_rate_drop,
           band_early, band_recent, band_drift, flag_band_drift,
           n_flags)

  message("[health-whatif.R] Pressure: ", nrow(result), " courses assessed, ",
          sum(result$n_flags >= 3, na.rm = TRUE), " with 3+ flags.")

  list(
    pressure      = result,
    early_terms   = early_falls,
    recent_terms  = recent_falls,
    season        = season,
    undergrad_only = undergrad_only,
    program_names = program_names,
    min_health_n  = min_health_n
  )
}


# =============================================================================
# get_actual_course_demand()
# =============================================================================

get_actual_course_demand <- function(students, programs, program_names,
                                     baseline_terms, validation_terms) {

  pop_ids <- programs %>%
    filter(program_name %in% program_names, program_type == "Major") %>%
    pull(student_id) %>%
    unique()

  message("[health-whatif.R] Hindcast: computing actual demand for ",
          format(length(pop_ids), big.mark = ","), " students across ",
          length(validation_terms), " validation terms.")

  # Baseline average: mean health-student count per course per term_type
  # across all baseline terms. Fall and spring averaged separately because
  # course offerings and enrollment patterns differ by semester.
  baseline_avg <- students %>%
    filter(student_id %in% pop_ids,
           registration_status_code %in% STATUS_REGISTERED,
           term %in% baseline_terms) %>%
    group_by(subject_course, term_type, term) %>%
    summarise(n = n_distinct(student_id), .groups = "drop") %>%
    group_by(subject_course, term_type) %>%
    summarise(baseline_avg = mean(n), .groups = "drop")

  # Actual enrollment per course per validation term
  students %>%
    filter(student_id %in% pop_ids,
           registration_status_code %in% STATUS_REGISTERED,
           term %in% validation_terms) %>%
    group_by(subject_course, term, term_type) %>%
    summarise(actual_n = n_distinct(student_id), .groups = "drop") %>%
    mutate(term_label = if_else(
      term_type == "fall",
      paste("Fall",   substr(as.character(term), 1, 4)),
      paste("Spring", substr(as.character(term), 1, 4))
    )) %>%
    left_join(baseline_avg, by = c("subject_course", "term_type")) %>%
    mutate(
      baseline_avg = coalesce(baseline_avg, 0),
      actual_delta = actual_n - baseline_avg
    ) %>%
    select(subject_course, term, term_label, term_type, actual_n, baseline_avg, actual_delta)
}


# =============================================================================
# get_enrollment_matrix()
# =============================================================================

#' Course × Program Enrollment Matrix
#'
#' Builds a wide matrix showing the average number of students from each
#' selected program enrolled in each course, over the selected term range.
#' Columns represent (program_name × Major/Pre-Major), sorted by total
#' enrollment descending (most students on left). Rows are courses, sorted
#' by total enrollment descending (busiest courses at top).
#'
#' @param programs   Data frame. `cedar_programs`.
#' @param students   Data frame. `cedar_students`.
#' @param program_names  Character vector of program names to include.
#' @param season     `"fall"` or `"spring"`.
#' @param year_range Integer vector of length 2: c(start_year, end_year).
#' @param undergrad_only Logical. Filter to undergraduate students only.
#' @param min_students   Numeric. Minimum average student count for a course
#'   to appear in the matrix. Courses below this threshold are suppressed.
#'
#' @return Named list:
#'   \describe{
#'     \item{`matrix`}{Wide data frame: subject_course, course_title,
#'       one column per (program_name × status) group, row_total.}
#'     \item{`col_order`}{Character vector of column names in display order.}
#'     \item{`col_totals`}{Data frame with col_name and col_total.}
#'     \item{`row_totals`}{Data frame with subject_course and row_total.}
#'     \item{`season`, `year_range`, `undergrad_only`, `program_names`,
#'       `min_students`, `selected_terms`}{Metadata for audit trail.}
#'   }
#'
#' @keywords internal
get_enrollment_matrix <- function(programs, students, program_names,
                                   season         = "fall",
                                   year_range     = c(2023L, 2025L),
                                   undergrad_only = TRUE,
                                   min_students   = 5L) {

  # Compute term codes for the selected season and year range
  years <- seq(as.integer(year_range[1]), as.integer(year_range[2]))
  suffix <- if (season == "fall") "80" else "10"
  selected_terms <- as.integer(paste0(years, suffix))

  if (undergrad_only) {
    programs <- programs %>% filter(student_level == "Undergraduate")
    students <- students %>% filter(student_level == "UG")
  }

  # Snapshot: for each student × term, what program + major/premajor status?
  # One row per (student_id, term, program_name, is_pre_major).
  # A student may appear in multiple programs if they hold multiple majors.
  prog_snap <- programs %>%
    filter(program_name %in% program_names,
           term %in% selected_terms) %>%
    select(student_id, term, program_name, is_pre_major) %>%
    distinct()

  available_terms <- sort(unique(prog_snap$term))
  if (length(available_terms) == 0) {
    stop("[get_enrollment_matrix] No program data found for the selected terms and programs.")
  }

  enrolled <- students %>%
    filter(registration_status_code %in% STATUS_REGISTERED,
           term %in% available_terms) %>%
    select(student_id, term, subject_course) %>%
    distinct()

  # Join: which students from which program are in which course in which term?
  joined <- enrolled %>%
    inner_join(prog_snap, by = c("student_id", "term"),
               relationship = "many-to-many") %>%
    distinct(subject_course, program_name, is_pre_major, student_id, term)

  if (nrow(joined) == 0) {
    stop("[get_enrollment_matrix] No enrollment records matched for the selected programs and terms.")
  }

  # Count distinct students per (course × program group × term)
  per_term <- joined %>%
    group_by(subject_course, program_name, is_pre_major, term) %>%
    summarise(n = n_distinct(student_id), .groups = "drop")

  # Average across terms to get avg students per term
  avg_enroll <- per_term %>%
    group_by(subject_course, program_name, is_pre_major) %>%
    summarise(avg_n = mean(n), .groups = "drop") %>%
    mutate(col_name = paste0(program_name,
                             if_else(is_pre_major, " Pre-Maj", " Major")))

  # Row totals for filtering + sorting
  row_totals <- avg_enroll %>%
    group_by(subject_course) %>%
    summarise(row_total = sum(avg_n), .groups = "drop") %>%
    filter(row_total >= min_students) %>%
    arrange(desc(row_total))

  if (nrow(row_totals) == 0) {
    stop("[get_enrollment_matrix] No courses met the min_students threshold (",
         min_students, "). Try lowering it.")
  }

  # Column totals (across rows that pass the filter)
  col_totals <- avg_enroll %>%
    filter(subject_course %in% row_totals$subject_course) %>%
    group_by(col_name) %>%
    summarise(col_total = sum(avg_n), .groups = "drop") %>%
    arrange(desc(col_total))

  # Course title lookup (one title per course)
  course_titles <- students %>%
    filter(subject_course %in% row_totals$subject_course,
           !is.na(course_title)) %>%
    distinct(subject_course, course_title) %>%
    group_by(subject_course) %>%
    slice(1L) %>%
    ungroup()

  # Pivot wide
  wide <- avg_enroll %>%
    filter(subject_course %in% row_totals$subject_course) %>%
    select(subject_course, col_name, avg_n) %>%
    tidyr::pivot_wider(names_from  = col_name,
                       values_from = avg_n,
                       values_fill = 0) %>%
    left_join(row_totals,    by = "subject_course") %>%
    left_join(course_titles, by = "subject_course") %>%
    arrange(desc(row_total))

  # Enforce column order (most enrolled program on left)
  col_order <- col_totals$col_name
  col_order <- intersect(col_order, names(wide))

  wide <- wide %>%
    select(subject_course, course_title, all_of(col_order), row_total)

  message("[health-whatif.R] Enrollment matrix: ",
          nrow(wide), " courses x ", length(col_order), " program columns, ",
          length(available_terms), " terms averaged (",
          season, " ", year_range[1], "-", year_range[2], ").")

  list(
    matrix         = wide,
    col_order      = col_order,
    col_totals     = col_totals,
    row_totals     = row_totals,
    season         = season,
    year_range     = year_range,
    undergrad_only = undergrad_only,
    program_names  = program_names,
    min_students   = min_students,
    selected_terms = available_terms
  )
}
