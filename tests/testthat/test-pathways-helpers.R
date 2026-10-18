context("Pathways branch helpers")

# The population below is intermediate membership scaffolding, not authored raw
# enrollment data. MC02 supplies all course rows, including concurrent labs,
# repeat attempts and a student moving between delivery campuses.
grouped_path_population <- function() {
  test_students_mc %>% distinct(student_id) %>%
    mutate(population_label = "All", relevant_until = NA_integer_)
}
grouped_path_opt <- function(...) {
  modifyList(list(data_edges = list(first_enrolled = 202010L,
    last_enrolled_complete = 202110L), min_n = 1L, min_band_n = 1L), list(...))
}

test_that("grouped paths count concurrent same-category courses once per student and campus", {
  p <- get_grouped_student_paths(test_students_mc, grouped_path_population(),
    CEDAR_PATHWAY_SUBJECT_GROUPS, grouped_path_opt())
  first <- p$cells %>% filter(relative_term == 1, group_id == "languages")
  expect_equal(first$n_students[first$campus == "ABQ"], 4L)
  expect_equal(first$n_students[first$campus == "GA"], 2L)
  second <- p$cells %>% filter(relative_term == 2, campus == "ABQ", group_id == "languages")
  expect_equal(second$n_students, 4L)
  expect_equal(second$n_eligible, 5L)
  # Campus filtering must not re-anchor MC_G1 at term 1 after moving to ABQ.
  scoped <- get_grouped_student_paths(test_students_mc, grouped_path_population(),
    CEDAR_PATHWAY_SUBJECT_GROUPS, grouped_path_opt(campus = "ABQ"))
  expect_equal(scoped$cells, filter(p$cells, campus == "ABQ"))
  expect_equal(nrow(filter(p$courses, subject_course == "SPAN 201", campus == "ABQ")), 2L)
})

test_that("grouped paths suppress thin bands and cells without leaking their counts", {
  p <- get_grouped_student_paths(test_students_mc, grouped_path_population(),
    CEDAR_PATHWAY_SUBJECT_GROUPS, grouped_path_opt(min_n = 3L, min_band_n = 4L))
  thin_band <- p$cells %>% filter(campus == "GA" | relative_term == 3)
  expect_true(all(is.na(thin_band$n_students)))
  expect_true(all(is.na(thin_band$n_eligible)))
  thin_cell <- p$cells %>% filter(campus == "ABQ", relative_term == 2, group_id == "humanities")
  expect_true(thin_cell$cell_suppressed)
  expect_true(is.na(thin_cell$pct_students))
  expect_true(is.na(thin_cell$n_students))
  expect_false(any(p$courses$subject_course == "PHIL 105"))
  expect_false("student_id" %in% names(p$courses))
  expect_true(all(p$courses$n_students >= 3 & p$courses$n_eligible >= 4))
})

test_that("grouped paths honor population ceilings and the settled observation edge", {
  pop <- grouped_path_population()
  pop$relevant_until[pop$student_id == "MC_A1"] <- 202010L
  p <- get_grouped_student_paths(test_students_mc, pop, CEDAR_PATHWAY_SUBJECT_GROUPS,
    grouped_path_opt(data_edges = list(first_enrolled = 202010L, last_enrolled_complete = 202080L)))
  second <- p$cells %>% filter(campus == "ABQ", relative_term == 2, group_id == "languages")
  expect_equal(second$n_students, 3L)
  expect_false(any(p$cells$relative_term > 2))
  expect_error(get_grouped_student_paths(test_students_mc, pop, CEDAR_PATHWAY_SUBJECT_GROUPS,
    list(data_edges = list())), "settled enrollment edge")
  partial <- CEDAR_PATHWAY_SUBJECT_GROUPS %>% filter(subject_code != "PHIL")
  unmapped <- get_grouped_student_paths(test_students_mc, grouped_path_population(), partial, grouped_path_opt())
  expect_equal(unmapped$meta$n_unmapped_rows, 1L)
  expect_true("Unmapped coursework" %in% unmapped$cells$group_label)
})

test_that("catalog trees preserve alternatives, bundles, timing and unresolved source rules", {
  catalog <- CEDAR_DEGREE_CATALOG
  expect_equal(validate_degree_catalog(catalog), catalog)
  r <- degree_rule_outline(catalog, catalog$catalogs$catalog_id)
  intermediate <- r[r$rule_id == "bio-intermediate", ]
  bundle <- r[r$rule_id == "bio-microbiology", ]
  expect_equal(intermediate$operator, "choose_n")
  expect_equal(intermediate$minimum, "3")
  expect_equal(bundle$parent_id, intermediate$rule_id)
  expect_equal(sum(r$parent_id == bundle$rule_id), 2L)
  expect_true(any(r$operator == "concurrent"))
  expect_true(any(r$operator == "prior_or_concurrent"))
  expect_true(any(grepl("SOURCE CONFLICT", r$text, fixed = TRUE)))
  bad <- catalog
  bad$rules$parent_id[1] <- bad$rules$rule_id[1]
  expect_error(validate_degree_catalog(bad), "Cycle")
  bad <- catalog
  bad$rules$minimum[bad$rules$rule_id == "bio-intermediate"] <- "6"
  expect_error(validate_degree_catalog(bad), "Invalid choice group")
  bad <- catalog
  bad$courses$rule_id[1] <- "missing"
  expect_error(validate_degree_catalog(bad), "unknown rule")
})


