# Enrollment projections, the view: what build_enrollment_projection_view()
# and its companions derive for the page, as numbers, flags and columns. The
# sentences it writes are held in snapshots (tests/testthat/_snaps): a wording
# change is accepted with testthat::snapshot_accept() and reviewed as a diff.
testthat::local_edition(3)

test_that("historical-method plot compares one term type with lifecycle actuals", {
  history <- tidyr::crossing(
    method_id = c("seasonal_last", "spine_adjusted"),
    target_term = c(202410L, 202510L, 202610L)
  ) %>%
    dplyr::mutate(
      subject_course = "CHEM 1215",
      term_type = "spring",
      method_label = unname(CEDAR_ENROLLMENT_PROJECTION_METHODS[method_id]),
      applicable = TRUE,
      raw_projected_classlist_total = dplyr::if_else(
        method_id == "seasonal_last", 200, 210
      ) + dplyr::row_number(),
      actual_classlist_total = c(205, 215, 225)[match(
        target_term, c(202410L, 202510L, 202610L)
      )],
      # Spring 2025 carries no status dates: its first day is a gap.
      actual_first_day = dplyr::if_else(
        target_term == 202510L, NA_real_, actual_classlist_total - 5
      ),
      actual_census = actual_classlist_total - 10,
      actual_final_enrollment = actual_classlist_total - 15
    )

  plot <- build_enrollment_projection_method_history_plot(
    history, selected_method_id = "spine_adjusted"
  )
  built <- plotly::plotly_build(plot)
  trace_names <- vapply(built$x$data, function(trace) trace$name, character(1))

  expect_s3_class(plot, "plotly")
  # Four lifecycle actuals and the two candidates, the selected one marked.
  expect_equal(length(trace_names), 6L)
  expect_snapshot(cat(trace_names, sep = "\n"))
  first_day_trace <- built$x$data[[grep("^First day", trace_names)]]
  expect_true(is.na(first_day_trace$y[[2]]))

  mixed <- dplyr::bind_rows(
    history,
    dplyr::mutate(history[1, ], term_type = "fall", target_term = 202480L)
  )
  expect_error(
    build_enrollment_projection_method_history_plot(mixed),
    "must contain one term type"
  )
})

# ISSUES.md M35. Five published forecasts of 100 for one course; each range is
# rebuilt from the earlier misses only (80th percentile, type 7):
#   fold  actual  miss  earlier misses   half-width  seats   held?
#   1     90      +10   none             --          --      not scored
#   2     110     -10   10               10          +2%     yes
#   3     95       +5   10, 10           10          +5%     yes
#   4     130     -30   10, 10, 5        10          +30%    no, actual above
#   5     100       0   10, 10, 5, 30    18          -3%     yes
# A sixth fold the rule did not publish is never read.
test_that("the range's rolling coverage is reported by whether seats held", {
  backtests <- tibble::tibble(
    market_id = "abq_ea_course_market", subject_course = "TEST 101",
    term_type = "fall", target_term = seq(202080L, by = 100L, length.out = 6),
    policy_selected = c(rep(TRUE, 5), FALSE),
    projected_classlist_total = 100,
    actual_classlist_total = c(90, 110, 95, 130, 100, 40),
    fold_seat_change = c(NA, 0.02, 0.05, 0.30, -0.03, 0)
  )
  coverage <- summarize_projection_range_coverage(backtests)
  expect_equal(coverage$seats, c("steady", "moved", "unknown"))
  expect_equal(coverage$folds, c(3L, 1L, 0L))
  expect_equal(coverage$covered, c(3L, 0L, 0L))
  expect_equal(coverage$actual_above, c(0L, 1L, 0L))
  expect_equal(coverage$coverage, c(1, 0, NA))

  summary <- projection_range_coverage_summary(backtests, list())
  none <- projection_range_coverage_summary(backtests[1, ], list())
  # Held against moved, and where the misses fell; one fold shows nothing.
  expect_snapshot({
    cat(summary$sentence, "\n\n")
    cat(none$sentence, "\n")
  })
  expect_error(
    summarize_projection_range_coverage(dplyr::select(backtests, -fold_seat_change)),
    "fold_seat_change"
  )
})

