# Enrollment projections, the page's words: every sentence, note and label
# a reader sees. Wording is held in snapshots (tests/testthat/_snaps), so a
# wording change is accepted with testthat::snapshot_accept() and reviewed
# as a diff, never re-pinned by hand. Each test asserts the numbers it can.
testthat::local_edition(3)

test_that("the three axes are explained separately and may disagree", {
  # The state the retired single label could not express: a course whose own
  # history is calm, observed only twice, and forecast closely on those two.
  # Stability says "predictable", depth says "barely watched", accuracy says
  # "close so far". All three are true at once.
  explanation <- projection_axis_explanation(
    stability = "Stable", depth = "Thin", accuracy = "High",
    n_backtests = 2L, wape = 0.045, history_terms = 5L, history_cv = 0.04,
    history_median_yoy = 0.03, term_type = "spring"
  )

  # Reader labels: stability is "Own history" and depth is "Evidence", so
  # neither reads as a synonym of Reliability; no WAPE or aftcast jargon.
  expect_snapshot(cat(explanation))
  expect_false(grepl("WAPE|aftcast|Stability|Depth", explanation))

  # A volatile course says so plainly and frames the swing as the finding,
  # rather than reporting it as a failure of the forecast.
  volatile <- projection_axis_explanation(
    stability = "Volatile", depth = "Deep", accuracy = "Low",
    n_backtests = 4L, wape = 0.42, history_terms = 5L, history_cv = 0.55,
    history_median_yoy = 0.48, term_type = "spring"
  )
  expect_snapshot(cat(volatile))
})

test_that("the axis summary stays compact and names the main caveat", {
  brief <- projection_axis_brief(
    stability = "Stable", depth = "Deep", accuracy = "High",
    capacity_constrained = TRUE, methods_disagree = TRUE
  )

  expect_snapshot({
    cat(brief, "\n")
    cat(projection_axis_brief("Stable", "Deep", "High", regime_alarm = TRUE), "\n")
  })
})

# The published rule's record beside doing nothing, from saved aftcasts. Four
# Spring folds for one course, actual 100 each; the rule published prior
# same-season in 2023 and 2025 and the adjusted forecast in 2024 and 2026:
#   fold  seats   default |err|  adjusted |err|  published |err|
#   2023  +2%     10             12              10 (default)
#   2024  +30%    20             15              15 (adjusted)
#   2025  -5%      5              9               5 (default)
#   2026  unknown 29             20              20 (adjusted)
# Published 50 / 400 = 12.5%; prior same-season alone 64 / 400 = 16.0%; with
# seats held (2023, 2025) 15 / 200 = 7.5%, with seats moved (2024) 15 / 100 =
# 15.0%. An unknown seat change is neither held nor moved. The published
# errors are -10, -15, +5, -20: 40 low on 400, so the record says the
# forecasts ran 10% low and why.
test_that("the forecast's record is stated beside last year's number alone", {
  backtests <- tibble::tribble(
    ~target_term, ~method_id,       ~policy_selected, ~error, ~fold_seat_change,
    202310L,      "seasonal_last",  TRUE,             -10,     0.02,
    202310L,      "spine_adjusted", FALSE,            -12,     0.02,
    202410L,      "seasonal_last",  FALSE,            -20,     0.30,
    202410L,      "spine_adjusted", TRUE,             -15,     0.30,
    202510L,      "seasonal_last",  TRUE,               5,    -0.05,
    202510L,      "spine_adjusted", FALSE,              9,    -0.05,
    202610L,      "seasonal_last",  FALSE,            -29,     NA,
    202610L,      "spine_adjusted", TRUE,             -20,     NA
  ) %>%
    dplyr::mutate(market_id = "m", subject_course = "TEST 101",
                  term_type = "spring", actual_classlist_total = 100,
                  abs_error = abs(error))
  record <- projection_track_record_summary(backtests, list())
  expect_equal(record$n_folds, 4L)
  expect_equal(record$wape, 50 / 400)
  expect_equal(record$default_wape, 64 / 400)
  expect_equal(record$held_folds, 2L)
  expect_equal(record$held_wape, 15 / 200)
  expect_equal(record$moved_folds, 1L)
  expect_equal(record$moved_wape, 15 / 100)
  expect_equal(record$bias, -40 / 400)
  # A record that ran high says so without the full-course explanation, and
  # one within a point of even says nothing about direction.
  high <- projection_track_record_summary(
    dplyr::mutate(backtests, error = -error), list()
  )
  expect_equal(high$bias, 40 / 400)
  even <- projection_track_record_summary(
    dplyr::mutate(backtests, error = dplyr::if_else(target_term == 202610L, 20, error)),
    list()
  )
  expect_equal(even$bias, 0)
  expect_false(grepl("on average: a course", even$sentence, fixed = TRUE))
  none <- projection_track_record_summary(backtests[0, ], list())
  # The words, as the page shows them: held against moved, the published
  # forecast against last year's number alone, the direction and why.
  expect_snapshot({
    cat("sentence:", record$sentence, "\n\n")
    cat("headline:", record$headline, "\n\n")
    cat("ran high:", high$sentence, "\n\n")
    cat("even:", even$sentence, "\n\n")
    cat("none saved:", none$sentence, "\n")
  })
  # Comparing the rule with doing nothing needs doing nothing on every term.
  expect_error(
    projection_track_record_summary(
      dplyr::filter(backtests, !(target_term == 202410L & method_id == "seasonal_last")),
      list()
    ),
    "1 published past forecasts have no prior same-season aftcast"
  )
})