test_that("pathways_level_filter translates UI values to CEDAR level values", {
  expect_null(pathways_level_filter("all"))
  expect_null(pathways_level_filter(""))
  expect_equal(pathways_level_filter("undergrad"), c("lower", "upper"))
  expect_equal(pathways_level_filter("lower"), "lower")
  expect_equal(pathways_level_filter("upper"), "upper")
  expect_equal(pathways_level_filter("grad"), "grad")
})


test_that("filter_pathways_analysis_population excludes unclear entry rows only for entry split", {
  hist_pop <- build_population(
    test_programs, test_degrees,
    opt = list(type = "preset", program_names = "History", split_by = "entry")
  )

  filtered <- filter_pathways_analysis_population(hist_pop, split_by = "entry")

  expect_true("unclear" %in% hist_pop$entry_method)
  expect_false("unclear" %in% filtered$entry_method)
  expect_lt(nrow(filtered), nrow(hist_pop))
})


test_that("filter_pathways_analysis_population applies selected population label", {
  hist_pop <- build_population(
    test_programs, test_degrees,
    opt = list(type = "preset", program_names = "History", split_by = "transfer")
  )
  label <- hist_pop$population_label[1]

  filtered <- filter_pathways_analysis_population(
    hist_pop, split_by = "transfer", selected_label = label
  )

  expect_true(nrow(filtered) > 0)
  expect_true(all(filtered$population_label == label))
})


test_that("resolve_pathways_focal_dept_codes resolves selected program names", {
  opt <- list(type = "major", program_names = "History")

  dept_codes <- resolve_pathways_focal_dept_codes(opt, test_programs)

  expect_equal(dept_codes, "HIST")
})


test_that("resolve_pathways_focal_subjects uses subject lookup, not dept code as course prefix", {
  opt <- list(type = "dept", dept_code = "GES")

  subjects <- resolve_pathways_focal_subjects(opt, test_programs, test_lookups)

  expect_true("GEOG" %in% subjects)
  expect_false("GES" %in% subjects)
})


test_that("resolve_pathways_gen_ed_courses keeps only focal subject courses", {
  opt <- list(type = "dept", dept_code = "HIST")
  focal_subjects <- resolve_pathways_focal_subjects(opt, test_programs, test_lookups)

  courses <- resolve_pathways_gen_ed_courses(focal_subjects)

  expect_true(length(courses) > 0)
  expect_true(all(sub(" .*", "", courses) %in% focal_subjects))
})


test_that("pathways_observation_boundary walks back complete regular terms", {
  # One term of follow-up: Fall 2025 outcomes need Spring 2026 complete.
  expect_equal(pathways_observation_boundary(202610L, 1L), 202580L)
  # Two terms of follow-up (e.g. course-pairs max gap = 2).
  expect_equal(pathways_observation_boundary(202510L, 2L), 202410L)
  # Summer input steps back to the prior regular term.
  expect_equal(pathways_observation_boundary(202560L, 1L), 202510L)
  # Zero follow-up = the boundary is the last complete term itself.
  expect_equal(pathways_observation_boundary(202510L, 0L), 202510L)
})

test_that("pathways_observation_boundary returns NULL when the anchor is unknown", {
  expect_null(pathways_observation_boundary(NULL, 1L))
  expect_null(pathways_observation_boundary(NA_integer_, 1L))
})


# =============================================================================
# pathways_coverage_facts() — what the data window can see about a population
# =============================================================================
#
# These counts back an on-screen disclosure, so the failure that matters is
# overstating coverage: a student whose record is bounded at either end must not
# be counted as fully readable.

cov_pop <- function() {
  tibble::tibble(
    student_id = paste0("S", 1:6),
    # S1 starts at the data edge -> truncated. S2 ends at the edge -> censored.
    # S3 is both. S4/S5/S6 sit inside the window -> complete.
    first_unm_term   = c(202010L, 202080L, 202010L, 202080L, 202110L, 202080L),
    last_record_term = c(202310L, 202480L, 202480L, 202310L, 202310L, 202380L)
  )
}

test_that("coverage facts count truncation, censoring and complete records", {
  f <- pathways_coverage_facts(cov_pop(), min_data_term = 202010L, max_data_term = 202480L)

  expect_equal(f$n, 6)
  expect_equal(f$n_truncated, 2)   # S1, S3
  expect_equal(f$n_censored, 2)    # S2, S3
  expect_equal(f$n_complete, 3)    # S4, S5, S6
  expect_equal(f$pct_complete, 50)
})

test_that("a student at the boundary counts as unreadable, not as a clean start", {
  # first_unm_term == min_data_term cannot be distinguished from "started earlier",
  # so it must fall on the truncated side. Counting it as complete would overstate
  # coverage, which is the one direction this must never fail.
  f <- pathways_coverage_facts(
    tibble::tibble(student_id = "S1", first_unm_term = 202010L, last_record_term = 202310L),
    min_data_term = 202010L, max_data_term = 202480L)

  expect_equal(f$n_truncated, 1)
  expect_equal(f$n_complete, 0)
})