test_that("the draft comparison separates short of day one from short of the plan", {
  projections <- tibble::tibble(
    market_id = "abq_ea_course_market",
    subject_course = c("DAY 1", "PLAN 1", "COVER 1", "SPARE 1", "MISSING 1"),
    department = "TEST",
    projected_classlist_total = 100,
    planned_registrations = 110, pressure_bump = 10, plan_feeder_adjustment = 0,
    projected_first_day_equivalent = 90,
    recommended_sections = 4L, reference_section_size = 30,
    scheduled_sections = c(2L, 3L, 4L, 7L, 0L),
    # DAY 1 is short of day one by less than a section (30 of 90) and of the
    # plan by two (50 of 110), so the two section counts differ.
    scheduled_capacity = c(60, 100, 115, 200, 0),
    target_schedule_available = c(TRUE, TRUE, TRUE, TRUE, FALSE),
    additional_sections = c(2L, 1L, 0L, 0L, NA),
    target_registration_observed = FALSE, target_registered_now = NA_real_,
    accuracy = "High", accuracy_value = "5.0% off",
    # SPARE 1's Low rating was set by its seats, so it displays grey.
    reliability_tone = c("High", "High", "High", "neutral", "High"),
    reliability_label = c(rep("5.0% off", 3), "5.0% off · set by seats", "5.0% off"),
    seat_consistency = "High", seat_consistency_value = "seats moved in 0 of 4",
    # Last year's registrations, and whether last year was near full: DAY 1
    # and SPARE 1 were, so the draft's seats have their own answer there.
    observed_baseline = c(96, 100, 100, 100, 100),
    adjusted_saturated_prior = c(TRUE, FALSE, NA, TRUE, TRUE)
  )
  components <- tibble::tibble(
    market_id = "abq_ea_course_market", subject_course = "DAY 1",
    campus = c("ABQ", "EA"), part_term = "1", scheduled_sections = c(1L, 1L)
  )
  # Last year's seats: DAY 1 had 80 (1.2 registrations per seat), SPARE 1 had
  # 100; the rest are not needed, and MISSING 1 has no history row at all.
  history <- tibble::tibble(
    market_id = "abq_ea_course_market",
    subject_course = c("DAY 1", "DAY 1", "PLAN 1", "COVER 1", "SPARE 1"),
    recency_rank = c(1L, 2L, 1L, 1L, 1L),
    scheduled_capacity = c(80, 70, 90, 110, 100)
  )
  view <- list(
    projections = projections, delivery_components = components,
    history = history,
    meta = list(target_schedule_as_of = as.Date("2026-10-08"),
                target_term_label = "Spring 2027")
  )
  draft <- build_enrollment_projection_draft_comparison(view)
  table <- draft$table

  # If the draft's seats fill as last year's did: DAY 1's 60 seats at 1.2 per
  # seat hold 72; SPARE 1's 200 at 1.0 hold 200. A course that had seats to
  # spare (PLAN 1), one whose fill is unknown (COVER 1) and one not in the
  # draft (MISSING 1) get no such number: their registrations did not follow
  # their seats, or there are no seats to follow.
  expect_equal(table$if_seats_fill[table$course == "DAY 1"], 72)
  expect_equal(table$if_seats_fill[table$course == "SPARE 1"], 200)
  expect_true(all(is.na(table$if_seats_fill[table$course %in% c("PLAN 1", "COVER 1", "MISSING 1")])))
  # modifyList() would merge a tibble's columns into the old one; replace it.
  no_seats <- view
  no_seats$history <- dplyr::select(history, -scheduled_capacity)
  expect_error(build_enrollment_projection_draft_comparison(no_seats), "scheduled_capacity")

  expect_true(draft$available)
  expect_equal(table$course, c("DAY 1", "PLAN 1", "MISSING 1", "COVER 1", "SPARE 1"))
  expect_equal(table$status,
               c("short_day_one", "short_plan", "not_in_draft", "covers", "spare"))
  # Draft seats less the plan: negative is short.
  expect_equal(table$draft_vs_plan, c(-50, -10, NA, 5, 90))
  expect_equal(table$campus_sections[[1]], "ABQ 1 \u00b7 EA 1")
  # The ratings travel with the numbers behind them, and with the table's
  # display of them.
  expect_equal(unique(table$reliability_value), "5.0% off")
  expect_equal(unique(table$seat_consistency_value), "seats moved in 0 of 4")
  expect_equal(table$reliability_tone[table$course == "SPARE 1"], "neutral")
  expect_equal(table$reliability_label[table$course == "SPARE 1"], "5.0% off · set by seats")
  expect_equal(table$reliability_label[table$course == "DAY 1"], "5.0% off")

  # No schedule for the target term: says so instead of an empty table.
  none <- build_enrollment_projection_draft_comparison(list(
    projections = dplyr::mutate(projections, target_schedule_available = FALSE),
    delivery_components = components[0, ], history = history,
    meta = list(target_schedule_as_of = as.Date(NA), target_term_label = "Spring 2027")
  ))
  expect_false(none$available)
  expect_true(all(is.na(none$table$if_seats_fill)))

  # The figure's counts: one course per verdict, most urgent first, with the
  # course not in the draft listed last because there is one.
  expect_equal(draft$parts$status,
               c("short_day_one", "short_plan", "covers", "spare", "not_in_draft"))
  expect_equal(draft$parts$n, rep(1L, 5))
  expect_equal(sum(draft$parts$n), nrow(table))
  # The draft's 475 seats against the 440 registrations planned in the four
  # courses it holds; and for DAY 1 and SPARE 1, near full last year, the 272
  # their seats would hold against the 220 planned for the two.
  expect_equal(draft$meters$id, c("seats", "if_seats_fill"))
  expect_equal(draft$meters$value, c(475, 272))
  expect_equal(draft$meters$planned, c(440, 220))
  expect_equal(draft$meters$share, c(475 / 440, 272 / 220))
  # A draft every course is in lists the four verdicts and no fifth; a verdict
  # no course has stays listed at zero, with no gap to state.
  all_in_view <- view
  all_in_view$projections <- projections[2:4, ]
  all_in <- build_enrollment_projection_draft_comparison(all_in_view)
  expect_equal(all_in$parts$status, c("short_day_one", "short_plan", "covers", "spare"))
  expect_equal(all_in$parts$n, c(0L, 1L, 1L, 1L))
  expect_true(is.na(all_in$parts$detail[[1]]))
  # No course near full last year: only the seats are set against the plan.
  spare_view <- view
  spare_view$projections <- projections[2:3, ]
  expect_equal(build_enrollment_projection_draft_comparison(spare_view)$meters$id, "seats")
  # No schedule: nothing to draw.
  expect_equal(nrow(none$meters), 0L)
  expect_equal(none$parts$n[none$parts$status == "not_in_draft"], nrow(none$table))

  # Each course's verdict (day-one and plan shortfalls in seats and sections;
  # one course takes a singular verb), the sentence over the five with the
  # near-full courses' seats at last year's fill, the figure's words, and no
  # schedule at all.
  expect_snapshot({
    cat(paste0(table$course, ": ", table$verdict), sep = "\n")
    cat("\n", draft$sentence, "\n\n", sep = "")
    cat(draft$headline, draft$caption, "|", draft$scope, "\n")
    cat(paste(draft$parts$n, draft$parts$label, draft$parts$detail, sep = " | "), sep = "\n")
    cat(paste0(draft$meters$label, ": ", draft$meters$text), sep = "\n")
    cat("\n", all_in$headline, " ", all_in$caption, "\n\n", sep = "")
    cat(none$sentence, "\n")
  })
})