test_that("the ledger of ideas tried is complete and in the page's words", {
  ledger <- enrollment_projection_attempts_ledger()
  expect_equal(names(ledger), c("idea", "result", "status"))
  expect_gte(nrow(ledger), 10L)
  expect_false(any(is.na(ledger) | ledger == ""))
  # The one idea the rules forbid and the one that is next are both listed,
  # so a reader finds them before asking.
  expect_true(any(ledger$status == "Next"))
  expect_snapshot(cat(paste0(ledger$status, " | ", ledger$idea), sep = "\n"))
})

# Reader-facing text says last year's registrations, the students still
# waiting, a change, a sharp change, and a count that stopped at its seats;
# the model's internal names are for the code. Checked on the sentence-like
# string literals (those with a space) of the page's files, comments aside.
test_that("the projections page carries no model jargon in its text", {
  jargon <- "\\b(spine|floor|delta|deltas|regime|aftcast|aftcasts|saturated|saturation|capped)\\b"
  files <- c(
    "R/modules/enrollment-projections.R",
    "R/lists/enrollment_projection_groups.R"
  )
  for (file in files) {
    lines <- readLines(file.path(cedar_base_dir, file), warn = FALSE)
    lines <- lines[!grepl("^\\s*#", lines)]
    strings <- unlist(regmatches(lines, gregexpr('"[^"]*\\s[^"]*"', lines)))
    hits <- strings[grepl(jargon, strings, ignore.case = TRUE)]
    expect_equal(hits, character(0), info = file)
  }
})

test_that("students left waiting in the term just finished are flagged from half a section and stated for every course", {
  # Four Spring 2027 rows with sections of 24: 12 and 11 left waiting in Fall
  # 2026, none, and a term that kept no waitlist rows.
  rows <- tibble::tibble(
    subject_course = c("A 1", "B 1", "C 1", "D 1"),
    target_term = 202710L, adjusted_preceding_term = 202680L,
    adjusted_waitlisted_preceding = c(12L, 11L, 0L, NA),
    adjusted_feeder_check = "measured", reference_section_size = 24
  )
  # Half a section of 24 is 12.
  expect_equal(projection_waiting_flags(rows, list()),
               c("12 left waiting in Fall 2026", NA, NA, NA))
  expect_equal(projection_waiting_flags(rows, list(preceding_waiting_flag_sections = 0.25)),
               c("12 left waiting in Fall 2026", "11 left waiting in Fall 2026", NA, NA))
  # Counts of different widths are not padded to the widest: format() on the
  # vector once gave " 12 left waiting" beside "101 left waiting".
  expect_equal(
    projection_waiting_flags(dplyr::mutate(rows, adjusted_waitlisted_preceding = c(1012L, 12L, 0L, NA)), list()),
    c("1,012 left waiting in Fall 2026", "12 left waiting in Fall 2026", NA, NA)
  )
  notes <- projection_waiting_notes(rows)
  summary <- projection_preceding_waiting_summary(rows)
  expect_equal(summary$students, 23)
  expect_equal(summary$n_courses, 2L)
  # Each course's note (waiting, waiting, none, no rows kept) and the summary.
  expect_snapshot({
    cat(notes, sep = "\n")
    cat("\n", summary$sentence, "\n", sep = "")
  })

  # A Fall target two steps out: Spring 2027 has not happened.
  ahead <- dplyr::mutate(
    rows, target_term = 202780L, adjusted_preceding_term = 202710L,
    adjusted_waitlisted_preceding = NA_integer_,
    adjusted_feeder_check = "term_not_observed"
  )
  unseen <- projection_preceding_waiting_summary(ahead)$sentence
  expect_true(all(is.na(projection_waiting_flags(ahead, list()))))
  # Every note says what the summary says.
  expect_true(all(projection_waiting_notes(ahead) == unseen))
  expect_snapshot(cat(unseen))
})

