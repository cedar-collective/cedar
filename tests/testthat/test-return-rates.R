# RR01 (fixtures/scenario_tables.R): four falls of ABQ freshmen, EA
# sophomores, graduating seniors and graduate students, and a Fall 2024 whose
# return is not yet observable. rr01$dashboard is the page's payload over it
# (minimum 5 a rate; courses with 10 takers and 5 DFW).

test_that("RR01: a degree that term and an unsettled next term stay out of the rate, counted", {
  r <- get_return_rates(rr01$student_terms, list(term_type = "fall", student_level = "UG", data_edges = rr01_edges))$rates
  expect_equal(r$term, c(202080L, 202180L, 202280L, 202380L, 202480L))
  expect_equal(r$n_enrolled, c(62L, 62L, 62L, 62L, 10L))
  expect_equal(r$n_graduated, c(2L, 2L, 2L, 2L, 0L))
  expect_equal(r$n_unobservable, c(0L, 0L, 0L, 0L, 10L))
  expect_equal(r$n_observable, c(60L, 60L, 60L, 60L, 0L))
  expect_equal(r$n_returned, c(43L, 45L, 47L, 49L, 0L))
  expect_equal(r$return_pct, c(100 * c(43, 45, 47, 49) / 60, NA))
})

test_that("RR01: the level scope keeps graduate students out, and every level reads them", {
  all_levels <- get_return_rates(rr01$student_terms, list(term_type = "fall", data_edges = rr01_edges))$rates
  expect_equal(all_levels$n_observable[1:4], rep(65L, 4))
  expect_equal(all_levels$n_returned[1:4], c(48L, 50L, 52L, 54L))
})

test_that("RR01: each home campus is its own row, and a small one gets no rate", {
  r <- get_return_rates(rr01$student_terms, c(list(term_type = "fall", student_level = "UG", data_edges = rr01_edges), list(group_cols = "student_campus", min_n = 25L)))$rates
  fall20 <- r[r$term == 202080L, ]
  expect_equal(fall20$student_campus, c("ABQ", "EA"))
  expect_equal(fall20$n_observable, c(40L, 20L))
  expect_equal(fall20$n_returned, c(28L, 15L))
  expect_equal(fall20$return_pct, c(70, NA))
})

test_that("RR01: the DFW sign is unknown without a posted grade and past the graded edge", {
  r <- get_return_rates(rr01$student_terms, c(list(term_type = "fall", student_level = "UG", data_edges = rr01_edges), list(group_cols = "dfw")))$rates
  fall22 <- r[r$term == 202280L, ]
  expect_equal(fall22$dfw, c(FALSE, TRUE, NA))
  expect_equal(fall22$n_observable, c(52L, 7L, 1L))
  expect_equal(fall22$n_returned, c(45L, 2L, 0L))
  # Fall 2023 is past the graded edge (Fall 2022): every student-term unknown.
  fall23 <- r[r$term == 202380L, ]
  expect_equal(nrow(fall23), 1L)
  expect_true(is.na(fall23$dfw))
  expect_equal(fall23$n_observable, 60L)
})

test_that("RR01: a late withdrawal is any course dropped after census", {
  r <- get_return_rates(rr01$student_terms, c(list(term_type = "fall", student_level = "UG", data_edges = rr01_edges), list(group_cols = "late_withdrawal")))$rates
  fall23 <- r[r$term == 202380L, ]
  expect_equal(fall23$late_withdrawal, c(FALSE, TRUE))
  expect_equal(fall23$n_observable, c(54L, 6L))
  expect_equal(fall23$n_returned, c(49L, 0L))
})

test_that("get_return_rates() stops on an unknown group, a missing edge or a missing column", {
  st <- rr01$student_terms
  expect_error(get_return_rates(st, c(list(term_type = "fall", student_level = "UG", data_edges = rr01_edges), list(group_cols = "major"))), "group_cols")
  expect_error(get_return_rates(st, list(term_type = "fall")), "settled enrollment edge")
  expect_error(get_return_rates(st, list(group_cols = "dfw",
                                         data_edges = list(last_enrolled_complete = 202480L))), "last_graded")
  expect_error(get_return_rates(dplyr::select(st, -degree_awarded), list(term_type = "fall", student_level = "UG", data_edges = rr01_edges)), "degree_awarded")
})

