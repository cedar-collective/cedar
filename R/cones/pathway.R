#' Curriculum Pathway Analysis
#'
#' @description
#' Maps how a defined student population moves through the curriculum over time.
#' The core question is: when do students in this population typically take each
#' course, and what sequences are most common?
#'
#' Timing is expressed in **relative terms** — the 1st, 2nd, 3rd term a student
#' was enrolled — rather than calendar years. This aligns students who started
#' in different semesters or years so their academic trajectories are comparable.
#'
#' **Note on terminology:** The `cohort` parameter accepted by these functions
#' is a student population defined by program membership (e.g., "all students
#' who ever declared Nursing"), not an entry-term cohort in the IPEDS sense.
#' There is no entry-term filter. Students from all entry years are included
#' and aligned by their own first enrolled term.
#'
#' @section What is and isn't reliable:
#'
#' **Reliable:**
#' - Course timing: what fraction of population students took a course in their
#'   1st, 2nd, 3rd term, etc.
#' - Ordered pairs: of students who took course A, what fraction later took B?
#' - Co-enrollment: which courses cluster together in the same term?
#'
#' **Less reliable / interpret with care:**
#' - Full path sequences. Even a population of 200 students typically produces
#'   150+ unique full course sequences. Per-path N is too small for statistics.
#'   Use timing + pairs instead.
#' - Transfer students. Their relative term 1 may be junior-year coursework.
#'   Use `opt$start_classification` to restrict to students who started as
#'   freshmen if you want a clean traditional-student picture.
#'
#' @section RStudio Exploration:
#'
#' ```r
#' library(qs2); library(dplyr); library(ggplot2)
#'
#' cedar_programs <- qs_read("data/cedar_programs.qs")
#' cedar_students <- qs_read("data/cedar_students.qs")
#' source("R/trunk/load-funcs.R")
#' load_funcs(".")   # loads population.R, pathway.R, and all dependencies
#'
#' # Build a student population and get course timing
#' population <- build_population(cedar_programs,
#'                                opt = list(type = "dept", dept_code = "NURS"))
#' timing <- get_course_timing(cedar_students, population, opt = list(min_n = 5))
#'
#' # Visualize as a curriculum map heatmap
#' plot_curriculum_map(timing)
#'
#' # Ordered course pairs (A before B)
#' pairs <- get_course_pairs(cedar_students, population, opt = list())
#' head(pairs, 20)
#'
#' # Restrict to students who started as freshmen
#' timing <- get_course_timing(cedar_students, population,
#'                             opt = list(start_classification = "Freshman"))
#'
#' # Focus on a subject area
#' plot_curriculum_map(timing %>% filter(subject_code == "BIOL"))
#' ```
#'
#' @name pathway


#' Get Course Timing for a Student Population
#'
#' For each course taken by population students, computes how many students took
#' it in each relative term of their academic career (1st, 2nd, 3rd term
#' enrolled, etc.). Returns a data frame suitable for `plot_curriculum_map()`.
#'
#' The `cohort` parameter accepts any tibble with `student_id` and
#' `population_label` columns — typically output from `build_population()`. Despite the
#' parameter name, this is a program-based population filter, not an entry-term
#' cohort. Students from all entry years are included and each student's
#' relative term 1 is anchored to their own first enrolled semester.
#'
#' @param students Data frame. The `cedar_students` table.
#' @param cohort Data frame. Output of `build_population()`. Must have columns
#'   `student_id` and `population_label`. Defines the student population to analyze.
#' @param opt List of options:
#'   \describe{
#'     \item{`start_classification`}{Character vector. Restrict to students
#'       whose first enrollment had this classification. Common values:
#'       `"Freshman"` (matches "Freshman, 1st Yr, 1st Sem" and "Freshman, 1st
#'       Yr, 2nd Sem"), `"Sophomore"`, `"Junior"`, `"Transfer"`. Partial
#'       matching is used. Default: no restriction (all students included).}
#'     \item{`include_summer`}{Logical. Whether to count summer as a separate
#'       relative term. If `FALSE` (default), summer enrollments are included
#'       in the surrounding term's count but summer itself does not advance
#'       the relative term counter.}
#'     \item{`max_relative_term`}{Integer. Cap on relative terms shown.
#'       Default: `8`.}
#'     \item{`min_n`}{Integer. Minimum number of population students who must
#'       have taken a course (across all terms) for it to appear. Default: `10`.}
#'     \item{`campus`}{Character vector of course-delivery campus codes. Scopes
#'       which enrollment rows are counted. This is the campus that taught the
#'       section, not the student's home campus — the two differ on roughly 28%
#'       of enrollment rows, so a population scoped by home campus still pulls in
#'       branch-delivered course rows without it. NULL includes every campus;
#'       pass NULL only for a deliberate UNM-wide aggregate.}
#'     \item{`subject_code`}{Character vector. Restrict to courses in these
#'       subjects (e.g., `c("BIOL", "CHEM")`). Optional.}
#'     \item{`subject_course`}{Character vector. Restrict to an explicit course
#'       list (e.g., the Gen Ed catalog). Applied alongside `subject_code` and,
#'       like it, after `n_eligible` is computed so the denominator stays the
#'       whole population. Optional.}
#'     \item{`denominator`}{Character. What `pct_pop` is a share OF.
#'       `"eligible"` (default) divides by the students who reached that x-axis
#'       position, giving a conditional rate: "of students who got this far, what
#'       share took this course". `"population"` divides by the whole population,
#'       giving "what share of everyone took this course at this point".
#'
#'       The choice matters most at the thin end of an axis. Eligibility falls
#'       away sharply — on a History graduate cohort the five credit bands hold
#'       98, 80, 33, 16 and 4 students — so under `"eligible"` a single student
#'       in the top band reports 25%, indistinguishable from a 23% built on a
#'       hundred. Under `"population"` that same student reports 1%: small,
#'       visible, and comparable with every other cell in the grid. Use
#'       `"population"` when the question is *when* something happens across a
#'       fixed group, and `"eligible"` when it is genuinely conditional on having
#'       got that far.}
#'     \item{`group_campus`}{Logical. Keep `campus` in the output key. Default
#'       `TRUE`, per the CEDAR campus policy. `FALSE` counts each student once
#'       per course regardless of delivery campus — a deliberate exception for
#'       trajectory questions only; see the comment at Step 6.}
#'     \item{`x_axis`}{Character. One of `"relative_term"` (default),
#'       `"classification"`, `"inst_credit_band"`, `"overall_credit_band"`, or
#'       `"unm_credit_band"`. The three band modes all use the same 30-credit
#'       cut points and differ only in where the credit total comes from — see
#'       the `term_credits` parameter for `"unm_credit_band"`.}
#'   }
#'
#' @return Data frame with columns:
#'   \describe{
#'     \item{`subject_course`}{Course identifier, e.g., `"BIOL 2310"`.}
#'     \item{`subject_code`}{Subject prefix, e.g., `"BIOL"`.}
#'     \item{`course_title`}{Course title (most common title for that course).}
#'     \item{`relative_term`}{Integer. Relative term number (1 = student's
#'       first term enrolled, 2 = second, etc.).}
#'     \item{`n_students`}{Number of population students who took this course
#'       in this relative term.}
#'     \item{`n_eligible`}{Number of population students who reached this
#'       relative term (denominator). Students with fewer terms than
#'       `relative_term` are excluded so later terms aren't penalized.}
#'     \item{`pct_pop`}{`n_students / n_eligible`, rounded to 3 decimal
#'       places. Column name retained for downstream compatibility.}
#'     \item{`median_term`}{Median relative term in which this course is
#'       taken, across all population students who took it. Used for sorting
#'       in `plot_curriculum_map()`.}
#'   }
#'
#' @examples
#' \dontrun{
#' population <- build_population(cedar_programs,
#'                            opt = list(type = "health",
#'                                       health_programs = "Radiologic Sciences"))
#' timing <- get_course_timing(cedar_students, population, opt = list())
#' plot_curriculum_map(timing)
#' }
#'
#' @seealso [plot_curriculum_map()], [get_course_pairs()]
#' @export
# Restrict enrollment rows to the campuses a course was *delivered* on.
#
# This is not the same filter as the population campus control. That one scopes
# `student_campus` on cedar_programs — a student's home campus — while this one
# scopes `campus` on cedar_students, the campus that actually taught the section.
# The two disagree on 28% of enrollment rows: an Albuquerque student taking a
# course online through EA or at a branch is common. Filtering only on home
# campus therefore leaves branch-delivered course rows in a main-campus view,
# which is exactly the leak the campus policy in AGENTS.md exists to close.
#
# NULL means every campus. Pass NULL only for a deliberate UNM-wide aggregate.
.filter_course_campus <- function(df, campus = NULL) {
  cedar_filter_campus(df, campus, fn = "pathway.R")
}