test_that("reliability reads grey 'set by seats' when the schedule set the past numbers", {
  shown <- projection_reliability_display(
    accuracy = c("Low", "Moderate", "Low", "High", "Unrated", "Moderate"),
    accuracy_value = c("32.8% off", "15.0% off", "25.0% off", "4.0% off", "Unrated", "12.0% off"),
    miss_cause = c("seats", "seats", "forecast", "seats", NA, "unknown")
  )
  # Low or Moderate with the schedule's miss: neutral, labelled. A close
  # forecast stays High whatever the seats did; the forecast's own miss and
  # an unknown cause keep their rating colour.
  expect_equal(shown$reliability_tone,
               c("neutral", "neutral", "Low", "High", "Unrated", "Moderate"))
  expect_equal(shown$reliability_label,
               c("32.8% off · set by seats", "15.0% off · set by seats",
                 "25.0% off", "4.0% off", "Unrated", "12.0% off"))

  bundle <- projection_fixture_bundle(202110L, 202080L, 202080L)
  view <- build_enrollment_projection_view(bundle, list(group_id = "all_saved"))
  expect_true(all(c("reliability_tone", "reliability_label") %in% names(view$table)))
  expect_equal(view$meta$n_bundle_rows, nrow(bundle$projections))
  expect_gte(view$meta$n_bundle_rows, view$meta$n_rows)
  # The designed class lists are dated, so no recent term is undated.
  expect_equal(view$meta$undated_terms, character(0))
  expect_match(view$meta$track_record$headline, "^(Past .*forecasts were|No past forecasts)")
})