test_that("RR01: the dashboard's signs compare with and without, and share the non-returners", {
  p <- rr01$dashboard
  expect_equal(p$series$term, c(202080L, 202180L, 202280L, 202380L))
  latest <- p$signs_latest
  lw <- latest[latest$sign == "late_withdrawal", ]
  expect_equal(lw$term, 202380L)
  expect_equal(c(lw$n_with, lw$returned_with, lw$n_without, lw$returned_without), c(6L, 0L, 54L, 49L))
  expect_equal(lw$share_of_nonreturners_pct, 100 * 6 / 11)
  # The DFW sign's latest known term is the graded edge's, Fall 2022.
  dfw <- latest[latest$sign == "dfw", ]
  expect_equal(dfw$term, 202280L)
  expect_equal(c(dfw$n_with, dfw$returned_with, dfw$n_without, dfw$returned_without), c(7L, 2L, 52L, 45L))
  expect_equal(dfw$share_of_nonreturners_pct, 100 * 5 / 12)
})

test_that("RR01: each college is its own series, and without the declarations there are no semesters", {
  g <- rr01$dashboard$groups
  expect_setequal(paste(g$dimension, g$group), c("college AS", "college EN"))
  expect_null(rr01$dashboard$stages)
  expect_equal(rr01$dashboard$meta$n_groups_past, 0L)
})

test_that("RT02: a semester counts the regular terms since the latest arrival, enrolled or not", {
  s <- student_term_semesters(rt02$student_terms, rt02$programs)
  got <- stats::setNames(s$semester_here, paste(s$student_id, s$term))
  expect_equal(got[c("A 202080", "A 202110", "A 202180")], c(`A 202080` = 1L, `A 202110` = 2L, `A 202180` = 3L))
  # A summer start: the summer has no semester; the fall after is the 1st.
  expect_true(is.na(got[["B 202060"]]))
  expect_equal(got[c("B 202080", "B 202110")], c(`B 202080` = 1L, `B 202110` = 2L))
  # Away for a year and back: terms passed count.
  expect_equal(got[["C 202280"]], 5L)
  # Left and came back as a new transfer: the count starts again.
  expect_equal(s$entry_type[s$student_id == "D"], c("first_time", "transfer"))
  expect_equal(got[c("D 202110", "D 202280")], c(`D 202110` = 4L, `D 202280` = 1L))
  # No arrival on record, or a row before the arrival: no row.
  expect_false(any(c("E 202080", "G 202010") %in% names(got)))
  expect_equal(got[["G 202080"]], 1L)
  # Recorded both ways in one term: first-time.
  expect_equal(s$entry_type[s$student_id == "F"], "first_time")
  expect_equal(got[c("H 202110", "H 202180")], c(`H 202110` = 1L, `H 202180` = 2L))
  # An arrival counts only at its own level.
  expect_equal(got[["I 202180"]], 3L)
  expect_false("I 202480" %in% names(got))
  expect_equal(got[["J 202310"]], 2L)
  expect_equal(s$entry_type[s$student_id == "J"], "transfer")
  expect_error(student_term_semesters(dplyr::select(rt02$student_terms, -term), rt02$programs), "term")
  expect_error(student_term_semesters(rt02$student_terms, dplyr::select(rt02$programs, -student_level)), "student_level")
  expect_error(student_term_semesters(rt02$student_terms, dplyr::mutate(rt02$programs, student_level = "Postdoctoral")),
               "Postdoctoral")
})