# 30-credit bands = one academic year of full-time study, mapping a credit total
# onto a "year" 1–5+. Shared by every credit-band x_axis mode so the three
# differ only in where the credit total comes from, never in where the cuts sit.
.credit_band <- function(credits) {
  dplyr::case_when(
    credits <  31 ~ 1L,   # 0–30   credits (year 1)
    credits <  61 ~ 2L,   # 31–60  credits (year 2)
    credits <  91 ~ 3L,   # 61–90  credits (year 3)
    credits < 121 ~ 4L,   # 91–120 credits (year 4)
    TRUE          ~ 5L    # 121+           (year 5+)
  )
}


#' @param term_credits Data frame or NULL. The `cedar_student_term_credits`
#'   table. **Required by every credit-band x_axis** — `inst_credit_band`,
#'   `overall_credit_band` and `unm_credit_band` all resolve their position
#'   through [build_credit_timeline()]. Ignored by `relative_term` and
#'   `classification`.
#'
#'   None of them may read the Academic Studies cumulative columns on
#'   `cedar_programs`. Those are stamped as of the data pull onto every
#'   historical row the report returns: within a single full historical re-pull
#'   they move across a student's own terms just 16% of the time, and at a
#'   student's first term they overstate the position by a median of 84 credits.
#'   See the field reliability contract in AGENTS.md.
#'
#'   The three modes differ only in what they count:
#'   \describe{
#'     \item{`inst_credit_band`}{UNM credits attempted. Needs `term_credits`.}
#'     \item{`overall_credit_band`}{UNM + transfer. Needs `term_credits` and
#'       `programs`, the latter only to recover the transfer block.}
#'     \item{`unm_credit_band`}{UNM credits completed entering the term.}
#'   }
#'
#' @param programs Data frame or NULL. Used only by `overall_credit_band`, to
#'   recover each student's transfer block. Never read for a per-term credit
#'   total.
get_course_timing <- function(students, population, programs = NULL, opt = list(),
                              students_full = NULL, term_credits = NULL) {

  message("[pathway.R] Starting course timing analysis...")

  validate_population(population, "get_course_timing")

  # --- Read options, using defaults for anything not specified ---
  x_axis            <- opt$x_axis            %||% "relative_term"
  include_summer    <- opt$include_summer    %||% FALSE
  max_relative_term <- opt$max_relative_term %||% 8L
  min_n             <- opt$min_n             %||% 10L  # suppress courses taken by fewer than this many population students
  pop_ids           <- unique(population$student_id)

  x_axis <- match.arg(x_axis, c("relative_term", "classification",
                                 "inst_credit_band", "overall_credit_band",
                                 "unm_credit_band"))

  cedar_require_campus(students, "pathway.R get_course_timing")

  # --- Step 1: Pull registered enrollment rows for population students only ---
  # RE/RS/RR = registered. Drops waitlisted, dropped, and audit rows.
  enrolled <- students %>%
    filter(
      student_id %in% pop_ids,
      registration_status_code %in% STATUS_REGISTERED
    ) %>%
    .filter_course_campus(opt$campus)

  # Optional: restrict to a course level (undergrad, lower-div, upper-div, grad)
  if (!is.null(opt$level) && length(opt$level) > 0) {
    enrolled <- enrolled %>% filter(level %in% opt$level)
  }

  # Optional: restrict to specific term types (fall, spring, summer).
  # When NULL, all term types are included (default pathway behavior).
  if (!is.null(opt$term_type) && length(opt$term_type) > 0) {
    enrolled <- enrolled %>% filter(term_type %in% opt$term_type)
  }

  # Keep only the columns we need; deduplicate (a student registered in the
  # same course twice in one term gets one row).
  enrolled <- enrolled %>%
    # No credit columns carried through from cedar_students: every credit axis
    # now resolves through build_credit_timeline() rather than reading a
    # cumulative column off the enrollment row.
    select(student_id, term, campus, subject_course, course_title,
           student_classification) %>%
    distinct()

  if (nrow(enrolled) == 0) {
    message("[pathway.R] No registered enrollment records found for this population.")
    return(data.frame())
  }

  # --- Step 2: Optionally restrict to students who started at a given classification ---
  # "Start classification" = the student's classification in their VERY FIRST
  # enrolled term. This is useful for separating traditional freshmen from
  # transfer students, who arrive in their junior year and distort timing.
  #
  # Special case: "Transfer" is NOT a Banner student_classification value — it
  # lives in student_population → population$origin. Attempting to
  # grepl("Transfer", student_classification) always returns 0 matches. We
  # detect "Transfer" explicitly and resolve it from the population instead.
  #
  # For all other values (Freshman, Sophomore, Junior, Senior), we check
  # student_classification at the student's earliest enrolled term.
  # Uses students_full (the un-windowed enrollment table) when available so
  # a History major's "first term" isn't their Sophomore year just because
  # their Freshman enrollment preceded their focal-program declaration.
  if (!is.null(opt$start_classification) && length(opt$start_classification) > 0) {

    wants_transfer  <- "Transfer" %in% opt$start_classification
    other_class     <- setdiff(opt$start_classification, "Transfer")

    # Resolve transfer students via population$origin
    transfer_ids <- if (wants_transfer && "origin" %in% names(population)) {
      ts <- population$origin
      population$student_id[!is.na(ts) & ts == "transfer"]
    } else {
      character(0)
    }

    # Resolve other classifications via student_classification in first enrolled term
    class_ids <- if (length(other_class) > 0) {
      pattern  <- paste(other_class, collapse = "|")
      ref_data <- if (!is.null(students_full)) {
        students_full %>%
          filter(student_id %in% pop_ids,
                 registration_status_code %in% STATUS_REGISTERED) %>%
          select(student_id, term, student_classification) %>%
          distinct()
      } else {
        enrolled
      }
      ref_data %>%
        group_by(student_id) %>%
        slice_min(order_by = term, n = 1, with_ties = FALSE) %>%
        ungroup() %>%
        filter(grepl(pattern, student_classification, ignore.case = TRUE)) %>%
        pull(student_id) %>%
        unique()
    } else {
      character(0)
    }

    first_class <- union(transfer_ids, class_ids)
    message("[pathway.R] Restricting to ", length(first_class),
            " students matching start_classification: '",
            paste(opt$start_classification, collapse = ", "), "'",
            if (wants_transfer) paste0(" (", length(transfer_ids), " via origin)"))
    enrolled <- enrolled %>% filter(student_id %in% first_class)
  }

  # Record how many students are contributing data at this point — after level
  # and start_classification filters but before subject filter. The subject filter
  # narrows courses shown but doesn't change who's in the analysis population.
  n_analyzed <- n_distinct(enrolled$student_id)

  # Extract subject prefix from course identifier (e.g., "BIOL 2310" → "BIOL")
  # Done here so subject filter and n_eligible both operate on the same column
  enrolled <- enrolled %>%
    mutate(subject_code = sub(" .*", "", subject_course))

  # --- Step 3: Assign the x-axis position for each enrollment row ---
  # Three modes: relative term number, classification year, or credit band.
  # n_eligible_df is computed here too — it counts how many students "reached"
  # each x-axis position, and is used as the denominator for pct_pop later.

  # Only the credit-band axes drop students for left truncation; the others read
  # a per-term Banner value that does not depend on seeing the earlier record.
  n_truncated <- 0L

  if (x_axis == "relative_term") {

    # Rank each student's distinct enrolled terms chronologically.
    # Term 1 = their first ever enrolled semester, Term 2 = second, etc.
    # Summer does not advance the counter (summer courses pin to the prior fall/spring).
    message("[pathway.R] Computing relative terms per student...")
    enrolled <- assign_relative_terms(enrolled, include_summer)

    enrolled <- enrolled %>%
      filter(relative_term <= max_relative_term, !is.na(relative_term))

    # n_eligible at relative term T = students who have at least T enrolled terms.
    # A student with only 3 terms is excluded from the denominator at term 4+
    # so later terms aren't penalized for short careers.
    students_per_term <- enrolled %>%
      group_by(student_id) %>%
      summarize(max_term = max(relative_term), .groups = "drop")

    eligible_by_rterm <- purrr::map_int(
      seq_len(max_relative_term),
      ~ sum(students_per_term$max_term >= .x)
    )
    n_eligible_df <- tibble(
      relative_term = seq_len(max_relative_term),
      n_eligible    = eligible_by_rterm
    )

  } else if (x_axis == "classification") {

    # Map the student's classification at time of enrollment to an integer:
    # Freshman=1, Sophomore=2, Junior=3, Senior=4.
    # Graduate/other classifications are dropped (NA filtered out).
    message("[pathway.R] Using student classification as x-axis...")
    enrolled <- enrolled %>%
      mutate(
        relative_term = case_when(
          startsWith(student_classification, "Freshman")  ~ 1L,
          startsWith(student_classification, "Sophomore") ~ 2L,
          startsWith(student_classification, "Junior")    ~ 3L,
          startsWith(student_classification, "Senior")    ~ 4L,
          TRUE ~ NA_integer_
        )
      ) %>%
      filter(!is.na(relative_term))

    # n_eligible = students who have ANY enrollment at that classification level
    # (different from the relative_term mode where it's a career-length threshold)
    n_eligible_df <- enrolled %>%
      distinct(student_id, relative_term) %>%
      count(relative_term, name = "n_eligible")

  } else {  # inst_credit_band, overall_credit_band, or unm_credit_band

    # Group students into 30-credit bands based on how many credits they had
    # accumulated at the time they took each course.
    # inst_credit_band = UNM credits only; overall_credit_band = UNM + transfer;
    # unm_credit_band  = UNM credits completed entering the term (class-list derived).
    credit_col <- "credit_band_source"

    if (x_axis == "unm_credit_band") {

      # Credits the student had already EARNED walking into the term, so the
      # course being placed is not counted toward its own band. Sourced from
      # cedar_student_term_credits (one row per enrolled term) rather than the
      # program records — see the term_credits parameter docs above.
      if (is.null(term_credits)) {
        stop("[pathway.R] unm_credit_band mode requires cedar_student_term_credits. ",
             "Pass term_credits = cedar_student_term_credits to get_course_timing().")
      }
      needed <- c("student_id", "term", "completed_unm_credits",
                  "cumulative_completed_unm_credits")
      missing_cols <- setdiff(needed, names(term_credits))
      if (length(missing_cols) > 0) {
        stop("[pathway.R] term_credits is missing required column(s): ",
             paste(missing_cols, collapse = ", "))
      }

      credit_lookup <- term_credits %>%
        dplyr::filter(student_id %in% pop_ids) %>%
        dplyr::transmute(
          student_id, term,
          credit_band_source = cumulative_completed_unm_credits - completed_unm_credits
        ) %>%
        dplyr::distinct(student_id, term, .keep_all = TRUE)
      enrolled <- enrolled %>%
        dplyr::left_join(credit_lookup, by = c("student_id", "term"))

      # This axis derives its position from the same running series, so it
      # inherits the same left-truncation exposure. It reads the completed-credit
      # columns, so it takes the validity rule on its own rather than through
      # build_credit_timeline(), which needs the attempted ones.
      validity <- credit_timeline_validity(
        term_credits, opt = list(student_ids = pop_ids))

    } else {

      # inst_credit_band / overall_credit_band. These used to read
      # cedar_programs' cumulative columns directly at each enrollment term.
      # They cannot: those columns are stamped as of the data pull onto every
      # historical row, so they reported the student's total today no matter
      # which term was being placed — see the field reliability contract in
      # AGENTS.md. Both modes now go through build_credit_timeline(), which
      # rebuilds the position from the per-term class-list series and, for the
      # transfer-inclusive mode, adds a transfer block recovered as the gap
      # between the two frozen columns (a difference taken at one instant, so it
      # survives the freeze).
      #
      # The names are kept because they still describe what the caller gets:
      #   inst_credit_band    — UNM credits only
      #   overall_credit_band — UNM + transfer
      if (is.null(term_credits)) {
        stop("[pathway.R] credit_band modes now require cedar_student_term_credits. ",
             "Pass term_credits = cedar_student_term_credits to get_course_timing(). ",
             "The cedar_programs credit columns cannot answer a per-term question ",
             "(see the field reliability contract in AGENTS.md).")
      }
      if (x_axis == "overall_credit_band" && is.null(programs)) {
        stop("[pathway.R] overall_credit_band needs cedar_programs to recover the ",
             "transfer block. Pass programs = cedar_programs, or use ",
             "inst_credit_band for a UNM-only axis.")
      }

      timeline <- build_credit_timeline(
        term_credits,
        programs = if (x_axis == "overall_credit_band") programs else NULL,
        opt = list(student_ids = pop_ids)
      )
      position_col <- if (x_axis == "inst_credit_band")
        "unm_credits_entering" else "total_credits_entering"

      enrolled <- enrolled %>%
        dplyr::left_join(
          timeline %>% dplyr::select(student_id, term,
                                     credit_band_source = dplyr::all_of(position_col)),
          by = c("student_id", "term"))

      validity <- timeline %>% dplyr::distinct(student_id, timeline_valid)
    }

    enrolled <- enrolled %>%
      dplyr::filter(!is.na(.data[[credit_col]])) %>%
      dplyr::mutate(relative_term = .credit_band(.data[[credit_col]]))

    # --- Left-truncation guard -------------------------------------------------
    # A credit band is a claim about where a student was in their career, and the
    # running total that answers it starts at zero on the student's first term IN
    # THE DATA. For anyone already enrolled when the window opens that is
    # mid-career, so a senior in the first term is placed in the 0-30 band.
    #
    # This is not a rare edge. Measured on current data: 30.1% of students are
    # left-truncated, and 100% of them read 0 credits entering their first
    # in-window term. The error only ever points one way — truncated students are
    # shifted left — so the uncorrected map shows courses being taken earlier in a
    # career than they actually are, and the contamination rises across the bands
    # (32% of records in 0-30, 71% in 150+).
    #
    # The relative_term axis has carried a guard for this for a while. These axes
    # did not need one while they read Banner's frozen cumulative columns, which
    # were wrong in a different way but were not built from a running total. Once
    # they moved onto build_credit_timeline() they acquired the exposure and the
    # guard did not follow. It does now.
    n_students_pre <- dplyr::n_distinct(enrolled$student_id)
    enrolled <- enrolled %>%
      dplyr::left_join(validity, by = "student_id") %>%
      # Unknown validity is not the same as valid — fail closed, as the timeline
      # builder itself does when a student's first term cannot be established.
      dplyr::filter(!is.na(timeline_valid), timeline_valid) %>%
      dplyr::select(-timeline_valid)
    n_truncated <- n_students_pre - dplyr::n_distinct(enrolled$student_id)

    # n_analyzed was taken before the x-axis step, so on a credit axis it still
    # counts the students this guard just removed. Left alone the scope bar reads
    # "629 students analyzed ... 228 students excluded" against a population of
    # 646 — two true numbers that cannot both be post-filter. Restate it as who
    # actually contributed.
    n_analyzed <- dplyr::n_distinct(enrolled$student_id)

    message("[pathway.R] Credit band mode (", x_axis, ") — ",
            nrow(enrolled), " enrollment records with credit data; ",
            n_truncated, " students excluded as left-truncated.")

    # n_eligible = students with any enrollment in each credit band
    n_eligible_df <- enrolled %>%
      dplyr::distinct(student_id, relative_term) %>%
      dplyr::count(relative_term, name = "n_eligible")

  }

  # --- Step 4: Apply optional subject filter ---
  # Done AFTER n_eligible_df is built so the denominator counts all population
  # students at each x-axis position, not just those in the filtered subject.
  # (If we filtered first, n_eligible would only count students who took at
  # least one BIOL course — which understates the true eligible population.)
  if (!is.null(opt$subject_code) && length(opt$subject_code) > 0) {
    enrolled <- enrolled %>%
      filter(subject_code %in% opt$subject_code)
  }
  if (!is.null(opt$subject_course) && length(opt$subject_course) > 0) {
    enrolled <- enrolled %>%
      filter(subject_course %in% opt$subject_course)
  }

  # --- Step 5: Set the course grain ---
  # n_students = distinct population students who took this course at position X.
  # pct_pop = n_students / n_eligible (how many of the students who REACHED
  # this position actually took this course there).
  # Campus is part of the key: the same course delivered in Albuquerque and at a
  # branch is two offerings with different students, and a row that merges them
  # reads as a single main-campus course. n_eligible stays population-wide, so
  # pct_pop is the share of all students who reached this position and took the
  # course *on this campus*.
  #
  # opt$group_campus = FALSE drops campus from the key. This is a deliberate
  # exception to the CEDAR campus policy, of the same kind get_course_pairs()
  # takes: when the question is about one student's trajectory rather than about
  # a course's delivery, campus does not belong in the key. A student who took
  # ENGL 1120 online and PSYC 1110 in Albuquerque has one trajectory, and
  # splitting their row by delivery campus answers a different question while
  # halving every count on a small population. Campus SCOPING (opt$campus) is
  # unaffected and still applies. Only pass FALSE when the caller is reading
  # trajectories; a delivery-mix or course-audience view must keep the default.
  group_campus <- opt$group_campus %||% TRUE
  course_key_cols <- if (isTRUE(group_campus)) {
    c("campus", "subject_course")
  } else {
    "subject_course"
  }
  timing_keys <- if (isTRUE(group_campus)) {
    c("campus", "subject_course", "subject_code", "relative_term")
  } else {
    c("subject_course", "subject_code", "relative_term")
  }

  # A course may have multiple recorded titles across terms. Resolve the most
  # common title inside the same campus-course grain used by the metric.
  course_titles <- enrolled %>%
    group_by(across(all_of(c(course_key_cols, "course_title")))) %>%
    summarize(n = n(), .groups = "drop") %>%
    group_by(across(all_of(course_key_cols))) %>%
    slice_max(n, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    select(all_of(course_key_cols), course_title)

  # --- Step 6: Count students per course per x-axis position ---

  # n_eligible is returned either way — it is what tells a reader how thin a
  # position is — but it only drives pct_pop under the conditional denominator.
  denominator <- match.arg(opt$denominator %||% "eligible", c("eligible", "population"))
  n_population <- length(pop_ids)

  timing <- enrolled %>%
    group_by(across(all_of(timing_keys))) %>%
    summarize(n_students = n_distinct(student_id), .groups = "drop") %>%
    left_join(n_eligible_df, by = "relative_term") %>%
    mutate(pct_pop = if (denominator == "population") {
      round(n_students / n_population, 3)
    } else {
      round(n_students / n_eligible, 3)
    }) %>%
    left_join(course_titles, by = course_key_cols)

  # --- Step 7: Compute each course's median x-axis position ---
  # Used as the sort key in the heatmap: courses taken earlier appear at the top.
  # Each enrollment row contributes one relative_term value, so a course taken
  # by 30 students at Term 2 and 10 at Term 3 gets median ~2.25.
  median_terms <- enrolled %>%
    group_by(across(all_of(course_key_cols))) %>%
    summarize(median_term = median(relative_term), .groups = "drop")

  timing <- timing %>%
    left_join(median_terms, by = course_key_cols)

  # --- Step 8: Drop courses below the minimum student threshold ---
  # min_n applies to total students across ALL x-axis positions for a course.
  # A course taken by 5 students in Term 1 and 3 in Term 2 has total=8 and
  # would be dropped at the default min_n=10.
  course_totals <- timing %>%
    group_by(across(all_of(course_key_cols))) %>%
    summarize(total_students = sum(n_students), .groups = "drop") %>%
    filter(total_students >= min_n) %>%
    select(all_of(course_key_cols))

  timing <- timing %>%
    semi_join(course_totals, by = course_key_cols) %>%
    arrange(across(any_of(c("campus", "subject_course"))), relative_term)

  n_course_groups <- nrow(distinct(timing, across(all_of(course_key_cols))))
  message("[pathway.R] Returning timing data for ", n_course_groups,
          " campus-course groups across ", n_distinct(timing$relative_term),
          " relative terms.")

  # Tag the result with the x_axis mode so plot_curriculum_map() knows which
  # axis labels to use without being told again.
  # Also attach timing_meta so the UI can surface filtering context without
  # re-computing it in the module.
  attr(timing, "x_axis") <- x_axis
  attr(timing, "denominator") <- denominator
  attr(timing, "timing_meta") <- list(
    n_population         = length(pop_ids),
    n_analyzed           = n_analyzed,
    start_classification = opt$start_classification %||% NULL,
    min_n                = min_n,
    n_courses            = n_course_groups,
    # Students dropped because their record starts at the edge of the data, so a
    # credit position could not be established for them. Zero on every non-credit
    # axis. The UI states this rather than letting the cohort silently shrink.
    n_truncated          = n_truncated
  )
  return(timing)
}


#' Plot Curriculum Map Heatmap
#'
#' Visualizes course timing data as a heatmap: relative term on the x-axis,
#' course on the y-axis (sorted by median term taken), and cell fill showing
#' what percentage of eligible cohort students took that course in that term.
#'
#' @param timing_data Data frame. Output of `get_course_timing()`.
#' @param opt List of options:
#'   \describe{
#'     \item{`title`}{Character. Plot title. Default: `"Curriculum Map"`.}
#'     \item{`pct_label_threshold`}{Numeric (0-1). Only show percentage labels
#'       inside cells above this value. Default: `0.05` (5%).}
#'     \item{`fill_color`}{Character. High-end fill color. Defaults to the CEDAR
#'       green (`CEDAR_COLORS["green"]`). Can be any ggplot2-compatible color.}
#'     \item{`facet_by_subject`}{Logical. If `TRUE`, facet rows by subject code
#'       (e.g., all BIOL courses grouped, then CHEM, etc.). Default: `FALSE`.}
#'     \item{`top_n`}{Integer. Maximum number of courses to display. Courses
#'       are ranked by their peak `pct_pop` across all terms; only the top
#'       `top_n` are shown. Default: `40`.}
#'     \item{`min_pct`}{Numeric (0–1). Courses where no term exceeds this
#'       percentage are dropped before applying `top_n`. Default: `0.05`.}
#'   }
#'
#' @return A ggplot2 object. Use `ggsave()` to save or display in RStudio viewer.
#'
#' @examples
#' \dontrun{
#' timing <- get_course_timing(cedar_students, cohort, opt = list())
#' plot_curriculum_map(timing)
#'
#' # Save to file
#' p <- plot_curriculum_map(timing, opt = list(title = "Radiologic Sciences Pathway"))
#' ggsave("output/radiology-pathway.png", p, width = 12, height = 8)
#'
#' # Subject-only view
#' plot_curriculum_map(timing %>% filter(subject_code %in% c("BIOL","CHEM","PHYS")))
#' }
#'
#' @seealso [get_course_timing()]
#' @export
plot_curriculum_map <- function(timing_data, opt = list()) {

  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("[pathway.R] ggplot2 is required for plot_curriculum_map()")
  }

  title               <- opt$title               %||% "Curriculum Map"
  note                <- opt$note                %||% NULL
  pct_label_threshold <- opt$pct_label_threshold %||% 0.05
  fill_color          <- opt$fill_color          %||% unname(CEDAR_COLORS["green"])
  facet_by_subject    <- opt$facet_by_subject    %||% FALSE
  top_n               <- opt$top_n               %||% 40L
  min_pct             <- opt$min_pct             %||% 0.05
  # Prefer the x_axis mode embedded in the data (set by get_course_timing),
  # falling back to opt$x_axis, then "relative_term"
  x_axis <- attr(timing_data, "x_axis") %||% opt$x_axis %||% "relative_term"
  # The subtitle states what the denominator IS, so it has to follow the data
  # rather than assume the conditional one. A chart that says "denominator =
  # students who reached that term" while dividing by the whole population is
  # describing a different calculation than the one it drew.
  denominator <- attr(timing_data, "denominator") %||% opt$denominator %||% "eligible"

  if (nrow(timing_data) == 0) {
    message("[pathway.R] plot_curriculum_map: timing_data is empty, returning NULL")
    return(NULL)
  }

  has_campus <- "campus" %in% names(timing_data)
  timing_data <- timing_data %>%
    mutate(
      .course_key = if (has_campus) {
        paste(campus, subject_course, sep = "|")
      } else {
        as.character(subject_course)
      },
      .course_label = if (has_campus) {
        paste(subject_course, campus, sep = " · ")
      } else {
        as.character(subject_course)
      }
    )

  # Drop campus-course groups that never exceed min_pct in any term.
  timing_data <- timing_data %>%
    group_by(.course_key) %>%
    filter(max(pct_pop, na.rm = TRUE) >= min_pct) %>%
    ungroup()

  # If still more than top_n groups, keep only the top_n by peak pct_pop.
  if (dplyr::n_distinct(timing_data$.course_key) > top_n) {
    top_courses <- timing_data %>%
      group_by(.course_key) %>%
      summarize(peak_pct = max(pct_pop, na.rm = TRUE), .groups = "drop") %>%
      dplyr::slice_max(peak_pct, n = top_n) %>%
      pull(.course_key)
    timing_data <- timing_data %>% filter(.course_key %in% top_courses)
  }

  message("[pathway.R] Plotting ", dplyr::n_distinct(timing_data$.course_key),
          " campus-course groups.")

  # Order campus-course groups by median term, then label.
  course_order <- timing_data %>%
    select(.course_key, .course_label, median_term) %>%
    distinct() %>%
    arrange(median_term, .course_label) %>%
    pull(.course_label)

  plot_data <- timing_data %>%
    mutate(
      .course_label = factor(.course_label, levels = rev(course_order)),
      label          = ifelse(pct_pop >= pct_label_threshold,
                              scales::percent(pct_pop, accuracy = 1),
                              "")
    )

  p <- ggplot2::ggplot(
    plot_data,
    ggplot2::aes(x = relative_term, y = .course_label, fill = pct_pop)
  ) +
    ggplot2::geom_tile(color = "white", linewidth = 0.4) +
    ggplot2::geom_text(
      ggplot2::aes(label = label),
      size = 3.5, color = "white", fontface = "bold"
    ) +
    ggplot2::scale_fill_gradient(
      low      = "#EAF1EC",   # pale cedar tint — sequential ramp toward fill_color
      high     = fill_color,
      na.value = unname(CEDAR_COLORS["gray"]),
      labels   = scales::percent_format(accuracy = 1),
      name     = "% of students\n(in that term)"
    ) +
    {
      x_breaks <- sort(unique(plot_data$relative_term))
      if (x_axis == "classification") {
        class_labels <- c("1" = "Freshman", "2" = "Sophomore",
                          "3" = "Junior",   "4" = "Senior")
        ggplot2::scale_x_continuous(
          breaks = x_breaks,
          labels = class_labels[as.character(x_breaks)]
        )
      } else if (x_axis %in% c("inst_credit_band", "overall_credit_band",
                               "unm_credit_band")) {
        band_labels <- c("1" = "0–30", "2" = "31–60", "3" = "61–90",
                         "4" = "91–120", "5" = "121+")
        ggplot2::scale_x_continuous(
          breaks = x_breaks,
          labels = band_labels[as.character(x_breaks)]
        )
      } else {
        ggplot2::scale_x_continuous(
          breaks = x_breaks,
          labels = paste0("Term\n", x_breaks)
        )
      }
    } +
    ggplot2::labs(
      title    = title,
      subtitle = {
        position <- dplyr::case_when(
          x_axis == "classification"      ~ "at that classification level",
          x_axis == "inst_credit_band"    ~ "at that UNM-credit band (transfer not included; 30-credit bands)",
          x_axis == "overall_credit_band" ~ "at that overall-credit band (UNM + transfer; 30-credit bands)",
          x_axis == "unm_credit_band"     ~ "at that credit band (UNM credits entering the term; 30-credit bands)",
          TRUE                            ~ "in that relative term"
        )
        if (denominator == "population") {
          paste0("Each cell = % of ALL population students who took this course ", position,
                 ". Denominator = the whole population, so cells are comparable across the axis ",
                 "and a row sums to the share who ever took the course.")
        } else {
          paste0("Each cell = % of population students who took this course ", position,
                 ". Denominator = students who reached that position.")
        }
      },
      x = NULL,
      y = NULL,
      caption = {
        base_caption <- dplyr::case_when(
          x_axis == "classification" ~
            "Classification at time of enrollment (Freshman/Sophomore/Junior/Senior).",
          x_axis == "inst_credit_band" ~
            "Credit bands based on institution credits attempted (UNM only) at time of enrollment.",
          x_axis == "overall_credit_band" ~
            "Credit bands based on overall credits earned (UNM + transfer) at time of enrollment.",
          x_axis == "unm_credit_band" ~
            "Credit bands based on UNM credits completed before the term, from class-list records.",
          TRUE ~
            paste0("Relative terms count from each student's first enrolled term, ",
                   "excluding summer unless opt$include_summer = TRUE.")
        )
        if (!is.null(note)) paste0(base_caption, "\n", note) else base_caption
      }
    ) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      panel.grid    = ggplot2::element_blank(),
      axis.text.y   = ggplot2::element_text(size = 9),
      axis.text.x   = ggplot2::element_text(size = 9),
      plot.title    = ggplot2::element_text(face = "bold", size = 11),
      plot.subtitle = ggplot2::element_text(size = 8, color = "grey40"),
      plot.caption  = ggplot2::element_text(size = 7, color = "grey50"),
      plot.margin   = ggplot2::margin(6, 6, 6, 6),
      legend.position = "right"
    )

  if (facet_by_subject && "subject_code" %in% names(plot_data)) {
    p <- p + ggplot2::facet_grid(
      rows     = ggplot2::vars(subject_code),
      scales   = "free_y",
      space    = "free_y"
    )
  }

  return(p)
}


