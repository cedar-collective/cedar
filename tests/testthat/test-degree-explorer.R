context("Degree Explorer")

# The demo institution's designed catalog (institution/demo/degree_*.csv,
# exposed by setup.R as test_degree_catalog / test_degree_roadmaps) holds two
# synthetic programs built to exercise each planning rule. Every schedule below
# is worked by hand from those files.
#
# Biology B.S., calculus-ready, Composition I, fall start (120 credits, 15 usual,
# 16 maximum, upper-level from semester 5):
#   s1 calc1 4, engl1 3, bio1 4, chem1 4 (lecture/lab bundle)    = 15
#   s2 engl2 3, bio2 4, chem2 4 (bundle), phys1 4 (after calc1)  = 15
#   s3 genetics 3 (after bio2 and chem1), biosci 4 (choice)      =  7
#   s5 molecular 4, evolution 4, physiology 3 (evolution before or with it) = 11
#   s7 bioelective 3 (choice); s8 biocap 3 (after molecular)
#   Shown 54; other degree work 66 fills every semester to 15.
#   Early allowances: s3 has 3 + 3 + 2; s4 has five 3-credit slots. They occupy
#   top rows 1–5; the aligned course families begin with math at row 6.
#   molecular's ancestors: genetics, chem2 (2), bio2, chem1 (2), bio1 = 7 courses,
#   chem1 counted once although both genetics and chem2 lead from it.
#   physiology: prereq_depth 2, not 3 — a concurrent link adds no semester.
# History B.A., algebra-ready (statistics), Composition I:
#   math1350 s1 (a suggested Gen Ed course), hist1 s1, hist2 s2,
#   histmethods/histupper1/histupper2 s5, histupper3/histupper4/histchoice s6,
#   historiography s7 (2 of the histupper pool, plus permission), histsenior s8.
catalog <- function() test_degree_catalog
roadmaps <- function() test_degree_roadmaps
BIOLOGY <- "demo-biology-bs-2026"
HISTORY <- "demo-history-ba-2026"
plan <- function(id = BIOLOGY, math = "calculus", english = "composition", r = roadmaps()) {
  build_degree_roadmap(catalog(), r, id, math, english)
}
view_of <- function(id = BIOLOGY, math = "calculus", english = "composition", season = "fall", r = roadmaps()) {
  build_degree_roadmap_view(catalog(), r, id, math, english, season)
}
at <- function(view, id, field = "semester") view$nodes[[field]][match(id, view$nodes$node_id)]

# EC-11 and EC-11b supply the raw section and class-list rows for popup history.
history_edges <- list(last_enrolled_complete = 202080L, last_enrolled = 202180L)
planning_gen_ed <- function() data.frame(subject_course = c("SOCI 100", "SOCI 101", "SOCI 104"),
  area_label = c("4: Social sciences", "4: Social sciences", "5: Humanities"))

# ── Catalog rule trees ───────────────────────────────────────────────────────

test_that("catalog trees preserve alternatives, bundles, timing and unresolved source rules", {
  expect_equal(validate_degree_catalog(catalog()), catalog())
  rules <- degree_rule_outline(catalog(), catalog()$catalogs$catalog_id)
  intermediate <- rules[rules$rule_id == "bio-intermediate", ]
  bundle <- rules[rules$rule_id == "bio-microbiology", ]
  expect_equal(intermediate$operator, "choose_n")
  expect_equal(intermediate$minimum, "2")
  expect_match(intermediate$text, "Choose at least 2 options", fixed = TRUE)
  expect_equal(bundle$parent_id, intermediate$rule_id)
  expect_equal(bundle$depth, 1L)
  expect_equal(rules$depth[rules$rule_id == "bio-micro-lab"], 2L)
  # Children follow their parent, whatever the file order.
  expect_equal(match("bio-micro-lab", rules$rule_id), match("bio-microbiology", rules$rule_id) + 2L)
  expect_true(any(rules$operator == "concurrent"))
  expect_match(rules$text[rules$rule_id == "bio-physiology-req"],
    "BIOL 304C — Evolution (4 credits) [for BIOL 3200]: Complete before or take concurrently", fixed = TRUE)
  expect_match(rules$text[rules$rule_id == "bio-total"], "[SOURCE CONFLICT]", fixed = TRUE)
  bad <- catalog(); bad$rules$parent_id[1] <- bad$rules$rule_id[1]
  expect_error(validate_degree_catalog(bad), "Cycle")
  bad <- catalog(); bad$rules$minimum[bad$rules$rule_id == "bio-intermediate"] <- "4"
  expect_error(validate_degree_catalog(bad), "Invalid choice group")
  bad <- catalog(); bad$courses$rule_id[1] <- "missing"
  expect_error(validate_degree_catalog(bad), "unknown rule")
  bad <- catalog(); bad$evidence$catalog_year[1] <- "2025-2026"
  expect_error(validate_degree_catalog(bad), "evidence year")
})