test_that("the administrator summary says the decision in one sentence and flags why to look", {
  row <- tibble::tibble(
    subject_course = "TEST 101", term_type = "spring",
    projected_classlist_total = 2179, projected_first_day_equivalent = 2080,
    pressure_bump = 218, pressure_bump_applied = TRUE,
    pressure_bump_note = "Pressure bump +218: near full in every recent Spring",
    plan_feeder_adjustment = 0, planned_registrations = 2397,
    recommended_sections = 99L, observed_baseline = 2179,
    adjusted_saturated_prior = TRUE, adjusted_prior_first_day_fill = 0.988,
    adjusted_prior_first_day_basis = "complete", campus_fill_flag = NA_character_,
    waiting_flag = NA_character_,
    adjusted_waitlisted_prior = 15L, adjusted_regime_alarm = FALSE,
    adjusted_preceding_term = 202680L, adjusted_preceding_term_change = 0.02,
    stability = "Moderate", accuracy = "Moderate", wape = 0.1004,
    seat_consistency = "Unrated", miss_cause = NA_character_,
    methods_disagree = FALSE
  )
  sentence <- projection_summary_sentence(row)
  expect_false(grepl("No pressure bump", sentence))

  # The feeder adjustment is stated beside the bump, either way.
  fed <- projection_summary_sentence(dplyr::mutate(
    row, plan_feeder_adjustment = -60, planned_registrations = 2337
  ))

  # A full course denied the bump says why.
  denied <- dplyr::mutate(
    row, pressure_bump = 0, pressure_bump_applied = FALSE,
    planned_registrations = 2179,
    pressure_bump_note = "No pressure bump: Spring 2026 filled 85.0% of its seats"
  )
  denied_sentence <- projection_summary_sentence(denied)
  # The change is the forecast's, named as such: after "Plan ... for 2,397
  # registrations", "That is last year's level" read as though the plan were.
  expect_false(grepl("That is", sentence))
  # A capped count understates demand; it is no floor under this year's
  # (ISSUES.md I42).
  expect_false(grepl("floor", sentence))
  # ISSUES.md I42: the term just finished can take a capped course below last
  # year's count, and the sentence says both. ENGL 1120, Spring 2027: 2,179
  # last Spring, Fall 2026's changes take it to 2,164, the bump adds 109. A
  # change under 1% keeps a decimal, so 2,164 against 2,179 is not "1%" off,
  # nor 716 against 719 (CHEM 1215) a match.
  lower <- projection_summary_sentence(dplyr::mutate(
    row, projected_classlist_total = 2164, pressure_bump = 109,
    planned_registrations = 2273, projected_first_day_equivalent = 2058
  ))
  # The course's own error, as its plan step states it: a Moderate course at
  # 10.0% once read "averaged 10 to 20% off" above a step saying 10.0%.
  expect_false(grepl("10 to 20", sentence))
  low <- projection_summary_sentence(dplyr::mutate(row, accuracy = "Low", wape = 0.264))
  unrated <- projection_summary_sentence(
    dplyr::mutate(row, accuracy = "Unrated", wape = NA_real_)
  )
  # A flag says what no column does. Last year's fill and its waiting
  # students are the Day-1 fill column, so a full course carries no flag:
  # when they were flags, 10 of the 11 monitored Spring 2027 courses had one.
  expect_equal(projection_flags(row), "")
  expect_equal(
    projection_flags(dplyr::mutate(row, campus_fill_flag = "EA full in Spring 2026, ABQ had room")),
    "EA full in Spring 2026, ABQ had room"
  )
  expect_error(projection_flags(dplyr::select(row, -campus_fill_flag)), "campus_fill_flag")
  expect_equal(
    projection_flags(dplyr::mutate(row, waiting_flag = "42 left waiting in Fall 2026")),
    "42 left waiting in Fall 2026"
  )
  expect_error(projection_flags(dplyr::select(row, -waiting_flag)), "waiting_flag")

  moved <- dplyr::mutate(
    row, adjusted_saturated_prior = FALSE, adjusted_waitlisted_prior = 0L,
    adjusted_regime_alarm = TRUE, adjusted_preceding_term_change = 0.91,
    projected_classlist_total = 2400, pressure_bump = 0,
    pressure_bump_applied = FALSE, planned_registrations = 2400,
    pressure_bump_note = "No pressure bump: Fall 2026 filled 80.0% of its seats",
    stability = "Volatile", accuracy = "Low"
  )
  moved_sentence <- projection_summary_sentence(moved)
  # Far off as a full course's seats changed is the schedule's, so it is no
  # flag; far off with seats to spare is the forecast's own miss, which no
  # column says, so it is, whatever the seats did.
  expect_equal(projection_flags(moved), "Fall 2026 enrollment +91%")
  expect_equal(
    projection_flags(dplyr::mutate(moved, miss_cause = "seats")),
    "Fall 2026 enrollment +91%"
  )
  expect_equal(
    projection_flags(dplyr::mutate(moved, miss_cause = "forecast")),
    "Fall 2026 enrollment +91% | Off 20%+ with seats to spare"
  )
  expect_equal(
    projection_flags(dplyr::mutate(moved, miss_cause = "forecast", accuracy = "Moderate")),
    "Fall 2026 enrollment +91%"
  )
  # A Fall target read one step ahead compares against the Spring just
  # finished, and the flag names it (ISSUES.md I41).
  expect_equal(
    projection_flags(dplyr::mutate(moved, adjusted_preceding_term = 202710L)),
    "Spring 2027 enrollment +91%"
  )
  # A volatile history warns only when there is no track record to read.
  expect_equal(
    projection_flags(dplyr::mutate(moved, accuracy = "Unrated")),
    "Fall 2026 enrollment +91% | Hard to predict"
  )
  expect_equal(
    projection_flags(dplyr::mutate(moved, methods_disagree = TRUE, adjusted_regime_alarm = FALSE)),
    "Candidates disagree"
  )

  sparse <- dplyr::mutate(row, projected_classlist_total = NA_real_)
  # Every sentence the page can show for this row, in its words: the plan and
  # how much of it is the bump, with the first-day seats read off the
  # projection rather than the bumped plan; the feeder adjustment beside the
  # bump; a bump denied, and why; the forecast's change from last Spring at
  # one decimal; last Spring's fill (98.8%, not "99%") and who waited; the
  # course's own error; a sharp change; and too little history.
  expect_snapshot({
    cat("full:", sentence, "\n\n")
    cat("with feeders:", fed, "\n\n")
    cat("bump denied:", denied_sentence, "\n\n")
    cat("below last year:", lower, "\n\n")
    cat("low reliability:", low, "\n\n")
    cat("unrated:", unrated, "\n\n")
    cat("sharp change:", moved_sentence, "\n\n")
    cat("sparse:", projection_summary_sentence(sparse), "\n")
  })
})