test_that("RT02: a semester's earliest start is that many regular terms back, a fall's summer before it", {
  expect_equal(semester_earliest_arrival(c(202080L, 202110L, 202110L, 202180L, 202380L, 202280L), c(1L, 1L, 2L, 3L, 8L, 5L)),
               c(202060L, 202110L, 202060L, 202060L, 202010L, 202060L))
  # Every RT02 row's arrival is on or after its semester's earliest start.
  s <- student_term_semesters(rt02$student_terms, rt02$programs) %>% dplyr::filter(!is.na(semester_here))
  expect_true(all(s$arrived_term >= semester_earliest_arrival(s$term, s$semester_here)))
  expect_equal(retention_semester_label(1:2, 202110L), c("1st semester (spring start)", "2nd semester"))
  expect_equal(retention_semester_label(1:2, 202180L), c("1st semester", "2nd semester (spring start)"))
  expect_error(semester_earliest_arrival(202060L, 1L), "falls or springs")
  expect_error(semester_earliest_arrival(202080L, 0L), "semesters 1 or more")
})

test_that("RT01: each semester since arrival to the 8th is a line, each term read at min_n", {
  st <- rt01$dashboard$stages
  first <- st$series[st$series$entry_type == "first_time", ]
  # The 2nd semester never reaches min_n; the 7th is not read in the latest
  # fall; the 10th is after the last drawn.
  expect_equal(sort(unique(first$stage)), c(1L, 3L, 5L, 8L))
  # A fall's 8th semester started in a spring, and says so.
  expect_equal(unique(first$stage_label[first$stage == 8L]), "8th semester (spring start)")
  expect_equal(unique(first$stage_label[first$stage == 1L]), "1st semester")
  expect_equal(first$n_returned[first$stage == 8L], rep(5L, 4))
  expect_equal(st$arrivals_from, 201610L)
  expect_equal(first$return_pct[first$stage == 1L], c(70, 74, 78, 82))
  expect_equal(first$return_pct[first$stage == 5L], c(92, 86, 80, 74))
  ft <- st$trend[st$trend$entry_type == "first_time", ]
  expect_equal(stats::setNames(ft$direction, ft$stage),
               c(`1` = "rising", `3` = "steady", `5` = "falling", `8` = "steady"))
  expect_equal(st$n_past$n_past[st$n_past$entry_type == "first_time"], 1L)
  # Transfer students are their own lines.
  tr <- st$series[st$series$entry_type == "transfer", ]
  expect_equal(unique(tr$stage), 1L)
  expect_equal(tr$return_pct, rep(75, 4))
  # The overall series still counts every student, those with no start on record included.
  expect_equal(rt01$dashboard$series$n_observable, c(469L, 469L, 459L, 459L))
})

test_that("RT01: a semester's term is read only when the arrival records reach back to its earliest start", {
  st <- retention_stage_series(rt01$by_semester, 5L, 202380L, arrivals_from = 202160L)
  first <- st$series[st$series$entry_type == "first_time", ]
  # Records from Summer 2021: Fall 2020 reaches no semester; Fall 2021 the 1st
  # (its summer starters are recorded); the 3rd from Fall 2022, the 5th in
  # Fall 2023; the 8th never.
  expect_equal(first$term[first$stage == 1L], c(202180L, 202280L, 202380L))
  expect_equal(first$term[first$stage == 3L], c(202280L, 202380L))
  expect_equal(first$term[first$stage == 5L], 202380L)
  expect_false(8L %in% first$stage)
  # Fall 2020's 459, then Fall 2021's 3rd, 5th, 7th, 8th and 2nd (219), Fall
  # 2022's 5th and 8th (106), Fall 2023's 8th (6).
  expect_equal(st$unplaced$n_before_records, 790L)
  expect_equal(st$unplaced$n_beyond, 24L)
  expect_error(retention_stage_series(rt01$by_semester, 5L, 202380L, arrivals_from = Inf), "one term code")
  expect_error(retention_stage_series(dplyr::mutate(rt01$by_semester, term = dplyr::if_else(term == 202080L, 202110L, term)),
                                      5L, 202380L, 201610L), "one term type")
})

test_that("RT01: students with no start on record are counted apart, never dropped unsaid", {
  st <- rt01$dashboard$stages
  expect_equal(st$unplaced$n_no_start, 16L)
  expect_equal(st$unplaced$n_beyond, 24L)
  expect_equal(st$unplaced$n_before_records, 0L)
  # Every student is in a line, the 7th's and 2nd's left out (20 and 12),
  # after the 8th, or has no start.
  expect_equal(st$unplaced$n_no_start + st$unplaced$n_beyond + sum(st$series$n_observable) + 20L + 12L,
               sum(rt01$dashboard$series$n_observable))
  expect_error(retention_stage_series(rt01$dashboard$series, 5L, 202380L, 201610L), "entry_type")
  expect_error(plot_return_stages(rr01$dashboard, "first_time"), "no semester is read")
})