# ── Scheduling ───────────────────────────────────────────────────────────────

test_that("readable plan rules expose the active graph and distinguish policy from scheduling", {
  v <- view_of(HISTORY)
  rules <- build_degree_plan_rules(catalog(), roadmaps(), v)
  expect_match(rules$scenario, "Math: Calculus-ready: take statistics", fixed = TRUE)
  rows <- rules$rows
  expect_equal(sum(rows$kind == "Prerequisite arrow"), nrow(v$links))
  expect_equal(sum(rows$kind == "Other enrollment condition"), nrow(v$conditions))
  expect_true(any(grepl("2+ upper-level", rows$rule, fixed = TRUE)))
  # Aggregate conditions must not turn the entire qualifying pool into arrows.
  arrows <- rows[rows$kind == "Prerequisite arrow", ]
  expect_false(any(startsWith(arrows$node_ids, "histupper")))
  expect_true(all(nzchar(arrows$source_url) & nzchar(arrows$quote)))
  preference <- rows[rows$kind == "Planning preference", ]
  expect_true(any(grepl("15 credits; never more than 16", preference$rule, fixed = TRUE)))
  expect_true(all(preference$source_url == "" & preference$quote == ""))
  expect_true(any(rows$kind == "Suggested general coursework" & grepl("MATH 1350", rows$rule, fixed = TRUE)))
  expect_true(all(grepl("not evaluated", rows$effect[rows$kind == "Recorded catalog requirement"], fixed = TRUE)))
  prepared <- build_degree_plan_rules(catalog(), roadmaps(), view_of(HISTORY, "intermediate"))$rows
  expect_true(any(prepared$kind == "Preparation" & grepl("MATH 1215", prepared$rule, fixed = TRUE)))
  expect_false(any(rows$kind == "Preparation" & grepl("MATH 1215", rows$rule, fixed = TRUE)))
  expect_setequal(setdiff(unique(unlist(strsplit(paste(rows$node_ids, collapse = "|"), "|", fixed = TRUE))), ""), c(v$nodes$node_id, v$allowances$node_id))
})

test_that("required blocks count actual component courses rather than assuming a two-course pair", {
  nodes <- data.frame(node_id = c("clinical", "advanced"), kind = c("cohort", "major"),
    bundle = c(TRUE, FALSE), component_count = c(5L, 1L))
  links <- data.frame(from = "clinical", to = "advanced", timing = "before")
  metrics <- get_degree_chain_metrics(nodes, links)
  expect_equal(metrics$n_prerequisites[metrics$node_id == "advanced"], 5L)
  expect_equal(metrics$n_direct[metrics$node_id == "advanced"], 5L)
  expect_equal(metrics$prereq_depth[metrics$node_id == "advanced"], 1L)
  expect_equal(metrics$n_downstream[metrics$node_id == "clinical"], 1L)
})

test_that("the calculus-ready biology plan matches its hand-worked schedule", {
  v <- plan()
  expect_equal(at(v, c("calc1", "engl1", "bio1", "chem1")), rep(1L, 4))
  expect_equal(at(v, c("engl2", "bio2", "chem2", "phys1")), rep(2L, 4))
  expect_equal(at(v, c("genetics", "biosci")), c(3L, 3L))
  expect_equal(at(v, c("molecular", "evolution", "physiology")), rep(5L, 3))
  expect_equal(at(v, c("bioelective", "biocap")), c(7L, 8L))
  expect_equal(v$terms$known_credits, c(15, 15, 7, 0, 11, 0, 3, 3))
  expect_equal(v$terms$other_credits, c(0, 0, 8, 15, 4, 15, 12, 12))
  expect_equal(v$terms$planned_credits, rep(15, 8))
  expect_equal(v$terms$other_phase, rep(c("foundation", "advanced"), each = 4))
  expect_equal(v$preparation_credits, 0)
  expect_equal(v$n_moved, 0L)
  expect_equal(v$math_target$code, "MATH 1512")
  expect_error(build_degree_roadmap(catalog(), roadmaps(), catalog()$catalogs$catalog_id, "calculus", "composition"),
    "one known degree")
  expect_error(plan(math = "unknown"), "known math")
})

test_that("math preparation adds its sequence and moves only the courses that depend on it", {
  ready <- plan()
  prepared <- plan(math = "intermediate")
  expect_equal(at(prepared, c("math1215", "math1220", "math1250", "calc1")), 1:4)
  # Physics follows Calculus I out of semester 2; nothing else moves.
  expect_equal(at(prepared, "phys1"), 5L)
  expect_true(at(prepared, "phys1", "moved"))
  expect_equal(prepared$n_moved, 1L)
  unrelated <- c("bio1", "chem1", "genetics", "molecular", "biocap")
  expect_equal(at(prepared, unrelated), at(ready, unrelated))
  expect_equal(prepared$n_preparation, 3L)
  expect_equal(prepared$preparation_credits, 9)
  # 129 planned credits cannot fit eight semesters at 16; the plan grows a ninth.
  expect_equal(nrow(prepared$terms), 9L)
  expect_equal(prepared$terms$planned_credits, c(rep(15, 8), 9))
  expect_false("math1215" %in% ready$nodes$node_id)
})

