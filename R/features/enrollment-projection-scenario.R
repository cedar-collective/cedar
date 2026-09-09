# Population-growth scenarios over a PUBLISHED projection.
#
# A dean asks: "if health professions grows 10% a year for five years, how many
# students and sections will the critical courses need?"
#
# Everything here is arithmetic over rows already saved in the bundle. Nothing
# fits, aftcasts, calibrates, or selects a model -- that is the projection
# contract, and it is also what makes the scenario instant enough to explore.
#
# Year 1 IS the published projection, unchanged. Later years are scenario
# arithmetic and are labeled as such: they carry no accuracy axes and never
# borrow year 1's, because no aftcast has ever been run against a hypothetical.
#
# The growth assumption in one line: the named population's headcount grows at
# the given annual rate, and its students keep taking this course at the rate
# they take it today. Everyone else in the course is held flat. So a course whose
# baseline roster is 13% health-professions students moves 1.3% when that
# population grows 10%, and the page shows that share rather than letting a
# reader assume the whole course grows.


# The scenario's own knobs. Filters are shared with the projection view.
enrollment_projection_scenario_config <- function(opt = list()) {
  list(
    growth_rate = as.numeric(opt$growth_rate %||% 0.10),
    horizon_years = as.integer(opt$horizon_years %||% 5L),
    population_group = opt$population_group %||% NULL,
    major_codes = opt$major_codes %||% NULL,
    include_pre_majors = opt$include_pre_majors %||% "lump",
    # Guard the cell: a course with a handful of the population in it cannot
    # support a claim about how growth there changes its demand.
    min_population_cohort = as.integer(opt$min_population_cohort %||% 10L)
  )
}