test_that("RT01: the sentence names the semester students come back least often after, and the semesters moving", {
  testthat::local_edition(3)
  st <- rt01$dashboard$stages
  steady <- st
  steady$trend$direction <- "steady"
  few <- st
  few$trend$direction <- "too_few_terms"
  # The 8th semester lowest every fall: its students started in a spring.
  spring_low <- st
  spring_low$series$return_pct[spring_low$series$stage == 8L] <- 10
  expect_snapshot(cat(retention_stage_sentence(st, "first_time", "fall"), retention_stage_sentence(st, "transfer", "fall"),
                      retention_stage_sentence(steady, "first_time", "fall"),
                      retention_stage_sentence(few, "first_time", "fall"),
                      retention_stage_sentence(spring_low, "first_time", "fall"), sep = "\n"))
  expect_identical(retention_stage_sentence(NULL, "first_time", "fall"), character(0))
})

test_that("RT01: the chart draws a semester a line, breaking it at a term not read", {
  # The 3rd semester not read in Fall 2021.
  p <- rt01$dashboard
  p$stages$series <- p$stages$series[!(p$stages$series$stage == 3L & p$stages$series$term == 202180L), ]
  traces <- plotly::plotly_build(plot_return_stages(p, "first_time"))$x$data
  names <- vapply(traces, function(t) t$name, character(1))
  expect_equal(names, c("Every student together", "1st semester", "3rd semester", "5th semester", "8th semester (spring start)"))
  third <- traces[[which(names == "3rd semester")]]
  # A missing point between Fall 2020 and Fall 2022: the line does not join them.
  x <- unname(as.character(unlist(third$x)))
  y <- unlist(lapply(third$y, function(v) if (is.null(v)) NA else v))
  expect_equal(x[!is.na(x)], c("Fall 2020", "Fall 2022", "Fall 2023"))
  expect_equal(is.na(y), c(FALSE, TRUE, FALSE, FALSE))
  expect_false(isTRUE(third$connectgaps))
  # A count narrower than the others in its line is not padded on hover.
  p$stages$series$n_returned[p$stages$series$stage == 1L & p$stages$series$term == 202080L] <- 9L
  first <- plotly::plotly_build(plot_return_stages(p, "first_time"))$x$data[[2]]
  expect_false(any(grepl("  ", unlist(first$hovertext))))
  p$series$n_returned[[1]] <- 9L
  overall <- plotly::plotly_build(plot_return_series(p))$x$data[[1]]
  expect_false(any(grepl("  ", unlist(overall$hovertext))))
  # Transfer students' chart is their own semesters.
  transfer <- plotly::plotly_build(plot_return_stages(rt01$dashboard, "transfer"))$x$data
  expect_equal(vapply(transfer, function(t) t$name, character(1)), c("Every student together", "1st semester"))
})

test_that("RT01: the dashboard as text carries each semester's line and who has none", {
  testthat::local_edition(3)
  lines <- format_retention_dashboard(rt01$dashboard)
  expect_snapshot(cat(lines[grepl("semester|no start", lines)], sep = "\n"))
})

test_that("RR01: a scope with no student to read is an empty payload, not an error", {
  p <- build_retention_dashboard(rr01$student_terms, rr01$attempts, NULL, list(
    term_type = "fall", student_level = "UG", campus = "LA", data_edges = rr01_edges, min_n = 5L))
  expect_equal(nrow(p$series), 0L)
  expect_null(p$groups)
  expect_null(p$courses$listed)
  expect_match(format_retention_dashboard(p)[[3]], "no student in this scope")
})