test_that("English starting points replace the sequence and completed credit leaves the target", {
  stretch <- plan(english = "stretch")
  expect_equal(stretch$nodes$code[stretch$nodes$track == "english"], c("ENGL 1110X", "ENGL 1110Y", "ENGL 1120"))
  expect_equal(at(stretch, c("englX", "englY", "engl2")), 1:3)
  # Stretch I is preparation: 123 credits over eight semesters uses the 16-credit maximum.
  expect_equal(stretch$preparation_credits, 3)
  expect_equal(stretch$terms$planned_credits, c(16, 16, 16, 15, 15, 15, 15, 15))
  advanced <- plan(english = "composition2")
  expect_equal(advanced$nodes$code[advanced$nodes$track == "english"], "ENGL 1120")
  expect_equal(at(advanced, "engl2"), 1L)
  complete <- plan(english = "complete")
  expect_false(any(complete$nodes$track == "english"))
  expect_equal(complete$completed_credits, 6)
  expect_equal(sum(complete$terms$planned_credits), 114)
})

test_that("lecture/lab bundles stay together and count as two courses", {
  v <- plan()
  expect_equal(sum(v$nodes$bundle), 2L)
  expect_equal(at(v, c("chem1", "chem2"), "credits"), c(4, 4))
  expect_equal(at(v, "chem2", "n_prerequisites"), 2L)
  # Genetics' direct prerequisites: Biology II plus the chemistry bundle.
  expect_equal(at(v, "genetics", "n_direct"), 3L)
})

test_that("planning burden counts unique ancestors and keeps chain length separate", {
  v <- plan()
  expect_equal(at(v, "molecular", "n_prerequisites"), 7L)
  expect_equal(at(v, "molecular", "prereq_depth"), 3L)
  expect_setequal(strsplit(at(v, "molecular", "upstream_ids"), "|", fixed = TRUE)[[1]],
    c("genetics", "chem2", "bio2", "chem1", "bio1"))
  expect_equal(at(v, "biocap", "n_prerequisites"), 8L)
  expect_equal(at(v, "physiology", "prereq_depth"), 2L)
  expect_equal(at(v, "physiology", "n_prerequisites"), 3L)
  expect_equal(at(v, "bio1", "n_downstream"), 6L)
  expect_equal(at(v, "bio1", "chain_terms"), 5L)
  expect_setequal(strsplit(at(v, "chem1", "downstream_ids"), "|", fixed = TRUE)[[1]],
    c("chem2", "genetics", "molecular", "biocap"))
  expect_equal(at(v, "chem1", "n_downstream"), 5L)
  expect_equal(at(v, c("bio1", "bio2", "genetics", "evolution", "molecular", "biosci"), "planning_level"),
    c("green", "yellow", "red", "yellow", "red", "unresolved"))
  # Concurrent timing may share a semester; a "before" link may not.
  links <- v$links
  expect_true(all(at(v, links$to) >= at(v, links$from) + as.integer(links$timing == "before")))
  expect_equal(at(v, "physiology"), at(v, "evolution"))
})

# Authored timing perturbation: a delayed course pushes its dependants past semester 8.
test_that("the semester board extends rather than dropping delayed courses", {
  r <- roadmaps()
  r$nodes$semester[r$nodes$catalog_id == BIOLOGY & r$nodes$node_id == "molecular"] <- "8"
  v <- plan(r = r)
  expect_equal(at(v, c("molecular", "biocap")), c(8L, 9L))
  expect_equal(tail(v$terms$semester, 1), 9L)
  expect_equal(nrow(v$nodes), 15L)
  expect_match(format_degree_explorer_preview(view_of(r = r)), "Semester 9", fixed = TRUE)
})

test_that("upper-level courses wait for the institution's later planning stage", {
  v <- plan()
  expect_true(all(v$nodes$semester[v$nodes$course_level == "upper"] >= 5L))
  r <- roadmaps()
  r$plans$upper_level_from_semester[r$plans$catalog_id == BIOLOGY] <- "7"
  late <- view_of(r = r)
  expect_equal(at(late, c("molecular", "evolution", "physiology", "bioelective", "biocap")), c(7L, 7L, 7L, 7L, 8L))
  expect_true(all(late$terms$other_label[late$terms$semester < 7L] == "Gen Ed where identified; other elective / minor credits"))
  expect_true(all(late$terms$other_label[late$terms$semester >= 7L] == "Elective / minor · upper level may count"))
  expect_match(late$timing_note, "semester 7", fixed = TRUE)
  expect_true(all(late$terms$planned_credits <= 16))
})