test_that("a recent term with no first-day count for any course is named, not shown as dashes", {
  history <- tibble::tibble(
    history_term = c(202310L, 202310L, 202410L, 202410L, 202510L, 202510L),
    history_term_label = rep(c("Spring 2023", "Spring 2024", "Spring 2025"), each = 2L),
    subject_course = rep(c("A 1", "B 1"), 3L),
    actual_first_day = c(90, 80, NA, NA, NA, 75),
    actual_classlist_total = c(100, 90, 110, 95, 0, 80)
  )
  # Spring 2024: both courses offered, neither first day known. Spring 2025:
  # A 1 was not offered (no students), B 1's first day is known, so the term
  # is not undated. Spring 2023 is complete.
  expect_equal(projection_undated_history_terms(history), "Spring 2024")
  expect_equal(projection_undated_history_terms(history[0, ]), character(0))
  expect_error(projection_undated_history_terms(dplyr::select(history, -actual_first_day)),
               "actual_first_day")
})

test_that("standalone feature builder runs without Shiny or global data", {
  settled_students <- test_students %>%
    dplyr::mutate(as_of_date = .cedar_term_start(term) + 30L)
  cl <- calc_cl_enrls(settled_students, by_part_term = TRUE)
  bundle <- build_enrollment_projection_bundle(
    cl_enrls = cl,
    sections = test_sections,
    students = settled_students,
    student_terms = test_student_terms,
    target_term = 202110L,
    as_of_term = 202080L,
    scope_courses = "MATH 1215Z",
    scope_campuses = "ABQ",
    scope_market_id = "abq_course_market",
    force_courses = "MATH 1215Z",
    opt = list(history_start_term = 202080L),
    built_at = as.POSIXct("2026-08-15 12:00:00", tz = "UTC")
  )

  expect_true(validate_enrollment_projection_bundle(bundle))
  expect_equal(bundle$target_term, 202110L)
  expect_equal(bundle$as_of_term, 202080L)
  expect_equal(bundle$scope_campuses, "ABQ")
  expect_equal(bundle$scope_market_id, "abq_course_market")
  expect_equal(bundle$model_config$saturation_fill_threshold, 0.90)
  expect_equal(bundle$model_config$selection_min_backtests, 3L)
  expect_equal(bundle$model_config$history_start_term, 202080L)
  expect_equal(
    bundle$model_provenance$model_version,
    CEDAR_ENROLLMENT_PROJECTION_MODEL_VERSION
  )
  expect_equal(
    bundle$model_provenance$schema_version,
    CEDAR_ENROLLMENT_PROJECTION_SCHEMA_VERSION
  )
  expect_true(nrow(bundle$pressure_screen) >= 1)
  expect_equal(nrow(bundle$projections), sum(bundle$pressure_screen$included))
  expect_equal(
    anyDuplicated(bundle$projections[c("market_id", "subject_course", "target_term")]),
    0L
  )
  expect_false("campus" %in% names(bundle$projections))
  expect_equal(
    nrow(bundle$projections),
    dplyr::n_distinct(bundle$projections$subject_course)
  )
  expect_true(all(bundle$delivery_components$campus == "ABQ"))
  expect_true(any(bundle$source_fingerprint$sections$last_term == 202110L))
  expect_lte(bundle$source_fingerprint$classlist_enrollments$last_term, 202110L)
  expect_true(all(bundle$candidates$target_term == 202110L))
  expect_true(all(c("selected", "n_backtests", "wape") %in% names(bundle$candidates)))
  expect_true(all(c(
    "observed_baseline", "adjusted_projection", "selection_common_n",
    "capacity_data_quality", "floor_note", "regime_note"
  ) %in% names(bundle$projections)))
})