test_that("RS01: the page says who it counts: the level's students by how they started, other levels left out", {
  who <- retention_scope_facts(rs01$student_terms, rs01$programs, rs01$opt, 202280L)
  expect_equal(who$n_counted, 7L)
  expect_equal(who$arrivals, c(first_time = 3L, transfer = 2L, not_recorded = 2L))
  # New that fall: W-A and W-G first-time, W-D a transfer; W-B (Fall 2021) and
  # W-C (Spring 2022) started before it.
  expect_equal(who$new_arrivals, c(first_time = 2L, transfer = 1L))
  # A summer starter is in the fall's new class: W-C arriving in Summer 2022.
  summer_start <- rs01$programs %>% mutate(term = if_else(student_id == "W-C" & term == 202210L, 202260L, term))
  summer <- retention_scope_facts(rs01$student_terms, summer_start, rs01$opt, 202280L)
  expect_equal(summer$new_arrivals, c(first_time = 2L, transfer = 2L))
  expect_equal(summer$arrivals, who$arrivals)
  expect_equal(who$other_levels, tibble::tibble(student_level = c("GR", NA), n = c(2L, 1L)))
  # They are the students the return rates count that term.
  rates <- get_return_rates(rs01$returns, c(rs01$opt, list(data_edges = rs01_edges)))$rates
  expect_equal(rates$n_enrolled[rates$term == 202280L], who$n_counted)

  # Every home campus adds the EA transfer student; no level named counts
  # everyone and leaves no level out.
  everywhere <- retention_scope_facts(rs01$student_terms, rs01$programs, list(student_level = "UG"), 202280L)
  expect_equal(c(everywhere$n_counted, everywhere$arrivals[["transfer"]]), c(8L, 3L))
  every_level <- retention_scope_facts(rs01$student_terms, rs01$programs, list(campus = "ABQ"), 202280L)
  expect_equal(every_level$n_counted, 10L)
  expect_equal(nrow(every_level$other_levels), 0L)
  # Graduate students whose start the record does not call first-time or a
  # new transfer (W-H, W-I): none is new or started before, by the record.
  graduate <- retention_scope_facts(rs01$student_terms, rs01$programs, list(student_level = "GR", campus = "ABQ"), 202280L)
  expect_equal(graduate$arrivals, c(first_time = 0L, transfer = 0L, not_recorded = 2L))
  expect_error(retention_scope_facts(rs01$student_terms["student_id"], rs01$programs, rs01$opt, 202280L),
               "student_terms lacks term, enrolled")
  expect_error(retention_scope_facts(rs01$student_terms, rs01$programs["student_id"], rs01$opt, 202280L),
               "programs lacks student_level")

  testthat::local_edition(3)
  expect_snapshot({
    describe_retention_scope(who)
    describe_retention_scope(everywhere)
    describe_retention_scope(every_level)
    describe_retention_scope(graduate)
    cat(retention_who_note(who))
    cat(retention_who_note(graduate))
    cat(retention_who_note(NULL))
  })
})

test_that("RR01: the dashboard describes the latest term it reads, when it has the declarations", {
  p <- build_retention_dashboard(rr01$student_terms, rr01$attempts, NULL, list(
    term_type = "fall", student_level = "UG", data_edges = rr01_edges, min_n = 5L,
    courses = FALSE, milestones = FALSE), programs = rs01$programs)
  latest <- p$series[p$series$term == max(p$series$term), ]
  expect_equal(p$who$term, 202380L)
  expect_equal(p$who$n_counted, latest$n_enrolled)
  # None of RR01's students is in RS01's declarations, and its five graduate
  # students are another level.
  expect_equal(p$who$arrivals[["not_recorded"]], p$who$n_counted)
  expect_equal(p$who$other_levels$n, 5L)
  # The text preview carries the same facts the page's bar shows.
  described <- describe_retention_scope(p$who)
  expect_true(all(paste0("  ", names(described), ": ", described) %in% format_retention_dashboard(p)))
  # Without them the payload says nothing of who, as before.
  expect_null(rr01$dashboard$who)
})