# ── Layout ───────────────────────────────────────────────────────────────────

test_that("course families align after scheduling and parallel courses take separate rows", {
  v <- plan()
  expect_equal(at(v, c("calc1", "engl1", "engl2"), "row"), c(6L, 7L, 7L))
  expect_equal(at(v, c("bio1", "bio2", "genetics", "molecular"), "row"), rep(8L, 4))
  # Evolution and Physiology share Molecular Biology's semester and family.
  expect_equal(at(v, c("evolution", "physiology"), "row"), c(9L, 10L))
  # Other families reuse a row outside each other's span.
  expect_equal(at(v, c("biocap", "bioelective"), "row"), c(8L, 8L))
  expect_equal(at(v, c("chem1", "chem2", "biosci", "phys1"), "row"), c(9L, 9L, 9L, 10L))
  expect_false(anyDuplicated(paste(v$nodes$semester, v$nodes$row)) > 0L)
  # Layout metadata cannot change credit budgets, course timing or graph metrics.
  r <- roadmaps()
  r$nodes$row_group <- "one_family"
  alternate <- plan(r = r)
  fields <- c("node_id", "semester", "credits", "n_prerequisites", "n_downstream")
  expect_equal(v$nodes[fields], alternate$nodes[fields])
  expect_equal(v$terms, alternate$terms)
  r$nodes$row_group[1] <- ""
  expect_error(validate_degree_roadmaps(r, catalog()), "row group")
})

test_that("early allowances occupy the top rows without changing credits or family gaps", {
  v <- view_of()
  expect_identical(v$nodes$row, plan()$nodes$row)
  expect_equal(v$allowances$semester, c(3L, 3L, 3L, 4L, 4L, 4L, 4L, 4L))
  expect_equal(v$allowances$credits, c(3, 3, 2, 3, 3, 3, 3, 3))
  expect_equal(v$allowances$row, c(1L, 2L, 3L, 1L, 2L, 3L, 4L, 5L))
  expect_lt(max(v$allowances$row), min(v$nodes$row))
  expect_equal(v$allowances$title[3], "Credits left to allocate")
  expect_equal(v$n_rows, 10L)
  for (s in v$terms$semester[v$terms$other_phase == "foundation"]) {
    expect_equal(sum(v$allowances$credits[v$allowances$semester == s]), v$terms$other_credits[v$terms$semester == s])
  }
  expect_false(anyDuplicated(c(paste(v$nodes$semester, v$nodes$row),
    paste(v$allowances$semester, v$allowances$row))) > 0L)
  spring <- view_of(season = "spring")
  expect_equal(v$terms$season[1:4], c("fall", "spring", "fall", "spring"))
  expect_equal(spring$terms$season[1:4], c("spring", "fall", "spring", "fall"))
  expect_identical(v$allowances[c("node_id", "semester", "credits", "row")],
    spring$allowances[c("node_id", "semester", "credits", "row")])
  expect_error(degree_semester_seasons(1:8, "summer"), "fall or spring")
  r <- roadmaps()
  r$plans$degree_credit_target[r$plans$catalog_id == BIOLOGY] <- "54"
  no_allowances <- view_of(r = r)
  expect_equal(nrow(no_allowances$allowances), 0L)
  expect_equal(min(no_allowances$nodes$row), 1L)
})

# ── Programs: routes, conditions, choices and citations ──────────────────────

test_that("a statistics major takes its own math route and never inherits calculus", {
  h <- plan(HISTORY, "intermediate")
  expect_equal(h$nodes$code[h$nodes$track == "math"], c("MATH 1215", "MATH 1350"))
  expect_equal(at(h, c("math1215", "math1350")), 1:2)
  expect_equal(h$preparation_credits, 3)
  expect_false(any(c("calc1", "math1220", "math1250") %in% h$nodes$node_id))
  ready <- plan(HISTORY, "algebra")
  expect_equal(ready$math_target$code, "MATH 1350")
  expect_equal(ready$math_target$semester, 1L)
  expect_equal(ready$n_preparation, 0L)
  expect_setequal(unname(degree_math_start_choices(roadmaps(), HISTORY)),
    roadmaps()$starts$start_id[roadmaps()$starts$track == "math"])
  bad <- roadmaps(); bad$math_routes <- bad$math_routes[-1, ]
  expect_error(validate_degree_roadmaps(bad, catalog()), "math starting routes missing")
  bad <- roadmaps(); bad$math_routes$node_ids[1] <- "missing"
  expect_error(validate_degree_roadmaps(bad, catalog()), "math route course")
  bad <- roadmaps(); bad$math_routes$node_ids[bad$math_routes$catalog_id == HISTORY] <- "calc1"
  expect_error(validate_degree_roadmaps(bad, catalog()), "requirement evidence")
})