#' Project a named population's growth onto published course demand
#'
#' @param bundle A validated enrollment-projection bundle.
#' @param programs cedar_programs, used to resolve a named population group to
#'   Banner major codes. Required when `opt$population_group` is given.
#' @param opt Scenario options plus the usual view filters (`group_id`,
#'   `departments`, `courses`).
#' @return A list: `rows` (one row per course per year), `courses` (one row per
#'   course with its cohort and share), `meta`, and `excluded`.
build_enrollment_projection_scenario <- function(bundle, programs = NULL,
                                                 opt = list()) {
  validate_enrollment_projection_bundle(bundle)
  config <- enrollment_projection_scenario_config(opt)
  if (!is.finite(config$growth_rate)) {
    stop("[scenario] growth_rate must be a finite number.", call. = FALSE)
  }
  if (is.na(config$horizon_years) || config$horizon_years < 1L) {
    stop("[scenario] horizon_years must be at least 1.", call. = FALSE)
  }

  codes <- config$major_codes
  group_label <- "Selected major codes"
  if (is.null(codes)) {
    if (is.null(config$population_group)) {
      stop("[scenario] Give either a population_group or explicit major_codes.",
           call. = FALSE)
    }
    if (is.null(programs)) {
      stop("[scenario] cedar_programs is required to resolve a population group.",
           call. = FALSE)
    }
    codes <- population_group_major_codes(
      config$population_group, programs,
      include_pre_majors = config$include_pre_majors
    )
    group_label <- config$population_group
  }
  codes <- unique(as.character(codes))
  if (length(codes) == 0) {
    stop("[scenario] The population resolved to no major codes.", call. = FALSE)
  }

  composition <- bundle$cohort_composition
  if (is.null(composition) || nrow(composition) == 0) {
    stop("[scenario] This bundle carries no cohort_composition; rebuild it ",
         "before running a scenario.", call. = FALSE)
  }

  # Reuse the view's scoping so the scenario and the table it sits beside can
  # never disagree about which courses are in view.
  view <- build_enrollment_projection_view(bundle, opt)
  published <- view$projections
  if (nrow(published) == 0) {
    return(list(
      rows = .empty_scenario_rows(), courses = .empty_scenario_courses(),
      meta = .scenario_meta(bundle, config, group_label, codes, 0L, 0L),
      excluded = .empty_scenario_courses()
    ))
  }

  # CAMPUS_ROLLUP: cohort_composition is already saved at the planning market's
  # grain -- the market's campuses pooled, each student counted once -- and the
  # published projection it is joined to has the same grain. Grouping by campus
  # here would not match the projection the scenario is anchored on.
  cohort <- composition %>%
    dplyr::filter(subject_course %in% .env$published$subject_course) %>%
    dplyr::group_by(subject_course, baseline_term) %>%
    dplyr::summarise(
      baseline_students = sum(n_students),
      population_cohort = sum(n_students[major_code %in% .env$codes],
                              na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      population_share = dplyr::if_else(
        baseline_students > 0, population_cohort / baseline_students, NA_real_
      )
    )

  courses <- published %>%
    dplyr::select(
      subject_course, department, projected_classlist_total,
      reference_section_size, scheduled_sections, target_schedule_available,
      method_label, stability, depth, accuracy
    ) %>%
    dplyr::left_join(cohort, by = "subject_course") %>%
    dplyr::mutate(
      baseline_students = dplyr::coalesce(baseline_students, NA_integer_),
      population_cohort = dplyr::coalesce(population_cohort, NA_integer_),
      eligible = !is.na(population_cohort) &
        population_cohort >= config$min_population_cohort &
        is.finite(projected_classlist_total),
      ineligible_reason = dplyr::case_when(
        is.na(population_cohort) ~
          "No saved baseline roster for this course",
        !is.finite(projected_classlist_total) ~
          "No published projection to grow from",
        population_cohort < config$min_population_cohort ~ paste0(
          "Only ", population_cohort, " of this population in the baseline ",
          "roster (minimum ", config$min_population_cohort, ")"
        ),
        TRUE ~ NA_character_
      )
    )

  # Weak rows stay visible with a reason; they are never silently dropped.
  eligible <- courses %>% dplyr::filter(eligible)
  excluded <- courses %>% dplyr::filter(!eligible)

  rows <- if (nrow(eligible) == 0) .empty_scenario_rows() else {
    years <- seq_len(config$horizon_years)
    dplyr::bind_rows(lapply(years, function(year) {
      # Year 1 is the published projection itself: growth applies to the years
      # AFTER the target term, so g^0 = 1 leaves year 1 untouched at any rate.
      growth_multiple <- (1 + config$growth_rate)^(year - 1L) - 1
      eligible %>%
        dplyr::mutate(
          year_index = year,
          target_term = .scenario_year_term(bundle$target_term, year),
          target_term_label = fmt_term(.scenario_year_term(bundle$target_term, year)),
          basis = dplyr::if_else(year == 1L, "Published projection", "Scenario"),
          population_students = population_cohort * (1 + config$growth_rate)^(year - 1L),
          projected_classlist_total = projected_classlist_total +
            population_cohort * growth_multiple,
          recommended_sections = projection_sections_for_demand(
            projected_classlist_total, reference_section_size
          ),
          additional_sections = projection_additional_sections(
            recommended_sections, scheduled_sections
          )
        )
    })) %>%
      dplyr::arrange(subject_course, year_index) %>%
      dplyr::select(
        subject_course, department, year_index, target_term, target_term_label,
        basis, baseline_students, population_cohort, population_share,
        population_students, projected_classlist_total, reference_section_size,
        scheduled_sections, target_schedule_available, recommended_sections,
        additional_sections, method_label, stability, depth, accuracy
      )
  }

  list(
    rows = rows,
    courses = eligible,
    excluded = excluded %>%
      dplyr::select(subject_course, department, baseline_students,
                    population_cohort, ineligible_reason),
    meta = .scenario_meta(bundle, config, group_label, codes,
                          nrow(eligible), nrow(excluded))
  )
}


# Same season, one year later per step: a Fall target's horizon is Falls.
.scenario_year_term <- function(target_term, year_index) {
  as.integer(target_term) + (as.integer(year_index) - 1L) * 100L
}


.scenario_meta <- function(bundle, config, group_label, codes,
                           n_courses, n_excluded) {
  list(
    target_term = bundle$target_term,
    target_term_label = fmt_term(bundle$target_term),
    as_of_term = bundle$as_of_term,
    market_id = bundle$scope_market_id,
    population_label = group_label,
    population_codes = sort(codes),
    growth_rate = config$growth_rate,
    horizon_years = config$horizon_years,
    min_population_cohort = config$min_population_cohort,
    n_courses = n_courses,
    n_excluded = n_excluded,
    model_version = bundle$model_version,
    assumption = paste0(
      "The population's headcount grows ",
      scales::percent(config$growth_rate, accuracy = 0.1),
      " a year and its students keep taking each course at today's rate. ",
      "Everyone else in the course is held flat."
    )
  )
}


.empty_scenario_rows <- function() {
  tibble::tibble(
    subject_course = character(), department = character(),
    year_index = integer(), target_term = integer(),
    target_term_label = character(), basis = character(),
    baseline_students = integer(), population_cohort = integer(),
    population_share = numeric(), population_students = numeric(),
    projected_classlist_total = numeric(), reference_section_size = numeric(),
    scheduled_sections = integer(), target_schedule_available = logical(),
    recommended_sections = integer(), additional_sections = integer(),
    method_label = character(), stability = character(),
    depth = character(), accuracy = character()
  )
}


.empty_scenario_courses <- function() {
  tibble::tibble(
    subject_course = character(), department = character(),
    baseline_students = integer(), population_cohort = integer(),
    ineligible_reason = character()
  )
}


# ---------------------------------------------------------------------------
# Text preview  (committed production formatter, not a scratch script)
# ---------------------------------------------------------------------------
#
# Stabilize the numbers here before any Shiny surface exists. The formatter owns
# display formatting only: tests and the UI both read the typed payload, never
# this rendered text.

format_enrollment_projection_scenario_preview <- function(scenario,
                                                          measure = "students") {
  if (!measure %in% c("students", "sections", "additional")) {
    stop("[scenario] measure must be students, sections, or additional.",
         call. = FALSE)
  }
  meta <- scenario$meta
  header <- c(
    "# Enrollment Projection Scenario",
    paste0(
      "Population: ", meta$population_label,
      " | Growth: ", scales::percent(meta$growth_rate, accuracy = 0.1),
      " a year | Horizon: ", meta$horizon_years, " years",
      " | Anchor: ", meta$target_term_label,
      " | Data through: ", fmt_term(meta$as_of_term),
      " | Model: ", meta$model_version
    ),
    paste0("Assumption: ", meta$assumption),
    ""
  )
  if (nrow(scenario$rows) == 0L) {
    return(c(header, "No course in scope carries enough of this population to scale."))
  }

  value_column <- switch(
    measure,
    students = "projected_classlist_total",
    sections = "recommended_sections",
    additional = "additional_sections"
  )
  measure_label <- switch(
    measure,
    students = "Projected class-list demand",
    sections = "Sections needed",
    additional = "Additional sections beyond the current schedule"
  )

  wide <- scenario$rows %>%
    dplyr::mutate(
      value = if (measure == "students") {
        projection_preview_integer(.data[[value_column]])
      } else {
        projection_preview_integer(as.numeric(.data[[value_column]]))
      }
    ) %>%
    dplyr::select(subject_course, department, target_term_label, value) %>%
    tidyr::pivot_wider(
      names_from = target_term_label, values_from = value
    )

  context <- scenario$courses %>%
    dplyr::transmute(
      subject_course,
      `Population in course` = projection_preview_integer(population_cohort),
      Share = projection_preview_percent(population_share),
      Method = method_label
    )

  table <- wide %>%
    dplyr::rename(Course = subject_course, Dept = department) %>%
    dplyr::left_join(context, by = c("Course" = "subject_course")) %>%
    dplyr::relocate(`Population in course`, Share, .after = Dept)

  year_columns <- setdiff(
    names(table), c("Course", "Dept", "Population in course", "Share", "Method")
  )
  lines <- projection_preview_markdown_table(
    table, right_align = c(year_columns, "Population in course", "Share")
  )

  excluded_lines <- if (nrow(scenario$excluded) == 0L) character(0) else c(
    "",
    paste0("## Not scaled (", nrow(scenario$excluded), ")"),
    projection_preview_markdown_table(
      scenario$excluded %>%
        dplyr::transmute(
          Course = subject_course, Dept = department,
          `Population in course` = projection_preview_integer(population_cohort),
          Reason = ineligible_reason
        ),
      right_align = "Population in course"
    )
  )

  c(
    header,
    paste0("## ", measure_label),
    lines,
    excluded_lines,
    "",
    paste0(
      "The first year is the published projection. Later years are scenario ",
      "arithmetic: they carry no aftcast accuracy, because no aftcast has been ",
      "run against a hypothetical."
    )
  )
}


print_enrollment_projection_scenario_preview <- function(scenario,
                                                         measure = "students") {
  output <- format_enrollment_projection_scenario_preview(scenario, measure)
  cat(output, sep = "\n")
  invisible(output)
}