test_that("the page says which of the worst misses the schedule set and names the forecast's own", {
  config <- list(accuracy_fair_max_wape = 0.20)
  rows <- tibble::tibble(
    subject_course = c("ENGL 1110", "FYEX 1010", "FYEX 1110", "MATH 1220", "BIOL 1140"),
    accuracy = c("Low", "Low", "Low", "High", "Moderate"),
    miss_cause = c("seats", "seats", "forecast", "forecast", "seats")
  )
  # More than five of the forecast's own are counted, not listed.
  many <- tibble::tibble(subject_course = paste("C", 1:6), accuracy = "Low",
                         miss_cause = "forecast")
  # Mixed causes, naming the forecast's own; all the schedule's ("None was
  # the forecast's own" is the finding, so it is said); an unknown cause;
  # many of the forecast's own; none off; one course; and the threshold read
  # live from the model.
  expect_snapshot({
    cat(projection_miss_sentence(rows, config), "\n\n")
    cat(projection_miss_sentence(rows[1:2, ], config), "\n\n")
    cat(projection_miss_sentence(dplyr::mutate(rows[1, ], miss_cause = NA), config), "\n\n")
    cat(projection_miss_sentence(many, config), "\n\n")
    cat(projection_miss_sentence(rows[4:5, ], config), "\n\n")
    cat(projection_miss_sentence(rows[4, ], config), "\n\n")
    cat(projection_miss_sentence(rows, list(accuracy_fair_max_wape = 0.25)), "\n")
  })
  expect_error(projection_miss_sentence(rows, list()), "accuracy_fair_max_wape")
  expect_error(projection_miss_sentence(dplyr::select(rows, -miss_cause), config), "miss_cause")

  # The same finding as the figure's parts: every course shown in one group.
  # Of the five, two Low the schedule set, one Low the forecast's own, and
  # two within the threshold (High and Moderate, whatever their cause).
  summary <- projection_miss_summary(rows, config)
  expect_equal(summary$parts$part, c("seats", "forecast", "within"))
  expect_equal(summary$parts$n, c(2L, 1L, 2L))
  expect_equal(sum(summary$parts$n), nrow(rows))
  expect_equal(summary$n_low, 3L)
  expect_equal(summary$sentence, projection_miss_sentence(rows, config))
  # None the forecast's own is the finding, so its part stays at zero; with no
  # Low course there is no such part to show.
  schedule_only <- projection_miss_summary(rows[1:2, ], config)
  expect_equal(schedule_only$parts$part, c("seats", "forecast"))
  expect_equal(schedule_only$parts$n, c(2L, 0L))
  expect_equal(projection_miss_summary(rows[4:5, ], config)$parts$part, "within")
  # A Low course whose cause the data cannot tell, and a course with too few
  # past forecasts to rate, are their own parts, not folded into another.
  mixed <- projection_miss_summary(
    dplyr::mutate(rows, accuracy = c("Low", "Low", "Low", "High", "Unrated"),
                  miss_cause = c("seats", NA, "forecast", "forecast", NA)),
    config
  )
  expect_equal(mixed$parts$part, c("seats", "forecast", "unknown", "within", "unrated"))
  expect_equal(mixed$parts$n, rep(1L, 5))
  expect_error(
    projection_miss_summary(dplyr::mutate(rows, accuracy = NA_character_), config),
    "accuracy is missing for 5"
  )
  # The figure's words: the headline, each part with its note (the forecast's
  # own named, or counted when more than five), and the threshold read live.
  many_parts <- projection_miss_summary(many, config)$parts
  one <- projection_miss_summary(rows[4, ], list(accuracy_fair_max_wape = 0.25))
  expect_snapshot({
    cat(summary$headline, summary$caption, "\n")
    cat(paste(mixed$parts$n, mixed$parts$label, mixed$parts$detail, sep = " | "), sep = "\n")
    cat(paste(many_parts$n, many_parts$label, many_parts$detail, sep = " | "), sep = "\n")
    cat(one$headline, one$caption, "\n")
    cat(paste(one$parts$n, one$parts$label, one$parts$detail, sep = " | "), sep = "\n")
  })
})