test_that("coverage facts return NA rather than a confident zero when bookends are missing", {
  f <- pathways_coverage_facts(
    tibble::tibble(student_id = c("S1", "S2")),
    min_data_term = 202010L, max_data_term = 202480L)

  expect_equal(f$n, 2)
  expect_true(is.na(f$pct_truncated))
  expect_true(is.na(f$n_complete))
})

test_that("an empty population yields NA counts, not zero coverage", {
  f <- pathways_coverage_facts(cov_pop()[0, ], min_data_term = 202010L, max_data_term = 202480L)
  expect_equal(f$n, 0)
  expect_true(is.na(f$pct_truncated))
})

test_that("coverage percentages never exceed 100 or fall below 0", {
  f <- pathways_coverage_facts(cov_pop(), min_data_term = 202010L, max_data_term = 202480L)
  for (p in c(f$pct_truncated, f$pct_censored, f$pct_complete)) {
    expect_gte(p, 0); expect_lte(p, 100)
  }
})


# =============================================================================
# latest_graded_term() — the observation boundary comes from the data
# =============================================================================
#
# Deriving it from term arithmetic on cedar_current_term goes stale (grades land
# weeks after a term ends, and nothing moves the boundary until the config is
# edited) and can overshoot (a config set ahead of the data nominates a term
# with no grades, in which every student reads as stopped out).

graded_students <- function() {
  mk <- function(term, n, graded) tibble::tibble(
    term = rep(as.integer(term), n),
    final_grade = c(rep("A", graded), rep(NA_character_, n - graded))
  )
  dplyr::bind_rows(
    mk(202480, 100, 91),   # complete
    mk(202580, 100, 91),   # complete
    mk(202610, 100, 7),    # grades not posted yet
    mk(202680, 100, 0)     # in progress
  )
}

test_that("the boundary is the last term whose grades are posted", {
  expect_equal(latest_graded_term(graded_students()), 202580L)
})

test_that("a term with a trickle of early grades does not qualify", {
  # Spring 2026 sat at 7% on real data — enough to look non-empty, nowhere near
  # enough to measure a DFW rate against.
  expect_equal(latest_graded_term(graded_students(), min_graded_share = 0.5), 202580L)
  expect_true(latest_graded_term(graded_students()) < 202610L)
})

test_that("the boundary advances on its own once grades land", {
  # The behaviour the arithmetic version could not have: no config edit needed.
  later <- dplyr::bind_rows(
    dplyr::filter(graded_students(), term != 202610L),
    tibble::tibble(term = rep(202610L, 100),
                   final_grade = c(rep("A", 88), rep(NA_character_, 12)))
  )
  expect_equal(latest_graded_term(later), 202610L)
})

test_that("max_term caps the boundary without changing the grade rule", {
  expect_equal(latest_graded_term(graded_students(), max_term = 202510L), 202480L)
})

test_that("no graded term yields NULL rather than a confident guess", {
  ungraded <- tibble::tibble(term = rep(202680L, 10), final_grade = NA_character_)
  expect_null(latest_graded_term(ungraded))
  expect_null(latest_graded_term(graded_students()[0, ]))
})

test_that("missing columns fail loudly", {
  # Delegates to cedar_data_edges(), which owns the schema check.
  expect_error(latest_graded_term(tibble::tibble(term = 202480L)),
               "missing required column")
})

# These are authored curriculum metadata, not invented student/section boundary rows.
test_that("roadmaps expose preparation and propagate prerequisites without moving unrelated courses", {
  c <- CEDAR_DEGREE_CATALOG; r <- CEDAR_DEGREE_ROADMAPS
  baseline <- build_degree_roadmap(c, r, "cs-bs-2026", "calculus", "composition")
  prepared <- build_degree_roadmap(c, r, "cs-bs-2026", "intermediate", "composition")
  semester <- function(view, id) view$nodes$semester[match(id, view$nodes$node_id)]
  expect_equal(semester(baseline, "calc1"), 1L)
  expect_equal(vapply(c("math1215", "math1220", "math1250", "calc1", "calc2", "linear", "numerical"),
    function(id) semester(prepared, id), integer(1), USE.NAMES = FALSE), c(1L, 2L, 3L, 4L, 5L, 6L, 7L))
  expect_equal(semester(prepared, "computing0"), semester(baseline, "computing0"))
  expect_equal(semester(prepared, "java1"), semester(baseline, "java1"))
  expect_false("math1215" %in% baseline$nodes$node_id)
  expect_true(all(prepared$terms$planned_credits <= 16))
  expect_true(all(prepared$terms$other_credits >= 0))
  expect_equal(sum(prepared$nodes$node_id == "calc1"), 1L)
  for (view in list(baseline, prepared)) {
    expect_true(all(vapply(seq_len(nrow(view$links)), function(i) {
      l <- view$links[i, ]
      semester(view, l$to) >= semester(view, l$from) + as.integer(l$timing == "before")
    }, logical(1))))
  }
  expect_error(build_degree_roadmap(c, r, c$catalogs$catalog_id, "calculus", "composition"), "one known degree")
  expect_error(build_degree_roadmap(c, r, "cs-bs-2026", "unknown", "composition"), "known math")
})