#' Get Ordered Course Pairs for a Student Population
#'
#' Identifies the most common ordered course sequences — cases where a
#' student took course A in one term and course B in a later term. This
#' captures the implicit prerequisite chains that students actually follow,
#' as opposed to the formally catalogued ones.
#'
#' Only courses taken by at least `opt$min_n` population students are included.
#' Only pairs where the A→B pattern occurred at least `opt$min_pair_n` times
#' are returned.
#'
#' @param students Data frame. The `cedar_students` table.
#' @param cohort Data frame. Output of `build_population()`. Defines the student
#'   population to analyze — a program-based filter, not an entry-term cohort.
#' @param opt List of options:
#'   \describe{
#'     \item{`min_n`}{Integer. Minimum population students who took course A
#'       for it to be included as a pair source. Default: `15`.}
#'     \item{`min_pair_n`}{Integer. Minimum population students exhibiting the
#'       A→B pattern for the pair to appear in results. Default: `10`.}
#'     \item{`max_term_gap`}{Integer. Maximum number of relative terms between
#'       A and B. Default: `4` (pairs more than 4 terms apart are unlikely to
#'       be meaningfully sequential).}
#'     \item{`campus`}{Character vector of course-delivery campus codes. Scopes
#'       which enrollment rows are counted. This is the campus that taught the
#'       section, not the student's home campus — the two differ on roughly 28%
#'       of enrollment rows, so a population scoped by home campus still pulls in
#'       branch-delivered course rows without it. NULL includes every campus;
#'       pass NULL only for a deliberate UNM-wide aggregate.}
#'     \item{`subject_code`}{Character vector. Restrict to courses in these
#'       subjects. Optional.}
#'     \item{`censor_term`}{Integer term code of the last complete data term.
#'       When supplied, A-side enrollments (and the `pct_a_to_b` denominator)
#'       are restricted to terms with `max_term_gap` complete regular terms of
#'       follow-up, so recently-taken courses don't show deflated follow-on
#'       rates purely because the data ends (right-censoring). Optional;
#'       NULL preserves uncensored behavior.}
#'   }
#'
#' @return Data frame sorted by `n_students` descending, with columns:
#'   \describe{
#'     \item{`course_a`}{First course in the pair.}
#'     \item{`course_b`}{Second course (taken after A).}
#'     \item{`n_students`}{Population students who took A and then took B.}
#'     \item{`n_took_a`}{Total population students who took course A (denominator).}
#'     \item{`pct_a_to_b`}{`n_students / n_took_a`: of students who took A,
#'       what fraction went on to take B?}
#'     \item{`median_term_gap`}{Median number of relative terms between taking
#'       A and taking B.}
#'   }
#'
#' @examples
#' \dontrun{
#' population <- build_population(cedar_programs,
#'                            opt = list(type = "health",
#'                                       health_programs = "Radiologic Sciences"))
#' pairs <- get_course_pairs(cedar_students, population, opt = list())
#' # Top transitions out of BIOL 2310
#' pairs %>% filter(course_a == "BIOL 2310")
#' }
#'
#' @seealso [get_course_timing()]
#' @export
get_course_pairs <- function(students, population, opt = list()) {

  message("[pathway.R] Computing ordered course pairs...")

  # --- Read options ---
  min_n        <- opt$min_n        %||% 15L   # minimum students in course A to include it
  min_pair_n   <- opt$min_pair_n   %||% 10L   # minimum A→B occurrences to show the pair
  max_term_gap <- opt$max_term_gap %||% 4L    # ignore pairs more than this many terms apart
  pop_ids      <- unique(population$student_id)

  cedar_require_campus(students, "pathway.R get_course_pairs")

  # --- Step 1: Pull registered enrollment rows for population students ---
  enrolled <- students %>%
    filter(
      student_id %in% pop_ids,
      registration_status_code %in% STATUS_REGISTERED
    ) %>%
    .filter_course_campus(opt$campus)

  if (!is.null(opt$level) && length(opt$level) > 0) {
    enrolled <- enrolled %>% filter(level %in% opt$level)
  }

  # One row per student per course per term (deduplicated).
  #
  # Campus scopes which rows enter the self-join but is deliberately NOT part of
  # the pair key. A pair is a statement about one student taking two courses, and
  # those two can legitimately sit on different campuses — an Albuquerque student
  # taking the follow-on online through EA is an ordinary path, not a data error.
  # Forcing a single campus onto the row would either drop those pairs or label
  # them with a campus only half the pair belongs to. The scope is reported
  # alongside the table instead. This is the deliberate exception the campus
  # policy allows; see AGENTS.md.
  enrolled <- enrolled %>%
    select(student_id, term, subject_course) %>%
    distinct()

  # Optional subject filter — applied before the self-join to keep it small
  if (!is.null(opt$subject_code) && length(opt$subject_code) > 0) {
    enrolled <- enrolled %>%
      filter(sub(" .*", "", subject_course) %in% opt$subject_code)
  }

  # --- Step 2: Assign relative term numbers ---
  # Same logic as get_course_timing: summer doesn't advance the counter.
  enrolled <- assign_relative_terms(enrolled, include_summer = FALSE)

  # --- Step 2b: Observation-window censoring (A side only) ---
  # An A-enrollment only gets a fair chance to show a follow-on B if the data
  # contains max_term_gap complete regular terms after it. Without this,
  # recently-taken courses drag pct_a_to_b down purely because the data ends
  # (right-censoring), not because students skip the follow-on.
  # opt$censor_term = last complete data term (the Pathways module passes it);
  # A-side rows — and the pct denominator — are restricted to calendar terms
  # with a full follow-up window. B-side rows are never censored.
  # NULL censor_term (e.g. standalone RStudio use) preserves old behavior.
  a_pool <- enrolled
  a_boundary <- NULL
  if (!is.null(opt$censor_term) && !is.na(opt$censor_term)) {
    a_boundary <- pathways_observation_boundary(opt$censor_term, max_term_gap)
    a_pool <- a_pool %>% filter(term <= a_boundary)
    message("[pathway.R] Censoring A-side enrollments after ", a_boundary,
            " (", max_term_gap, " regular terms of follow-up required; data through ",
            opt$censor_term, ").")
  }

  # --- Step 3: Pre-filter to qualifying course_a candidates before the self-join ---
  # This is the key scaling fix. A full enrolled × enrolled self-join is O(N²) in
  # enrollment rows. Computing n_took_a first and restricting the left side to
  # qualifying courses reduces the left factor significantly — typically 5–10× for
  # large populations where most courses fall below the min_n threshold.
  # The right side (course_b) stays unrestricted: any course can follow a qualifying A.
  # n_took_a comes from the censored A pool so the pct_a_to_b denominator matches
  # the numerator's observation window.
  # CAMPUS_ROLLUP: course pairs describe institution-wide student trajectories
  # within the selected campus scope, not performance of a delivery campus.
  n_took_a <- a_pool %>%
    group_by(subject_course) %>%
    summarize(n_took_a = n_distinct(student_id), .groups = "drop") %>%
    filter(n_took_a >= min_n)

  enrolled_a <- a_pool %>%
    filter(subject_course %in% n_took_a$subject_course)

  message("[pathway.R] Pair search: ", nrow(enrolled_a), " A-side rows × ",
          nrow(enrolled), " B-side rows (", n_distinct(enrolled_a$subject_course),
          " qualifying courses at min_n = ", min_n, ").")

  # --- Step 4: Find all ordered pairs (A, B) where B is taken after A ---
  # Only courses meeting min_n appear on the A side; all courses can appear on B.
  # max_term_gap prevents counting distant pairs like "ENGL 1110 → HIST 4800"
  # (8 terms apart) as meaningful sequences.
  pairs <- enrolled_a %>%
    rename(course_a = subject_course, term_a = relative_term) %>%
    inner_join(
      enrolled %>% rename(course_b = subject_course, term_b = relative_term),
      by = "student_id", relationship = "many-to-many"
    ) %>%
    filter(
      term_b > term_a,                       # B is strictly after A
      term_b - term_a <= max_term_gap,        # not too far apart
      course_a != course_b                   # not the same course twice
    ) %>%
    select(student_id, course_a, course_b, term_a, term_b) %>%
    distinct()

  # --- Step 5: Aggregate pair counts and compute the A→B rate ---
  # n_students = distinct students who took A and then took B
  # pct_a_to_b = of everyone who took A, what fraction also took B afterward?
  # median_term_gap = typical number of terms between taking A and taking B
  result <- pairs %>%
    group_by(course_a, course_b) %>%
    summarize(
      n_students      = n_distinct(student_id),
      median_term_gap = median(term_b - term_a),
      .groups = "drop"
    ) %>%
    inner_join(n_took_a %>% rename(course_a = subject_course), by = "course_a") %>%
    mutate(pct_a_to_b = round(n_students / n_took_a, 3)) %>%
    filter(n_students >= min_pair_n) %>%
    arrange(desc(n_students)) %>%
    select(course_a, course_b, n_students, n_took_a, pct_a_to_b, median_term_gap)

  message("[pathway.R] Returning ", nrow(result), " course pairs.")

  attr(result, "pair_meta") <- list(
    n_qualifying = n_distinct(enrolled_a$subject_course),
    n_a_rows     = nrow(enrolled_a),
    n_b_rows     = nrow(enrolled),
    min_n        = min_n,
    min_pair_n   = min_pair_n,
    n_pairs      = nrow(result),
    a_boundary   = a_boundary
  )
  return(result)
}