test_that("a course-count condition stays separate from named prerequisites", {
  h <- view_of(HISTORY, "algebra")
  expect_equal(at(h, c("histmethods", "histupper1", "histupper2")), rep(5L, 3))
  expect_equal(at(h, c("histupper3", "histupper4", "histchoice")), rep(6L, 3))
  expect_equal(at(h, c("historiography", "histsenior")), c(7L, 8L))
  expect_false(any(h$links$to == "historiography"))
  target <- h$nodes[h$nodes$node_id == "historiography", ]
  expect_equal(target$n_prerequisites, 0L)
  expect_equal(target$n_conditions, 2L)
  expect_equal(target$planning_level, "conditional")
  expect_equal(target$condition_label, "2+ upper-level History courses · Department permission")
  expect_equal(target$prerequisite_label, "Prior coursework / permission")
  expect_equal(target$chain_badge, "◇ Enrollment conditions")
  expect_match(target$planning_note, "0 named prerequisite courses", fixed = TRUE)
  expect_setequal(strsplit(target$qualifying_ids, "|", fixed = TRUE)[[1]], paste0("histupper", 1:4))
  expect_true(all(grepl("/courses/", h$conditions$source_url, fixed = TRUE)))
  expect_equal(at(h, "histsenior", "planning_level"), "yellow")
})

# Authored timing perturbation: the condition waits for the second qualifying
# pool completion, not for every member and not for two particular electives.
test_that("course-count conditions schedule against the earliest qualifying pool completions", {
  r <- roadmaps()
  history <- r$nodes$catalog_id == HISTORY
  r$nodes$semester[history & r$nodes$node_id %in% paste0("histupper", 1:3)] <- "8"
  r$nodes$semester[history & r$nodes$node_id == "histupper4"] <- "5"
  r$nodes$semester[history & r$nodes$node_id == "historiography"] <- "1"
  v <- plan(HISTORY, "algebra", r = r)
  expect_equal(at(v, "historiography"), 9L)
  bad <- roadmaps(); bad$conditions$minimum[1] <- "5"
  expect_error(validate_degree_roadmaps(bad, catalog()), "course-count condition")
  bad <- roadmaps(); bad$conditions$evidence_id[1] <- "total-hist"
  expect_error(validate_degree_roadmaps(bad, catalog()), "Condition needs matching course evidence")
})

test_that("Gen Ed suggestions are labelled while named requirements keep program styling", {
  h <- view_of(HISTORY, "algebra")
  b <- view_of()
  suggestion <- h$nodes[h$nodes$node_id == "math1350", ]
  expect_true(suggestion$is_suggested)
  expect_equal(suggestion$basis, "general")
  expect_equal(suggestion$kind_label, "Suggested Gen Ed")
  calculus <- b$nodes[b$nodes$node_id == "calc1", ]
  expect_false(calculus$is_suggested)
  expect_equal(calculus$basis, "degree")
})

test_that("named course sets expose every alternative without one option's prerequisites", {
  h <- view_of(HISTORY, "algebra")
  world <- h$nodes[h$nodes$node_id == "histchoice", ]
  expect_equal(world$option_label, "Choose 1 of 4 courses")
  expect_equal(world$option_codes, "HIST 1160, HIST 327, HIST 395, HIST 401")
  expect_equal(world$planning_level, "unresolved")
  expect_equal(world$kind_label, "Course choice · Level varies")
  expect_equal(nrow(h$options), 4L)
  expect_equal(h$options$credit_label[h$options$subject_course == "HIST 401"], "3–4")
  expect_equal(h$options$prerequisite_note[h$options$subject_course == "HIST 401"], "HIST 300 - Historical Methods (3)")
  expect_equal(h$options$prerequisite_note[h$options$subject_course == "HIST 327"], "")
  bad <- roadmaps(); bad$options <- rbind(bad$options, bad$options[1, ])
  expect_error(validate_degree_roadmaps(bad, catalog()), "option course")
  bad <- roadmaps(); bad$options$minimum[bad$options$node_id == "histchoice"] <- "5"
  expect_error(validate_degree_roadmaps(bad, catalog()), "option set")
  bad <- roadmaps(); bad$options$evidence_id[bad$options$node_id == "histchoice"][1] <- "total-hist"
  expect_error(validate_degree_roadmaps(bad, catalog()), "program requirement evidence")
  bad <- roadmaps(); bad$options$source_url[bad$options$subject_course == "HIST 401"] <- catalog()$catalogs$source_url[2]
  expect_error(validate_degree_roadmaps(bad, catalog()), "matching course evidence")
  # A named edge into a set would misstate every alternative.
  bad <- roadmaps(); edge <- bad$links[bad$links$catalog_id == HISTORY, ][1, ]
  edge$from <- "histmethods"; edge$to <- "histchoice"
  bad$links <- rbind(bad$links, edge)
  expect_error(validate_degree_roadmaps(bad, catalog()), "inherit a particular course")
})