test_that("English starting points replace the sequence and paired courses stay together", {
  c <- CEDAR_DEGREE_CATALOG; r <- CEDAR_DEGREE_ROADMAPS
  stretch <- build_degree_roadmap(c, r, "biology-bs-2026", "calculus", "stretch")
  writing <- stretch$nodes[stretch$nodes$track == "english", ]
  expect_equal(writing$code, c("ENGL 1110X", "ENGL 1110Y", "ENGL 1120"))
  expect_equal(writing$semester, 1:3)
  advanced <- build_degree_roadmap(c, r, "biology-bs-2026", "calculus", "composition2")
  expect_equal(advanced$nodes$code[advanced$nodes$track == "english"], "ENGL 1120")
  expect_equal(advanced$nodes$semester[advanced$nodes$track == "english"], 1L)
  complete <- build_degree_roadmap(c, r, "biology-bs-2026", "calculus", "complete")
  expect_false(any(complete$nodes$track == "english"))
  expect_equal(complete$completed_credits, 6)
  expect_equal(sum(complete$terms$planned_credits), 114)
  expect_equal(sum(stretch$nodes$bundle), 2L)
  expect_true(all(stretch$nodes$credits[stretch$nodes$bundle] == 4))
  bad <- r; bad$links$from[1] <- "missing"
  expect_error(validate_degree_roadmaps(bad, c), "endpoint")
  bad <- r; bad$links$to[1] <- bad$links$from[1]
  expect_error(validate_degree_roadmaps(bad, c), "Cycle")
})

# Authored template perturbation exercises a plan extending past four years.
test_that("the semester board extends rather than dropping delayed courses", {
  r <- CEDAR_DEGREE_ROADMAPS
  r$nodes$semester[r$nodes$catalog_id == "cs-bs-2026" & r$nodes$node_id == "linear"] <- "8"
  view <- build_degree_roadmap(CEDAR_DEGREE_CATALOG, r, "cs-bs-2026", "intermediate", "stretch")
  expect_equal(view$nodes$semester[view$nodes$node_id == "numerical"], 9L)
  expect_equal(tail(view$terms$semester, 1), 9L)
  expect_equal(nrow(view$nodes), 33L)
  expect_match(format_degree_explorer_preview(build_degree_roadmap_view(
    CEDAR_DEGREE_CATALOG, r, "cs-bs-2026", "intermediate", "stretch")), "Semester 9", fixed = TRUE)
})


# Authored metadata exercises the planner; no student/domain boundary rows are invented.
test_that("all degree starting scenarios budget other requirements without exceeding 16 credits", {
  c <- CEDAR_DEGREE_CATALOG; r <- CEDAR_DEGREE_ROADMAPS
  expect_true(all(r$plans$normal_load == "15" & r$plans$max_load == "16"))
  for (id in c$catalogs$catalog_id) {
    for (math in r$starts$start_id[r$starts$track == "math"]) {
      for (english in r$starts$start_id[r$starts$track == "english"]) {
        v <- build_degree_roadmap(c, r, id, math, english)
        expect_true(all(v$terms$planned_credits <= 16))
        expect_equal(v$terms$planned_credits, v$terms$known_credits + v$terms$other_credits)
        expect_equal(sum(v$terms$planned_credits), v$degree_credits - v$completed_credits + v$preparation_credits)
        expect_true(all(v$terms$other_credits <= pmax(0, 16 - v$terms$known_credits)))
        expect_true(all(v$nodes$semester[v$nodes$course_level == "upper"] >= 5L))
        expect_true(all(v$nodes$semester[match(v$links$to, v$nodes$node_id)] >=
          v$nodes$semester[match(v$links$from, v$nodes$node_id)] + as.integer(v$links$timing == "before")))
        expect_true(all(v$terms$other_phase[v$terms$semester < 5L] == "foundation"))
        expect_true(all(v$terms$other_phase[v$terms$semester >= 5L] == "advanced"))
        expect_false(anyDuplicated(paste(v$nodes$semester, v$nodes$row)) > 0L)
        writing <- v$nodes$row[v$nodes$row_group == "writing"]
        expect_lte(length(unique(writing)), 1L)
      }
    }
  }
  v <- build_degree_roadmap(c, r, "cs-bs-2026", "intermediate", "stretch")
  expect_equal(sum(v$terms$planned_credits), 137)
  expect_gt(nrow(v$terms), 8L)
  expect_equal(sum(v$nodes$credits), sum(v$terms$known_credits))
})

test_that("course-family alignment preserves scheduling and handles parallel courses", {
  c <- CEDAR_DEGREE_CATALOG; r <- CEDAR_DEGREE_ROADMAPS
  v <- build_degree_roadmap(c, r, "physics-bs-2026", "intermediate", "stretch")
  row <- function(ids) v$nodes$row[match(ids, v$nodes$node_id)]
  expect_equal(length(unique(row(c("englX", "englY", "engl2")))), 1L)
  expect_equal(length(unique(row(c("math1215", "math1220", "math1250", "calc1", "physcalc2", "physcalc3")))), 1L)
  expect_equal(row("physem1"), row("physem2"))
  expect_equal(row("physquantum1"), row("physquantum2"))
  expect_false(row("physem1") == row("physquantum1"))
  expect_false(row("physode") == row("physlinear"))
  # Layout metadata cannot change credit budgets, course timing or graph metrics.
  r$nodes$row_group <- "one_family"
  alternate <- build_degree_roadmap(c, r, "physics-bs-2026", "intermediate", "stretch")
  fields <- c("node_id", "semester", "credits", "n_prerequisites", "n_downstream")
  expect_equal(v$nodes[fields], alternate$nodes[fields])
  expect_equal(v$terms, alternate$terms)
  r$nodes$row_group[1] <- ""
  expect_error(validate_degree_roadmaps(r, c), "row group")
})