test_that("a plan's steps add up from last year's class list to its sections", {
  # One published row as the view holds it: the function's input contract.
  # Spring 2027 target: 200 registered last Spring, 6 still waiting, Fall
  # changes of +3.4 (retakes), -6.8 (listed predecessor) and +1.2 (feeders),
  # so the adjusted forecast is round(200 + 6 - 2.2) = 204.
  row <- tibble::tibble(
    term_type = "spring", method_id = "spine_adjusted",
    spine = 200, spine_term = 202610L, floor_uplift = 6,
    delta_repeat = 3.4, delta_sequence = -6.8, delta_feeder = 1.2,
    adjusted_sequence_courses = "SEQ 1", adjusted_preceding_term = 202680L,
    projected_classlist_total = 204, accuracy = "High", wape = 0.068,
    n_backtests = 4L, backtest_term_range = "Spring 2023 to Spring 2026",
    plan_feeder_adjustment = 0, plan_feeder_note = "No feeder adjustment",
    pressure_bump = 10,
    pressure_bump_note = "Pressure bump +10: near full on the first day in every recent Spring",
    planned_registrations = 214, reference_section_size = 25,
    recommended_sections = 9L, scheduled_sections = 8L,
    target_schedule_available = TRUE
  )
  steps <- projection_plan_steps(row)

  expect_equal(steps$label, c(
    "Registered in Spring 2026", "Students still waiting",
    "Enrollment change in Fall 2026", "Forecast registrations",
    "Pressure bump", "Planned registrations", "Sections"
  ))
  expect_equal(steps$kind,
               c("start", "add", "add", "total", "add", "total", "sections"))
  # The arithmetic reads down: each total is the lines above it.
  forecast <- which(steps$label == "Forecast registrations")
  expect_equal(sum(steps$amount[1:(forecast - 1)]), steps$amount[[forecast]])
  planned <- which(steps$label == "Planned registrations")
  expect_equal(sum(steps$amount[forecast:(planned - 1)]), steps$amount[[planned]])
  # Each step's detail, in the page's words: rounded parts (+3, -7, +1) that
  # no longer sum to the change (-2) say so; the course's own error names its
  # terms; the sections line shows its arithmetic and the draft's count.
  expect_snapshot(
    cat(paste0(steps$label, ": ", dplyr::coalesce(steps$detail, "")), sep = "\n")
  )

  # Last year's number with no additions: start, forecast, sections.
  plain <- projection_plan_steps(dplyr::mutate(
    row, method_id = "seasonal_last", projected_classlist_total = 200,
    pressure_bump = 0, planned_registrations = 200, recommended_sections = 8L
  ))
  expect_equal(plain$label,
               c("Registered in Spring 2026", "Forecast registrations", "Sections"))
  # Changes that cancel still show, so the adjusted method's work is visible.
  cancelled <- projection_plan_steps(dplyr::mutate(
    row, floor_uplift = 0, delta_repeat = 2, delta_sequence = -3,
    delta_feeder = 1, projected_classlist_total = 200
  ))
  expect_equal(cancelled$amount[cancelled$label == "Enrollment change in Fall 2026"], 0)
  expect_equal(nrow(projection_plan_steps(
    dplyr::mutate(row, projected_classlist_total = NA_real_)
  )), 0L)
  expect_error(projection_plan_steps(dplyr::select(row, -spine)), "spine")
})