test_that("RR01: the courses read the latest graded falls' students", {
  courses <- rr01$dashboard$courses
  expect_equal(courses$terms, c(202080L, 202180L, 202280L))
  expect_equal(courses$listed$subject_course, "MATH 101")
  expect_equal(courses$listed$campus, "ABQ")
  # The page's students only: the five graduate students a fall who got a
  # DFW in MATH 101 are not among the 21.
  expect_equal(c(courses$listed$pop_n_dfw, courses$listed$pop_n_pass), c(21L, 96L))
  expect_equal(courses$listed$pop_dfw_stopout_rate, 19 / 21)
  # 21 DFW students, 19 not back, against the passers' 8 of 96 not back.
  expect_equal(courses$listed$excess_not_back, 21 * (19 / 21 - 8 / 96))
  # The page's campus is the students' home campus: MATH 101 is taught on ABQ,
  # and no student whose home campus is EA took it.
  ea <- retention_dashboard_course_list(rr01$student_terms, rr01$attempts, NULL, rr01$dashboard$series, list(
    student_level = "UG", campus = "EA", data_edges = rr01_edges, course_min_n = 10L, course_min_dfw_n = 5L))
  expect_equal(NROW(ea$listed), 0L)
})

test_that("RR01: the trend carries its fitted line's ends, the least-squares line through the terms", {
  # plot_return_series() draws the trend from these, so the dashed line is the
  # fit the verdict was read from.
  s <- rr01$dashboard$series
  t <- rr01$dashboard$trend
  fit <- stats::lm(return_pct ~ I(term %/% 100L), data = s)
  expect_equal(t$fit_first_pct, unname(stats::fitted(fit)[1]))
  expect_equal(t$fit_last_pct, unname(stats::fitted(fit)[nrow(s)]))
  expect_equal((t$fit_last_pct - t$fit_first_pct) / ((t$last_term - t$first_term) %/% 100L), t$slope)
})

# RR01's students each hold one term's row (a new id every fall), so every
# entering class reads 0% still enrolled: the text shows the lines are there.
# The arithmetic is EC01's (test-entering-class-retention.R).
test_that("RR01: the dashboard as text", {
  testthat::local_edition(3)
  expect_snapshot(cat(format_retention_dashboard(rr01$dashboard), sep = "\n"))
})

test_that("RR01: the first section's sentence gives the verdict over the terms, and says when too few can be read", {
  testthat::local_edition(3)
  t <- rr01$dashboard$trend[1, , drop = FALSE]
  few <- t
  few$direction <- "too_few_terms"
  few$n_terms <- 2L
  expect_snapshot(cat(retention_lead_sentence(t, "fall"), retention_trend_arithmetic(t),
                      retention_lead_sentence(few, "fall"), sep = "\n"))
})

test_that("SG01: a spring student awarded a degree that summer finished, and is not a student who left", {
  r <- get_return_rates(sg01$student_terms, sg01$opt, sg01$degrees)$rates
  s22 <- r[r$term == 202210L, ]
  expect_equal(c(s22$n_enrolled, s22$n_graduated, s22$n_finished_between, s22$n_applied_between,
                 s22$n_observable, s22$n_returned), c(7L, 4L, 3L, 0L, 3L, 1L))
  # Summer 2023's degrees are not posted: the application stands in, counted apart.
  s23 <- r[r$term == 202310L, ]
  expect_equal(c(s23$n_graduated, s23$n_finished_between, s23$n_applied_between, s23$n_observable, s23$n_returned),
               c(1L, 0L, 1L, 1L, 1L))
  # Without the degrees table only the term's own degree is completion.
  plain <- get_return_rates(sg01$student_terms, sg01$opt)
  expect_equal(c(plain$rates$n_graduated[1], plain$rates$n_observable[1]), c(1L, 6L))
  expect_false(plain$meta$between_terms)
  # A fall's next regular term is the spring: nothing lies between.
  fall <- get_return_rates(sg01$student_terms, utils::modifyList(sg01$opt, list(term_type = "fall")), sg01$degrees)$rates
  expect_equal(sum(fall$n_finished_between + fall$n_applied_between), 0L)
  no_degree_edge <- sg01$opt
  no_degree_edge$data_edges <- list(last_enrolled_complete = 202380L)
  expect_error(get_return_rates(sg01$student_terms, no_degree_edge, sg01$degrees), "degree edge")
})