test_that("new program examples use the appropriate math route and retain catalog provenance", {
  c <- CEDAR_DEGREE_CATALOG; r <- CEDAR_DEGREE_ROADMAPS
  noncalculus <- c("history-ba-2026", "philosophy-ba-2026", "business-bba-2026", "anthropology-ba-2026")
  expect_true(all(c(noncalculus, "physics-bs-2026") %in% c$catalogs$catalog_id))
  for (id in noncalculus) {
    v <- build_degree_roadmap(c, r, id, "intermediate", "composition")
    expect_equal(v$nodes$code[v$nodes$track == "math"], c("MATH 1215", "MATH 1350"))
    expect_equal(v$nodes$semester[v$nodes$track == "math"], 1:2)
    expect_equal(v$preparation_credits, 3)
    expect_false(any(c("calc1", "math1250", "math1220") %in% v$nodes$node_id))
    ready <- build_degree_roadmap(c, r, id, "algebra", "composition")
    expect_equal(ready$math_target$semester, 1L)
    expect_equal(ready$n_preparation, 0L)
    expect_equal(ready$math_target$basis, if (id == "business-bba-2026") "degree" else "general")
    expect_true(all(v$nodes$evidence_catalog_year == "2026-2027"))
    degree <- v$nodes$basis %in% c("degree", "general")
    expect_true(all(v$nodes$evidence_source_url[degree] == v$catalog$source_url))
    expect_setequal(unname(degree_math_start_choices(r, id)), r$starts$start_id[r$starts$track == "math"])
  }
  physics <- build_degree_roadmap(c, r, "physics-bs-2026", "intermediate", "composition")
  expect_equal(physics$math_target$code, "MATH 1512")
  expect_equal(physics$math_target$semester, 4L)
  expect_gte(nrow(physics$terms), 10L)
  expect_equal(sum(physics$nodes$credits[physics$nodes$track != "english" & physics$nodes$kind != "preparation"]), 83)
  concurrent <- physics$links[physics$links$from == "physcompute" & physics$links$to == "physlinear", ]
  expect_equal(concurrent$timing, "before_or_same")
  expect_false(any(grepl("CSCI", physics$nodes$code))) # PHYS 2415 supplies the computing prerequisite.
  bad <- r; bad$math_routes <- bad$math_routes[-1, ]
  expect_error(validate_degree_roadmaps(bad, c), "math starting routes missing")
  bad <- r; bad$math_routes$node_ids[1] <- "missing"
  expect_error(validate_degree_roadmaps(bad, c), "math route course")
  bad <- r; bad$math_routes$node_ids[bad$math_routes$catalog_id == "history-ba-2026"] <- "calc1"
  expect_error(validate_degree_roadmaps(bad, c), "requirement evidence")
})

test_that("new programs retain major-specific choices, conditions and chains", {
  c <- CEDAR_DEGREE_CATALOG; r <- CEDAR_DEGREE_ROADMAPS
  h <- build_degree_roadmap(c, r, "history-ba-2026", "calculus", "composition")
  expect_equal(sum(h$nodes$credits[h$nodes$catalog_id == "history-ba-2026"]), 36)
  expect_false(any(h$links$to == "historiography"))
  gate <- h$conditions[h$conditions$node_id == "historiography" & h$conditions$kind == "course_count", ]
  expect_equal(gate$minimum, "2")
  expect_setequal(strsplit(gate$eligible_node_ids, "|", fixed = TRUE)[[1]], paste0("histupper", 1:6))
  hist491 <- h$nodes[h$nodes$node_id == "historiography", ]
  expect_equal(hist491$n_prerequisites, 0L)
  expect_equal(hist491$planning_level, "conditional")
  expect_equal(hist491$n_conditions, 2L)
  expect_false(any(h$links$from == "historiography" & h$links$to == "histsenior"))
  p <- build_degree_roadmap(c, r, "philosophy-ba-2026", "calculus", "composition")
  expect_equal(sum(p$nodes$credits[p$nodes$catalog_id == "philosophy-ba-2026"]), 30)
  expect_equal(sum(p$nodes$code == "PHIL 400–499"), 2L)
  a <- build_degree_roadmap(c, r, "anthropology-ba-2026", "calculus", "composition")
  own <- a$nodes$catalog_id == "anthropology-ba-2026"
  expect_equal(sum(a$nodes$credits[own]), 37)
  expect_gte(sum(a$nodes$credits[own & a$nodes$course_level == "upper"]), 18)
  b <- build_degree_roadmap(c, r, "business-bba-2026", "intermediate", "stretch")
  expect_equal(sum(b$nodes$node_id == "engl2"), 1L) # Phase I reuses the English entry route.
  expect_equal(sum(b$links$to == "buscapstone"), 8L)
  capstone <- b$nodes[b$nodes$node_id == "buscapstone", ]
  expect_equal(capstone$planning_level, "red")
  expect_gt(capstone$n_prerequisites, 8L)
  expect_match(b$policy$assumption, "31 credits", fixed = TRUE)
  expect_match(b$policy$assumption, "placement alone", fixed = TRUE)
})