# Course Dynamics > Projections shows one course's saved outlook per bundle,
# through the Projections page's own view, and says why a course has none
# rather than showing an empty panel.
test_that("Course Dynamics reads one course's outlook off the saved bundle and says why a course has none", {
  bundle <- projection_fixture_bundle(202080L, 202060L, 201980L)

  projected <- enrollment_projection_course_outlook(bundle, "MATH 1215Z")
  expect_equal(projected$status, "projected")
  expect_null(projected$sentence)
  expect_equal(projected$meta$target_term, 202080L)
  expect_equal(projected$detail$current$subject_course, "MATH 1215Z")
  # The same detail the Projections page opens for the course.
  page_detail <- enrollment_projection_course_detail(
    build_enrollment_projection_view(bundle, list(group_id = "all_saved")),
    "MATH 1215Z"
  )
  expect_equal(projected$detail$current, page_detail$current)
  expect_equal(projected$detail$plan_steps, page_detail$plan_steps)

  # Outside every monitored group: no detail, and the sentence says so.
  outside <- enrollment_projection_course_outlook(bundle, "ENGL 1110")
  expect_equal(outside$status, "out_of_scope")
  expect_null(outside$detail)

  # Monitored, but left out by the saved pressure screen: its saved reason.
  screened <- bundle
  screened$scope_courses <- c(screened$scope_courses, "TEST 999")
  screened$pressure_screen <- dplyr::bind_rows(
    screened$pressure_screen,
    projection_test_row %>%
      dplyr::mutate(subject_course = "TEST 999") %>%
      dplyr::mutate(
        market_id = bundle$scope_market_id, target_term = 202080L,
        # No delivery components for it, so no scheduled seats to reconcile.
        scheduled_sections = 0L, scheduled_capacity = 0,
        is_forced = FALSE, included = FALSE,
        inclusion_reason = "0 of 3 recent fall terms at or above 90% of scheduled capacity"
      )
  )
  expect_true(validate_enrollment_projection_bundle(screened))
  left_out <- enrollment_projection_course_outlook(screened, "TEST 999")
  expect_equal(left_out$status, "screened_out")
  expect_null(left_out$detail)

  # In scope with no saved row at all: said, never shown as an empty detail.
  unpublished <- bundle
  unpublished$scope_courses <- c(unpublished$scope_courses, "TEST 998")
  no_row <- enrollment_projection_course_outlook(unpublished, "TEST 998")
  expect_equal(no_row$status, "unpublished")
  # Outside the groups; screened out, with the saved reason; no saved row.
  expect_snapshot({
    cat(outside$sentence, "\n\n")
    cat(left_out$sentence, "\n\n")
    cat(no_row$sentence, "\n")
  })

  expect_error(enrollment_projection_course_outlook(bundle, NULL), "one subject_course")
  expect_error(
    enrollment_projection_course_outlook(bundle, c("MATH 1215Z", "ENGL 1110")),
    "one subject_course"
  )
})