#' Get Courses Adjacent to Student Entry or Exit Events
#'
#' Finds courses taken in the term(s) immediately before a population-level
#' change event and compares their frequency across two groups. For entry
#' events: converters (pre-majors who eventually declared) vs. non-converters
#' (pre-majors who left without declaring). For exit events: students who left
#' vs. students who stayed.
#'
#' Lift > 1 means the course appears disproportionately in the primary group
#' (converters for entry, leavers for exit) relative to the comparison group.
#' This is a correlation, not evidence of causation.
#'
#' @param students   Data frame. The `cedar_students` table.
#' @param population Data frame. Output of `build_population()`. Must have
#'   columns `student_id`, `outcome`, `first_unit_term`, `last_unit_term`.
#'   `entry_status` is not required — groups are assigned by outcome alone,
#'   so all entry paths (pre_major, switched_in, undecided) are included.
#' @param event      Character. `"entry"` (default) or `"exit"`.
#' @param window     Integer. Number of non-summer terms to look back from the
#'   event term. Default: `1L` (the single term immediately preceding).
#' @param include_event_term Logical. Whether to include the event term itself.
#'   Default: `FALSE`. Setting `TRUE` mixes gateway courses with first-term
#'   required courses.
#' @param min_n      Integer. Minimum students per group for a course to appear.
#'   Default: `5L`.
#' @param campus     Character vector of course-delivery campus codes. Scopes
#'   which enrollment rows are counted and is part of the output grouping. NULL
#'   includes every campus — pass NULL only for a deliberate UNM-wide aggregate.
#'   Note this is the campus that taught the section, not the student's home
#'   campus; the two differ on roughly 28% of enrollment rows.
#'
#' @return Wide data frame with one row per course and columns for each group's
#'   student count (`n_students_*`), group size (`n_group_*`), rate (`pct_*`),
#'   and `lift`. Attributes include `ep_meta` (list with n per group, n excluded
#'   for no prior term). Returns an empty data frame if no qualifying students
#'   are found.
#'
#' @seealso [get_course_timing()], [get_course_pairs()]
#' @export
get_event_adjacent_courses <- function(students, population,
                                        event              = "entry",
                                        window             = 1L,
                                        include_event_term = FALSE,
                                        min_n              = 5L,
                                        campus             = NULL) {

  needed <- c("student_id", "outcome", "first_unit_term", "last_unit_term")
  missing_cols <- setdiff(needed, names(population))
  if (length(missing_cols) > 0)
    stop("[pathway.R] population missing columns for event analysis: ",
         paste(missing_cols, collapse = ", "),
         ". Ensure build_population() was called with students= provided.")

  # ── Assign groups and anchor event terms ──────────────────────────────────

  if (event == "entry") {
    # Groups are based on outcome, not entry path. This includes switched_in
    # students (who took courses in the target major before switching, which
    # may have precipitated the switch) and students from undecided/general
    # pools who are not pre-majors in any formal sense. All are anchored at
    # first_unit_term — the semester before that window is what we examine.
    pop_grp <- population %>%
      mutate(
        event_term = first_unit_term,
        group = case_when(
          outcome %in% c("ongoing", "graduated",
                         "switched_out", "stopped_out") ~ "entered",
          outcome %in% c("chose_elsewhere",
                         "left_undeclared")             ~ "did_not_enter",
          TRUE ~ NA_character_
        )
      ) %>%
      filter(!is.na(group))

  } else if (event == "exit") {
    pop_grp <- population %>%
      mutate(
        event_term = last_unit_term,
        group = case_when(
          outcome %in% c("switched_out", "stopped_out",
                         "chose_elsewhere", "left_undeclared") ~ "left",
          outcome %in% c("ongoing", "graduated")               ~ "stayed",
          TRUE ~ NA_character_
        )
      ) %>%
      filter(!is.na(group))

  } else {
    stop("[pathway.R] event must be 'entry' or 'exit', got: '", event, "'")
  }

  if (nrow(pop_grp) == 0) {
    message("[pathway.R] No qualifying students for event='", event,
            "' (entry_status filter may have removed everyone).")
    return(data.frame())
  }

  message("[pathway.R] Event-adjacent courses: event='", event, "', ",
          n_distinct(pop_grp$student_id), " students in ",
          n_distinct(pop_grp$group), " groups.")

  # ── Build per-student term windows in absolute calendar space ─────────────
  #
  # Position-based lookup: find each event_term's index in the ordered list of
  # non-summer terms, then take the N terms before it. This correctly handles
  # the irregular YYYYSS gaps (spring=10, summer=60, fall=80).
  all_main_terms <- sort(unique(students$term[
    substr(as.character(students$term), 5, 6) != "60"
  ]))

  unique_event_terms <- unique(pop_grp$event_term[!is.na(pop_grp$event_term)])

  window_df <- purrr::map_dfr(unique_event_terms, function(et) {
    idx       <- match(et, all_main_terms)
    if (is.na(idx)) return(NULL)
    start_idx <- max(1L, idx - window)
    end_idx   <- if (include_event_term) idx else idx - 1L
    if (end_idx < start_idx) return(NULL)   # no prior term exists for this student
    tibble(event_term = et, term = all_main_terms[start_idx:end_idx])
  })

  if (nrow(window_df) == 0) {
    message("[pathway.R] No prior-term windows found ",
            "(all students may have entered in the earliest data term).")
    return(data.frame())
  }

  student_windows <- pop_grp %>%
    select(student_id, group, event_term) %>%
    inner_join(window_df, by = "event_term", relationship = "many-to-many")

  n_no_prior <- n_distinct(pop_grp$student_id) - n_distinct(student_windows$student_id)
  if (n_no_prior > 0)
    message("[pathway.R] ", n_no_prior,
            " student(s) excluded: no prior term on record before their event term.")

  # ── Join enrollment records for those windows ─────────────────────────────

  enrolled_in_window <- students %>%
    filter(registration_status_code %in% STATUS_REGISTERED) %>%
    .filter_course_campus(campus) %>%
    select(student_id, term, campus, subject_course, course_title) %>%
    distinct() %>%
    inner_join(student_windows %>% select(student_id, group, term),
               by = c("student_id", "term"))

  if (nrow(enrolled_in_window) == 0) {
    message("[pathway.R] No enrollment records found in event windows.")
    return(data.frame())
  }

  # ── Aggregate: courses per group, percentage of group ─────────────────────

  group_sizes <- student_windows %>%
    distinct(student_id, group) %>%
    count(group, name = "n_group")

  course_counts <- enrolled_in_window %>%
    # Campus joins the key: this table names courses, and a branch-delivered
    # section merged into a main-campus row reads as the same offering.
    group_by(group, campus, subject_course) %>%
    summarize(
      n_students   = n_distinct(student_id),
      course_title = first(course_title),
      .groups      = "drop"
    ) %>%
    left_join(group_sizes, by = "group") %>%
    mutate(
      pct          = round(n_students / n_group, 3),
      subject_code = sub(" .*", "", subject_course)
    ) %>%
    filter(n_students >= min_n)

  if (nrow(course_counts) == 0) {
    message("[pathway.R] No courses met min_n = ", min_n, " threshold.")
    return(data.frame())
  }

  # ── Pivot wide: one row per course ────────────────────────────────────────

  result <- course_counts %>%
    select(subject_course, subject_code, course_title,
           group, n_students, n_group, pct) %>%
    tidyr::pivot_wider(
      names_from  = group,
      values_from = c(n_students, n_group, pct),
      values_fill = list(n_students = 0L, pct = 0)
    )

  # ── Lift: ratio of primary group rate to comparison group rate ─────────────
  # > 1 = disproportionately associated with the primary group

  if (event == "entry" &&
      all(c("pct_entered", "pct_did_not_enter") %in% names(result))) {
    result <- result %>%
      mutate(lift = ifelse(pct_did_not_enter > 0,
                           round(pct_entered / pct_did_not_enter, 2),
                           NA_real_))
  } else if (event == "exit" &&
             all(c("pct_left", "pct_stayed") %in% names(result))) {
    result <- result %>%
      mutate(lift = ifelse(pct_stayed > 0,
                           round(pct_left / pct_stayed, 2),
                           NA_real_))
  }

  # Attach group-size metadata so callers can surface n_group without re-computing
  attr(result, "ep_meta") <- list(
    event      = event,
    n_groups   = as.list(setNames(group_sizes$n_group, group_sizes$group)),
    n_no_prior = n_no_prior,
    n_courses  = nrow(result),
    min_n      = min_n
  )

  message("[pathway.R] Returning ", nrow(result), " courses with event adjacency data.")
  result
}


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