test_that("lecture/lab alternatives count complete options and keep the slot's credits", {
  v <- view_of()
  science <- v$nodes[v$nodes$node_id == "biosci", ]
  expect_equal(science$option_label, "Choose 1 of 3 options")
  expect_equal(science$option_codes, "PHYS 1230 + PHYS 1230L, GEOL 1110 + GEOL 1110L, ENVS 1110C")
  groups <- v$option_groups[v$option_groups$node_id == "biosci", ]
  expect_equal(groups$component_count, c(2L, 2L, 1L))
  expect_true(all(groups$credits_min == 4 & groups$credits_max == 4))
  expect_false(any(v$links$from == "biosci" | v$links$to == "biosci"))
  # Counting rows as alternatives would let a one-credit lab fill the slot.
  bad <- roadmaps(); bad$nodes$credits[bad$nodes$catalog_id == BIOLOGY & bad$nodes$node_id == "biosci"] <- "3"
  expect_error(validate_degree_roadmaps(bad, catalog()), "option set or planning credits")
})

test_that("each tile cites its own requirement, and preparation cites the course it unlocks", {
  v <- plan(math = "intermediate")
  molecular <- v$nodes[v$nodes$node_id == "molecular", ]
  expect_equal(molecular$evidence_section, "Requirements → Biology core")
  expect_match(molecular$evidence_quote, "BIOL300C", fixed = TRUE)
  expect_equal(molecular$evidence_source_url, v$catalog$source_url)
  preparation <- v$nodes[v$nodes$node_id == "math1215", ]
  expect_equal(preparation$basis, "prerequisite")
  expect_match(preparation$evidence_source_url, "MATH-1220", fixed = TRUE)
  expect_false(preparation$source_url == preparation$evidence_source_url)
  expect_true(all(v$nodes$evidence_catalog_year == "2026-2027"))
  bad <- roadmaps(); bad$basis$evidence_id[bad$basis$catalog_id == BIOLOGY & bad$basis$node_id == "molecular"] <- "req-bio1-bio2"
  expect_error(validate_degree_roadmaps(bad, catalog()), "program page")
  bad <- roadmaps(); bad$basis$node_id[1] <- "missing"
  expect_error(validate_degree_roadmaps(bad, catalog()), "requirement evidence")
  bad <- roadmaps(); bad$links$evidence_id[1] <- "missing"
  expect_error(validate_degree_roadmaps(bad, catalog()), "Unknown roadmap evidence")
  bad <- roadmaps(); bad$links$from[1] <- "missing"
  expect_error(validate_degree_roadmaps(bad, catalog()), "endpoint")
  bad <- roadmaps(); bad$links$to[1] <- bad$links$from[1]
  expect_error(validate_degree_roadmaps(bad, catalog()), "Cycle")
})

test_that("authored course levels agree with institution numbering bands", {
  r <- roadmaps()
  r$nodes$course_level[r$nodes$node_id == "molecular"] <- "lower"
  expect_error(validate_degree_roadmaps(r, catalog()), "level disagrees")
  r <- roadmaps(); r$nodes$course_level[r$nodes$kind == "choice"] <- ""
  expect_error(validate_degree_roadmaps(r, catalog()), "Invalid roadmap course level")
  r <- roadmaps(); r$plans$upper_level_from_semester <- "1"
  expect_error(validate_degree_roadmaps(r, catalog()), "early-coursework stage")
  r <- roadmaps(); r$courses$subject_course[r$courses$node_id == "phys1"] <- "PHYS 1320"
  expect_error(validate_degree_roadmaps(r, catalog()), "components disagree")
})

# ── The loaded institution's own catalog ─────────────────────────────────────

# Integrity of whichever institution is loaded (UNM by default): its authored
# files, not the planner, are under test. A demo or empty catalog passes trivially.
test_that("the loaded institution's roadmaps keep every planning rule in every starting scenario", {
  c <- CEDAR_DEGREE_CATALOG; r <- CEDAR_DEGREE_ROADMAPS
  for (id in c$catalogs$catalog_id) {
    max_load <- as.numeric(r$plans$max_load[r$plans$catalog_id == id])
    upper_start <- as.integer(r$plans$upper_level_from_semester[r$plans$catalog_id == id])
    for (math in r$starts$start_id[r$starts$track == "math"]) {
      for (english in r$starts$start_id[r$starts$track == "english"]) {
        v <- build_degree_roadmap(c, r, id, math, english)
        expect_true(all(v$terms$planned_credits <= max_load))
        expect_equal(v$terms$planned_credits, v$terms$known_credits + v$terms$other_credits)
        expect_equal(sum(v$terms$planned_credits), v$degree_credits - v$completed_credits + v$preparation_credits)
        expect_true(all(v$nodes$semester[v$nodes$course_level == "upper"] >= upper_start))
        expect_true(all(v$nodes$semester[match(v$links$to, v$nodes$node_id)] >=
          v$nodes$semester[match(v$links$from, v$nodes$node_id)] + as.integer(v$links$timing == "before")))
        expect_false(anyDuplicated(paste(v$nodes$semester, v$nodes$row)) > 0L)
        expect_lte(length(unique(v$nodes$row[v$nodes$row_group == "writing"])), 1L)
        expect_lt(max(c(0L, v$allowances$row)), min(v$nodes$row))
        expect_false(anyDuplicated(c(paste(v$nodes$semester, v$nodes$row),
          paste(v$allowances$semester, v$allowances$row))) > 0L)
      }
    }
  }
})