test_that("the Day-1 fill column names last year's fill, who waited, and why a fill is unknown", {
  # Five courses' saved fields, as the bundle holds them: an analytical frame,
  # not institutional data.
  rows <- tibble::tibble(
    spine_term = c(202610L, 202610L, 202610L, 202510L, 202610L),
    adjusted_saturated_prior = c(TRUE, TRUE, FALSE, NA, NA),
    adjusted_prior_first_day_fill = c(0.988, 0.93, 0.72, NA, NA),
    adjusted_prior_first_day_basis = c("complete", "complete", "complete",
                                       "undated", NA),
    adjusted_waitlisted_prior = c(15L, 0L, 0L, NA, NA)
  )
  fill <- projection_prior_fill(rows, header_term = 202610L)
  # 98.8% is full, not merely near full, and shown with one decimal: whole
  # percents turned it into "99%". The two levels are the seat-fill constants.
  expect_equal(fill$prior_fill_text,
               c("Full · 98.8%", "Near full · 93.0%", "72.0%", "Unknown", NA))
  # The table shows the number, with the level beneath it.
  expect_equal(fill$prior_fill_percent, c("98.8%", "93.0%", "72.0%", "Unknown", NA))
  expect_equal(fill$prior_fill_level, c("Full", "Near full", NA, NA, NA))
  expect_equal(fill$prior_fill_note, c("15 waiting", NA, NA, "no status dates", NA))
  expect_equal(fill$prior_fill, c(0.988, 0.93, 0.72, NA, NA))
  # A course starting from an older term than the header's says which.
  expect_equal(fill$prior_fill_term, c(NA, NA, NA, "Spring 2025", NA))
  expect_true(all(is.na(projection_prior_fill(rows)$prior_fill_term)))
  # Every recorded cause of an unknown fill is named (ISSUES.md I28).
  causes <- projection_prior_fill(dplyr::mutate(
    rows[c(4, 4, 4, 4), ],
    adjusted_prior_first_day_basis = c("undated", "sessions_pending", "no_capacity",
                                       "no_start_date")
  ))
  expect_equal(causes$prior_fill_note,
               c("no status dates", "a session had not begun", "no seat count",
                 "a section has no start date"))
  expect_error(projection_prior_fill(dplyr::select(rows, -spine_term)), "spine_term")
})

test_that("each rating is shown as the number behind it", {
  rows <- tibble::tibble(
    stability = c("Moderate", "Unrated"), history_cv = c(0.157, NA),
    depth = c("Deep", "None"), n_backtests = c(4L, NA),
    accuracy = c("Moderate", "Unrated"), wape = c(0.10408922, NA),
    seat_consistency = c("Moderate", "Unrated"),
    seat_consistency_moves = c(1L, 0L), seat_consistency_terms = c(4L, 0L)
  )
  values <- projection_axis_values(rows)
  # The same 10.4% the summary sentence and plan steps state.
  expect_equal(values$accuracy_value, c("10.4% off", "Unrated"))
  expect_equal(values$seat_consistency_value, c("seats moved in 1 of 4", "Unrated"))
  expect_equal(values$stability_value, c("15.7% variation", "Unrated"))
  expect_equal(values$depth_value, c("4 past forecasts", "None"))
  expect_equal(projection_axis_values(rows[c(1, 1), ] %>%
                 dplyr::mutate(n_backtests = c(1L, 2L)))$depth_value,
               c("1 past forecast", "2 past forecasts"))
})