test_that("the feeder summary says how many plans it moved, and why when none", {
  # Published rows as the view holds them: the function's input contract.
  rows <- tibble::tibble(
    term_type = "spring", projected_classlist_total = c(100, 200, 300, 400, NA),
    method_id = c("seasonal_last", "seasonal_last", "seasonal_last",
                  "spine_adjusted", "seasonal_last"),
    plan_feeder_adjustment = c(12, -30, -8, 0, 0),
    adjusted_preceding_term = 202680L, adjusted_feeder_check = "measured"
  )
  summary <- projection_plan_feeder_summary(rows, 0.05, "spring")
  expect_equal(summary$n_raised, 1L)
  expect_equal(summary$n_lowered, 2L)
  expect_equal(summary$registrations, -26)
  still <- projection_plan_feeder_summary(
    dplyr::mutate(rows, plan_feeder_adjustment = 0, method_id = "seasonal_last"), 0.05,
    "spring"
  )
  unseen <- projection_plan_feeder_summary(
    dplyr::mutate(rows, plan_feeder_adjustment = 0, adjusted_feeder_check = "term_not_observed"),
    0.05, "spring"
  )
  # A Fall bundle says the rule, not that its feeders are unobserved.
  fall <- projection_plan_feeder_summary(
    dplyr::mutate(rows, term_type = "fall", plan_feeder_adjustment = 0,
                  adjusted_preceding_term = 202710L,
                  adjusted_feeder_check = "term_not_observed"),
    0.05, "spring"
  )
  # Plans moved, none moved, the term unobserved, and a Fall bundle.
  expect_snapshot({
    cat(summary$sentence, "\n\n")
    cat(still$sentence, "\n\n")
    cat(unseen$sentence, "\n\n")
    cat(fall$sentence, "\n")
  })
  expect_error(projection_plan_feeder_summary(rows, NULL, "spring"), "plan_feeder_change")
  expect_error(projection_plan_feeder_summary(rows, 0.05, NULL), "plan_feeder_seasons")
})