# ── Popup history ────────────────────────────────────────────────────────────

test_that("history components are explicit, and unenumerated groups and new codes stay unresolved", {
  r <- roadmaps()
  expect_setequal(r$courses$subject_course[r$courses$node_id == "chem1"], c("CHEM 1215", "CHEM 1215L"))
  group <- build_degree_course_history(test_sections, test_students, history_edges, r, BIOLOGY, "bioelective")
  expect_equal(group$state, "choice")
  # None of the physical-science options has a section in the window.
  science <- build_degree_course_history(test_sections, test_students, history_edges, r, BIOLOGY, "biosci")
  expect_equal(science$state, "empty")
  expect_setequal(science$missing_courses, r$options$subject_course[r$options$node_id == "biosci"])
  world <- build_degree_course_history(test_sections, test_students, history_edges, r, HISTORY, "histchoice")
  expect_equal(world$state, "ready")
  expect_match(world$note, "alternatives", fixed = TRUE)
  expect_setequal(unique(world$table$subject_course), c("HIST 327", "HIST 395"))
  expect_setequal(world$missing_courses, c("HIST 1160", "HIST 401"))
  course <- build_degree_course_history(test_sections, test_students, history_edges, r, BIOLOGY, "phys1")
  expect_equal(course$state, "empty")
  expect_equal(course$missing_courses, "PHYS 1310")
  expect_error(build_degree_course_history(test_sections, test_students, history_edges, r, BIOLOGY, "nope"),
    "Unknown degree course selection")
})

# Authored components redirect a tile to EC-11's raw rows; no institutional
# records are invented here.
test_that("a course popup keeps every campus, bundle component and alternative at its own grain", {
  r <- roadmaps()
  r$courses$subject_course[r$courses$node_id == "calc1"] <- "SOCI 100"
  h <- build_degree_course_history(test_sections_regstats, test_students_regstats, history_edges, r, BIOLOGY, "calc1")
  expect_setequal(h$table$campus, c("ABQ", "EA"))
  expect_true(is.numeric(h$table$capacity) && is.numeric(h$table$first_day_enrl))
  # Lecture and lab may have different campus histories; never cross their sets.
  r$courses$subject_course[r$courses$node_id == "chem1"] <- c("SOCI 100", "SOCI 101")
  bundle <- build_degree_course_history(test_sections_regstats, test_students_regstats, history_edges, r, BIOLOGY, "chem1")
  expect_equal(nrow(distinct(bundle$table, subject_course, campus)), 3L)
  r$options$subject_course[r$options$node_id == "histchoice"][1:3] <- c("SOCI 100", "SOCI 101", "SOCI 104")
  set <- build_degree_course_history(test_sections_regstats, test_students_regstats, history_edges, r, HISTORY, "histchoice")
  expect_setequal(unique(set$table$subject_course), c("SOCI 100", "SOCI 101", "SOCI 104"))
  full <- set$table[set$table$subject_course == "SOCI 100" & set$table$campus == "ABQ" &
    set$table$part_term == "1" & set$table$term == 202080L, ]
  expect_equal(full$capacity, 100)
  expect_equal(full$first_day_enrl, 107)
  expect_false(anyDuplicated(set$table[c("term", "subject_course", "campus", "college", "part_term")]) > 0L)
})

test_that("allowance popups disclose credit fit and exclude courses the plan already shows", {
  v <- view_of()
  remainder <- v$allowances$node_id[v$allowances$credits == 2]
  selection <- list(type = "allowance", catalog_id = BIOLOGY, math_start = "calculus",
    english_start = "composition", start_season = "fall", node_id = remainder)
  membership <- rbind(planning_gen_ed(), data.frame(subject_course = c("MATH 1512", "ENGL 1120"),
    area_label = c("2: Math", "1: Communication")))
  h <- build_degree_popup_history(test_sections_regstats, test_students_regstats, history_edges,
    catalog(), roadmaps(), membership, selection)
  expect_equal(h$kind, "allowance")
  expect_equal(h$season, "fall")
  expect_equal(h$credits, 2)
  expect_true(all(h$table$credit_fit == "Needs more credits"))
  expect_false(any(c("MATH 1512", "ENGL 1120") %in% h$missing_courses))
  expect_match(h$credit_note, "rather than a complete course", fixed = TRUE)
  expect_match(format_degree_allowance_preview(h), "SOCI 100 · ABQ", fixed = TRUE)
  expect_false(any(c("student_id", "crn") %in% names(h$table)))
  selection$node_id <- "allowance-99-1"
  expect_error(build_degree_popup_history(test_sections_regstats, test_students_regstats, history_edges,
    catalog(), roadmaps(), membership, selection), "Unknown degree allowance")
})