test_that("the view adds a needs-a-look filter without changing a number", {
  bundle <- projection_fixture_bundle(202110L, 202080L, 202080L)
  view <- build_enrollment_projection_view(bundle, list(group_id = "all_saved"))

  expect_true(all(c("planning_sections", "expected_first_day", "demand_range",
                    "flags", "recent_first_day", "recent_sections",
                    "recent_terms",
                    "summary_sentence", "attention") %in% names(view$table)))
  expect_equal(view$table$expected_first_day, view$projections$projected_first_day_equivalent)
  expect_equal(view$table$planning_sections, view$projections$recommended_sections)
  expect_equal(view$meta$n_attention, sum(view$projections$attention))
  # The campus history is saved per delivery campus, inside the saved scope,
  # for each recent term; Spring 2020 is in the window when it opens there.
  history_bundle <- projection_fixture_bundle(202110L, 202080L, 202010L)
  expect_gt(nrow(history_bundle$recent_campus_history), 0L)
  expect_true(all(history_bundle$recent_campus_history$campus %in% history_bundle$scope_campuses))
  expect_setequal(history_bundle$recent_campus_history$history_term,
                  history_bundle$recent_history$history_term)
  history_view <- build_enrollment_projection_view(history_bundle, list(group_id = "all_saved"))
  expect_true(all(history_view$campus_history$subject_course %in% history_view$projections$subject_course))
  # A draft that moves the seats 10% or more from last year's same term says
  # the range assumes steady seats; one within 10% says nothing.
  last <- history_bundle$recent_history %>% dplyr::filter(recency_rank == 1L)
  drafted <- history_bundle
  drafted$projections <- drafted$projections %>%
    dplyr::left_join(
      dplyr::select(last, subject_course, last_capacity = scheduled_capacity),
      by = "subject_course"
    ) %>%
    dplyr::mutate(
      projection_low = 10, projection_high = 30,
      target_schedule_available = TRUE,
      scheduled_capacity = c(1.5, rep(1.05, dplyr::n() - 1L)) * last_capacity
    ) %>%
    dplyr::select(-last_capacity)
  drafted_view <- build_enrollment_projection_view(drafted, list(group_id = "all_saved"))
  moved_course <- drafted$projections$subject_course[[1]]
  moved_note <- drafted_view$table$range_note[drafted_view$table$course == moved_course]
  expect_match(moved_note, last$history_term_label[last$subject_course == moved_course],
               fixed = TRUE)
  expect_true(all(is.na(drafted_view$table$range_note[drafted_view$table$course != moved_course])))
  expect_snapshot({
    cat(moved_note, "\n\n")
    cat(drafted_view$meta$range_coverage$sentence, "\n")
  })
  broken <- history_bundle
  broken$recent_campus_history <- dplyr::bind_rows(
    broken$recent_campus_history, broken$recent_campus_history[1, ]
  )
  expect_error(validate_enrollment_projection_bundle(broken), "Campus history")

  # The range is in registrations, the unit sections are sized from. The
  # fixture has too few aftcasts for an interval, so one is set on row 1;
  # its first-day range is narrower and must not be what the page shows.
  ranged_bundle <- bundle
  ranged_bundle$projections$projection_low[[1]] <- 1100
  ranged_bundle$projections$projection_high[[1]] <- 1300
  ranged_bundle$projections$projection_low_first_day_equivalent[[1]] <- 990
  ranged_bundle$projections$projection_high_first_day_equivalent[[1]] <- 1170
  ranged <- build_enrollment_projection_view(
    ranged_bundle, list(group_id = "all_saved")
  )
  course <- ranged_bundle$projections$subject_course[[1]]
  expect_equal(ranged$table$demand_range[ranged$table$course == course], "1,100 to 1,300")
  expect_true(all(is.na(ranged$table$demand_range[ranged$table$course != course])))

  flagged <- build_enrollment_projection_view(
    bundle, list(group_id = "all_saved", attention_only = TRUE)
  )
  expect_true(all(flagged$projections$attention))
  expect_lte(nrow(flagged$projections), nrow(view$projections))
})