# These are authored planning metadata scenarios, not institutional raw rows.
test_that("upper-level courses and choice groups wait for the later planning stage", {
  c <- CEDAR_DEGREE_CATALOG; r <- CEDAR_DEGREE_ROADMAPS
  b <- build_degree_roadmap(c, r, "biology-bs-2026", "calculus", "composition")
  expect_equal(b$nodes$semester[b$nodes$node_id == "molecular"], 5L)
  expect_true(all(b$nodes$semester[b$nodes$track == "english"] <= 4L))
  expect_true(all(b$nodes$semester[b$nodes$node_id %in% c("bio1", "bio2", "biolab")] <= 4L))
  r$nodes$semester[r$nodes$node_id %in% c("technical1", "software")] <- "1"
  v <- build_degree_roadmap(c, r, "cs-bs-2026", "calculus", "composition")
  expect_gte(v$nodes$semester[v$nodes$node_id == "technical1"], 5L)
  expect_gt(v$nodes$semester[v$nodes$node_id == "software"], v$nodes$semester[v$nodes$node_id == "large"])
  # A changed institution policy must move courses and the allowance labels together.
  r$plans$upper_level_from_semester <- "7"
  v <- build_degree_roadmap_view(c, r, "cs-bs-2026", "calculus", "composition")
  expect_true(all(v$nodes$semester[v$nodes$course_level == "upper"] >= 7L))
  expect_true(all(v$terms$other_label[v$terms$semester < 7L] == "Gen Ed / lower-level electives"))
  expect_true(all(v$terms$other_label[v$terms$semester >= 7L] == "Upper-level / minor / electives"))
  expect_match(v$timing_note, "semester 7", fixed = TRUE)
  expect_true(all(v$terms$planned_credits <= 16))
})

test_that("authored course levels agree with institution numbering bands", {
  c <- CEDAR_DEGREE_CATALOG; r <- CEDAR_DEGREE_ROADMAPS
  # Both numbering lengths use the same band, including an unambiguous component.
  r$nodes$code[r$nodes$node_id == "molecular"] <- "BIOL 3010"
  r$courses$subject_course[r$courses$node_id == "molecular"] <- "BIOL 3010"
  expect_no_error(validate_degree_roadmaps(r, c))
  r$nodes$course_level[r$nodes$node_id == "molecular"] <- "lower"
  expect_error(validate_degree_roadmaps(r, c), "level disagrees")
  r <- CEDAR_DEGREE_ROADMAPS; r$nodes$course_level[r$nodes$kind == "choice"] <- ""
  expect_error(validate_degree_roadmaps(r, c), "Invalid roadmap course level")
  r <- CEDAR_DEGREE_ROADMAPS; r$plans$upper_level_from_semester <- "1"
  expect_error(validate_degree_roadmaps(r, c), "early-coursework stage")
})

test_that("planning burden counts unique ancestors and makes an entry course's long chain visible", {
  v <- build_degree_roadmap(CEDAR_DEGREE_CATALOG, CEDAR_DEGREE_ROADMAPS,
    "cs-bs-2026", "intermediate", "composition")
  node <- function(id) v$nodes[v$nodes$node_id == id, ]
  expect_equal(node("math1215")$planning_level, "green")
  expect_equal(node("math1215")$n_downstream, 7L)
  expect_equal(node("math1215")$chain_terms, 7L)
  expect_equal(node("math1220")$planning_level, "yellow")
  expect_equal(node("calc1")$planning_level, "red")
  # Computing and math converge on linear algebra and numerical computing.
  # Java I / Fundamentals occur on multiple routes, but each counts only once.
  expect_equal(node("numerical")$n_direct, 3L)
  expect_equal(node("numerical")$n_prerequisites, 9L)
  expect_equal(node("numerical")$prereq_depth, 6L)
  expect_true(all(v$nodes$planning_level[v$nodes$kind == "choice"] == "unresolved"))
  b <- build_degree_roadmap(CEDAR_DEGREE_CATALOG, CEDAR_DEGREE_ROADMAPS,
    "biology-bs-2026", "calculus", "composition")
  physiology <- b$nodes[b$nodes$node_id == "physiology", ]
  expect_equal(physiology$n_prerequisites, 4L)
  expect_equal(physiology$prereq_depth, 1L) # Evolution can be concurrent, not an extra prior term.
  expect_equal(b$nodes$n_prerequisites[b$nodes$node_id == "chem2"], 2L) # The paired lecture and lab are two courses.
})

test_that("a degree citation cannot be silently replaced with a course description", {
  c <- CEDAR_DEGREE_CATALOG; r <- CEDAR_DEGREE_ROADMAPS
  v <- build_degree_roadmap(c, r, "cs-bs-2026", "intermediate", "composition")
  os <- v$nodes[v$nodes$node_id == "os", ]
  expect_equal(os$evidence_section, "Requirements → Required computer science courses")
  expect_match(os$evidence_quote, "CS481", fixed = TRUE)
  expect_match(os$evidence_source_url, "/programs/", fixed = TRUE)
  preparation <- v$nodes[v$nodes$node_id == "math1215", ]
  expect_equal(preparation$basis, "prerequisite")
  expect_match(preparation$evidence_quote, "MATH1215", fixed = TRUE)
  expect_false(preparation$source_url == preparation$evidence_source_url)
  expect_equal(preparation$evidence_catalog_year, "2026-2027")
  bad <- r; bad$basis$evidence_id[bad$basis$node_id == "os"] <- bad$links$evidence_id[1]
  expect_error(validate_degree_roadmaps(bad, c), "program page")
  bad <- r; bad$basis$node_id[1] <- "missing"
  expect_error(validate_degree_roadmaps(bad, c), "requirement evidence")
  bad <- r; bad$links$evidence_id[1] <- "missing"
  expect_error(validate_degree_roadmaps(bad, c), "Unknown roadmap evidence")
  bad <- c; bad$evidence$catalog_year[1] <- "2025-2026"
  expect_error(validate_degree_catalog(bad), "evidence year")
})