#' Assign Relative Term Numbers to Enrollment Records
#'
#' For each student, ranks their enrolled terms chronologically (1 = first term,
#' 2 = second, etc.) and adds a `relative_term` column.
#'
#' UNM term codes are YYYYSS format (e.g., 202510 = Spring 2025, 202560 = Summer,
#' 202580 = Fall). Numeric sort order is chronological order, so no external
#' lookup is needed.
#'
#' Summer terms (SS = "60") can be excluded from the counter — they don't
#' advance the relative term number but summer courses are still assigned to
#' the relative term of the preceding non-summer term.
#'
#' @param enrolled Data frame with columns: `student_id`, `term`.
#' @param include_summer Logical. Whether summer counts as its own relative
#'   term. Default: `FALSE`.
#'
#' @return `enrolled` with a `relative_term` integer column added.
#'
#' @keywords internal
assign_relative_terms <- function(enrolled, include_summer = FALSE) {

  # Tag each row with its integer term code and whether it's a summer term.
  # UNM term codes end in "60" for summer (e.g., 202560 = Summer 2025).
  enrolled <- enrolled %>%
    mutate(
      term_int  = as.integer(term),
      is_summer = substr(as.character(term), 5, 6) == "60"
    )

  if (!include_summer) {
    # --- Summer-excluded mode (default) ---
    # Summer does not count as its own relative term. A student whose first
    # three enrolled terms are Fall, Summer, Spring is treated as having two
    # relative terms, not three. Summer courses are assigned the relative_term
    # of the immediately preceding fall or spring.
    #
    # Implementation: rank non-summer terms per student, then combine with
    # summer terms (rank = NA) and forward-fill. This replaces the previous
    # many-to-many join approach and is O(N log N) instead of O(N × M).

    # Step A: rank each student's non-summer terms in chronological order
    non_summer_ranks <- enrolled %>%
      filter(!is_summer) %>%
      select(student_id, term_int) %>%
      distinct() %>%
      arrange(student_id, term_int) %>%
      group_by(student_id) %>%
      mutate(relative_term = row_number()) %>%
      ungroup()

    # Step B: combine ranked non-summer + unranked summer rows, sorted by
    # (student, term). Forward-fill propagates each non-summer rank to all
    # subsequent summer rows for the same student. coalesce(1L) handles the
    # edge case where a student's first enrolled term is summer.
    term_rterm <- bind_rows(
      non_summer_ranks,
      enrolled %>%
        filter(is_summer) %>%
        select(student_id, term_int) %>%
        distinct() %>%
        mutate(relative_term = NA_integer_)
    ) %>%
      distinct(student_id, term_int, .keep_all = TRUE) %>%
      arrange(student_id, term_int) %>%
      group_by(student_id) %>%
      tidyr::fill(relative_term) %>%                       # forward-fill summer ranks
      mutate(relative_term = dplyr::coalesce(relative_term, 1L)) %>%   # leading-summer edge case
      ungroup()

  } else {
    # --- Summer-included mode ---
    # Every term (including summer) advances the relative term counter.
    term_rterm <- enrolled %>%
      select(student_id, term_int) %>%
      distinct() %>%
      arrange(student_id, term_int) %>%
      group_by(student_id) %>%
      mutate(relative_term = row_number()) %>%
      ungroup()
  }

  # Join the relative_term back onto the original enrollment rows
  enrolled %>%
    left_join(term_rterm %>% select(student_id, term_int, relative_term),
              by = c("student_id", "term_int")) %>%
    select(-term_int, -is_summer)
}


# Null-coalescing operator - define only if not already loaded.
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}