# ── Rendering ────────────────────────────────────────────────────────────────

test_that("the board and popups render the payload; catalog evidence lives in the server modal", {
  withr::local_package("shiny")
  withr::local_package("bslib")
  load_funcs(cedar_base_dir, modules = TRUE)
  ui <- as.character(degreeExplorerUI("degree_explorer", catalog(), roadmaps()))
  expect_match(ui, "degree_explorer-dx_math_start", fixed = TRUE)
  expect_match(ui, "degree_explorer-dx_copy_url", fixed = TRUE)
  v <- view_of(math = "intermediate", english = "stretch")
  board <- as.character(degree_semester_board(v, "board"))
  expect_match(board, "data-roadmap", fixed = TRUE)
  expect_match(board, "Semester 9", fixed = TRUE)
  expect_match(board, "CHEM 1215 + 1215L", fixed = TRUE)
  expect_match(board, "↔ Paired", fixed = TRUE)
  expect_match(board, "3+ prerequisite courses", fixed = TRUE)
  expect_match(board, 'data-card-type="allowance"', fixed = TRUE)
  expect_match(board, "Browse Fall courses", fixed = TRUE)
  expect_match(board, "window.CedarRoadmap.initialize", fixed = TRUE)
  # The browser receives each chain from R and never sees catalog evidence.
  expect_match(board, '"upstream_ids"', fixed = TRUE)
  expect_false(grepl("evidence_quote", board, fixed = TRUE))
  popup <- as.character(degree_tile_modal(degree_roadmap_tile_detail(v, "molecular"), "history"))
  expect_match(popup, "cedar-roadmap-evidence-quote", fixed = TRUE)
  expect_match(popup, "Degree requirements ↗", fixed = TRUE)
  expect_match(popup, "modal-dialog-scrollable", fixed = TRUE)
  allowance <- as.character(degree_tile_modal(degree_roadmap_tile_detail(v, v$allowances$node_id[1]), "history"))
  expect_false(grepl("cedar-roadmap-detail\"", allowance, fixed = TRUE))
  expect_match(allowance, "Degree credit requirements ↗", fixed = TRUE)
  science <- as.character(degree_tile_modal(degree_roadmap_tile_detail(v, "biosci"), "history"))
  expect_equal(lengths(regmatches(science, gregexpr("<li data-option=", science, fixed = TRUE))), 3L)
  expect_match(science, "PHYS 1230 + PHYS 1230L · 4 credits together", fixed = TRUE)
  h <- view_of(HISTORY, "algebra")
  condition <- as.character(degree_tile_modal(degree_roadmap_tile_detail(h, "historiography"), "history"))
  expect_match(condition, "◇ Department permission", fixed = TRUE)
  expect_error(degree_roadmap_tile_detail(h, "nope"), "Unknown degree roadmap tile")
  expect_match(as.character(observedCoursePathsUI("paths", cedar_campus_choices(test_students))),
    "paths-button", fixed = TRUE)
})

test_that("popup history renders one standard table with first-day seats", {
  withr::local_package("shiny")
  r <- roadmaps()
  r$courses$subject_course[r$courses$node_id == "calc1"] <- "SOCI 100"
  h <- build_degree_course_history(test_sections_regstats, test_students_regstats, history_edges, r, BIOLOGY, "calc1")
  html <- as.character(degree_course_history_ui(h, "history_table"))
  expect_match(html, "filled at first class day", fixed = TRUE)
  expect_match(html, "history_table", fixed = TRUE)
  expect_match(html, "Near full", fixed = TRUE)
  expect_match(html, 'data-history-node="calc1"', fixed = TRUE)
  expect_match(html, "cedar-section-heading", fixed = TRUE)
  expect_s3_class(degree_history_table(h), "reactable")
  v <- view_of()
  selection <- list(type = "allowance", catalog_id = BIOLOGY, math_start = "calculus",
    english_start = "composition", start_season = "fall", node_id = v$allowances$node_id[1])
  suggestions <- build_degree_popup_history(test_sections_regstats, test_students_regstats, history_edges,
    catalog(), roadmaps(), planning_gen_ed(), selection)
  expect_s3_class(degree_allowance_table(suggestions), "reactable")
  html <- as.character(degree_allowance_history_ui(suggestions, "suggestion_table"))
  expect_match(html, "Fall course options", fixed = TRUE)
  expect_match(html, "first class day", fixed = TRUE)
  failed <- list(state = "error", kind = "allowance", node_id = "allowance-3-1", note = "Planner stopped")
  expect_match(as.character(degree_allowance_history_ui(failed, "suggestion_table")), "Planner stopped", fixed = TRUE)
})