# Authored timing perturbations prove a pool condition schedules enough courses
# without turning every option, or two particular electives, into named edges.
test_that("course-count conditions schedule against a pool and preserve their own evidence", {
  r <- CEDAR_DEGREE_ROADMAPS; c <- CEDAR_DEGREE_CATALOG
  hist <- r$nodes$catalog_id == "history-ba-2026"
  r$nodes$semester[hist & grepl("^histupper", r$nodes$node_id)] <- "8"
  r$nodes$semester[hist & r$nodes$node_id == "histupper6"] <- "5"
  r$nodes$semester[hist & r$nodes$node_id == "historiography"] <- "1"
  v <- build_degree_roadmap_view(c, r, "history-ba-2026", "calculus", "composition")
  expect_equal(v$nodes$semester[v$nodes$node_id == "historiography"], 9L)
  expect_false(any(v$links$to == "historiography"))
  target <- v$nodes[v$nodes$node_id == "historiography", ]
  expect_match(target$condition_label, "2+ upper-level History courses", fixed = TRUE)
  expect_match(target$planning_note, "0 named prerequisite courses", fixed = TRUE)
  expect_true(all(grepl("/courses/", v$conditions$source_url, fixed = TRUE)))
  philosophy <- build_degree_roadmap_view(c, r, "philosophy-ba-2026", "calculus", "composition")
  expect_false(any(philosophy$links$to == "philethics"))
  bad <- r; bad$conditions$minimum[1] <- "7"
  expect_error(validate_degree_roadmaps(bad, c), "course-count condition")
  bad <- r; bad$conditions$evidence_id[1] <- "total-history-ba-2026"
  expect_error(validate_degree_roadmaps(bad, c), "Condition needs matching course evidence")
})

test_that("Gen Ed suggestions are explicit on the chart payload while named math stays required", {
  c <- CEDAR_DEGREE_CATALOG; r <- CEDAR_DEGREE_ROADMAPS
  history <- build_degree_roadmap_view(c, r, "history-ba-2026", "algebra", "composition")
  business <- build_degree_roadmap_view(c, r, "business-bba-2026", "algebra", "composition")
  suggestion <- history$nodes[history$nodes$node_id == "math1350", ]
  required <- business$nodes[business$nodes$node_id == "math1350", ]
  expect_true(suggestion$is_suggested)
  expect_equal(suggestion$kind_label, "Suggested Gen Ed")
  expect_false(required$is_suggested)
  expect_equal(required$basis, "degree")
})

# These are the authored catalog sets; no enrollment/domain records are invented.
test_that("named course sets expose all alternatives without applying one option's prerequisites to the set", {
  c <- CEDAR_DEGREE_CATALOG; r <- CEDAR_DEGREE_ROADMAPS
  v <- build_degree_roadmap_view(c, r, "philosophy-ba-2026", "calculus", "composition")
  asian <- v$nodes[v$nodes$node_id == "philbuddhist", ]
  expect_equal(asian$option_label, "Choose 1 of 3 courses")
  expect_equal(asian$option_codes, "PHIL 333, PHIL 334, PHIL 336")
  expect_equal(asian$planning_level, "unresolved")
  expect_equal(nrow(v$options), 15L)
  expect_equal(sum(v$nodes$credits[v$nodes$catalog_id == "philosophy-ba-2026"]), 30)
  expect_equal(nrow(v$links), sum(v$links$catalog_id == "*"))
  expect_equal(nrow(v$conditions), 0L)
  expect_match(v$options$prerequisite_note[v$options$subject_course == "PHIL 358"], "one course in Philosophy", fixed = TRUE)
  expect_match(v$options$prerequisite_note[v$options$subject_course == "PHIL 352"], "PHIL2210", fixed = TRUE)
  expect_equal(v$options$credit_label[v$options$subject_course == "PHIL 356"], "3–4")
  expect_match(v$nodes$kind_label[v$nodes$node_id == "phillogic"], "Level varies", fixed = TRUE)
  expect_true(all(v$nodes$semester[v$nodes$course_level == "upper"] >= 5L))
  bad <- r; bad$options <- rbind(bad$options, bad$options[1, ])
  expect_error(validate_degree_roadmaps(bad, c), "option course")
  bad <- r; bad$options$minimum[bad$options$node_id == "philbuddhist"] <- "4"
  expect_error(validate_degree_roadmaps(bad, c), "option set")
  bad <- r; bad$options$evidence_id[1] <- "total-history-ba-2026"
  expect_error(validate_degree_roadmaps(bad, c), "program requirement evidence")
  bad <- r; bad$options$source_url[bad$options$subject_course == "PHIL 358"] <- c$catalogs$source_url[1]
  expect_error(validate_degree_roadmaps(bad, c), "matching course evidence")
  # Restoring the former selected-course edge would misstate every alternative.
  bad <- r; edge <- bad$links[1, ]; edge$catalog_id <- "philosophy-ba-2026"
  edge$from <- "philmodern"; edge$to <- "philknowledge"
  bad$links <- rbind(bad$links, edge)
  expect_error(validate_degree_roadmaps(bad, c), "inherit a particular course")
})

test_that("science alternatives count complete lecture/lab options and retain the shared credit budget", {
  c <- CEDAR_DEGREE_CATALOG; r <- CEDAR_DEGREE_ROADMAPS
  v <- build_degree_roadmap_view(c, r, "cs-bs-2026", "calculus", "composition")
  science <- v$nodes[v$nodes$node_id %in% paste0("science", 1:4), ]
  expect_equal(science$credits, c(4, 4, 3, 3))
  expect_equal(sum(science$credits), 14)
  expect_true(all(science$option_count == 11L))
  expect_true(all(science$planning_level == "unresolved"))
  expect_true(all(grepl("14+ science credits total · 2 lecture/lab pairs", science$requirement_summary, fixed = TRUE)))
  first <- v$option_groups[v$option_groups$node_id == "science1", ]
  expect_equal(nrow(first), 11L)
  expect_equal(sum(first$component_count), 19L)
  expect_equal(sum(first$component_count == 2L), 8L)
  expect_true(all(first$credits_min == 4 & first$credits_max == 4))
  expect_equal(first$option_code[first$option_id == "chem1215"], "CHEM 1215 + CHEM 1215L")
  expect_equal(first$option_code[first$option_id == "biol2110c"], "BIOL 2110C")
  extra <- v$options[v$options$node_id == "science3", ]
  expect_equal(nrow(extra), 11L)
  expect_true(all(as.numeric(extra$credits_min) >= 3))
  expect_true(all(v$terms$planned_credits <= 16))
  expect_false(any(v$links$from %in% science$node_id | v$links$to %in% science$node_id))
  expect_match(science$evidence_quote[1], "two lectures paired with the appropriate labs", fixed = TRUE)
  # The old row-based validation accepted 3 credits because lectures and labs
  # looked like separate alternatives. Every complete lab option costs 4.
  bad <- r; bad$nodes$credits[bad$nodes$catalog_id == "cs-bs-2026" & bad$nodes$node_id == "science1"] <- "3"
  expect_error(validate_degree_roadmaps(bad, c), "option set or planning credits")
})

test_that("early allowances occupy course slots without changing credits or sequence gaps", {
  c <- CEDAR_DEGREE_CATALOG; r <- CEDAR_DEGREE_ROADMAPS
  for (starts in list(c("cs-bs-2026", "calculus", "composition"),
    c("cs-bs-2026", "intermediate", "stretch"), c("philosophy-ba-2026", "algebra", "complete"),
    c("physics-bs-2026", "intermediate", "composition"))) {
    v <- build_degree_roadmap_view(c, r, starts[1], starts[2], starts[3])
    original <- build_degree_roadmap(c, r, starts[1], starts[2], starts[3])
    expect_identical(v$nodes$row, original$nodes$row)
    expect_equal(v$terms$planned_credits, original$terms$planned_credits)
    expect_true(all(v$allowances$credits > 0 & v$allowances$credits <= 4))
    expect_true(all(v$allowances$semester < 5))
    expect_false(anyDuplicated(c(paste(v$nodes$semester, v$nodes$row),
      paste(v$allowances$semester, v$allowances$row))) > 0L)
    for (s in v$terms$semester[v$terms$other_phase == "foundation"]) {
      expect_equal(sum(v$allowances$credits[v$allowances$semester == s]), v$terms$other_credits[v$terms$semester == s])
    }
    expect_false(any(v$allowances$row %in% v$nodes$row[v$nodes$row_group %in% c("math", "writing")]))
    for (key in unique(paste(v$nodes$row, v$nodes$row_group))) {
      family <- v$nodes[paste(v$nodes$row, v$nodes$row_group) == key, ]
      expect_false(any(v$allowances$row == family$row[1] &
        v$allowances$semester >= min(family$semester) & v$allowances$semester <= max(family$semester)))
    }
  }
  fall <- build_degree_roadmap_view(c, r, "cs-bs-2026", "calculus", "composition")
  spring <- build_degree_roadmap_view(c, r, "cs-bs-2026", "calculus", "composition", "spring")
  expect_equal(fall$terms$season[1:4], c("fall", "spring", "fall", "spring"))
  expect_equal(spring$terms$season[1:4], c("spring", "fall", "spring", "fall"))
  expect_identical(fall$allowances[c("node_id", "semester", "credits", "row")],
    spring$allowances[c("node_id", "semester", "credits", "row")])
  expect_error(degree_semester_seasons(1:8, "summer"), "fall or spring")
  r$plans$degree_credit_target[r$plans$catalog_id == "cs-bs-2026"] <-
    sum(fall$nodes$credits[fall$nodes$kind != "preparation"])
  empty <- build_degree_roadmap_view(c, r, "cs-bs-2026", "calculus", "composition")
  expect_equal(nrow(empty$allowances), 0L)
})
