test_that("the scope bar's visible line holds facts; what they mean opens with the codes", {
  facts <- list(`In progress` = c("Fall 2026 (as of Oct 8, 2026)", "Spring 2027 (registration filling)"),
                `Grades through` = "Summer 2026")
  meaning <- "What a term in progress means."
  bar <- htmltools::renderTags(unit_codes_scope(scope_unit_rows, time_facts = facts, time_meaning = meaning))$html
  summary <- regmatches(bar, regexpr("<summary>.*?</summary>", bar))

  expect_equal(lengths(regmatches(summary, gregexpr('class="scope-chip"', summary))), 2L)
  expect_true(grepl("Fall 2026 (as of Oct 8, 2026); Spring 2027 (registration filling)", summary, fixed = TRUE))
  expect_true(grepl("Summer 2026", summary, fixed = TRUE))
  expect_false(grepl(meaning, summary, fixed = TRUE))
  expect_true(grepl(meaning, sub(summary, "", bar, fixed = TRUE), fixed = TRUE))
})

test_that("without time facts the scope bar is the unit and its codes alone", {
  bar <- htmltools::renderTags(unit_codes_scope(scope_unit_rows))$html
  expect_false(grepl('class="scope-chip"', bar, fixed = TRUE))
  expect_true(grepl("Data scope for History (HIST), Arts and Sciences", bar, fixed = TRUE))
})

# ── cedar_section_scope_inputs(): the inputs a page that lists sections asks for ──

test_that("a section page's scope inputs are the ones its shared link restores", {
  # A link is restored into `<prefix>_<field>` (CEDAR_SHARE_SPECS), so the ids
  # the builder writes and the registry's fields have to be the same set.
  for (page in c("Open Seats", "Cancellations")) {
    spec <- CEDAR_SHARE_SPECS[[page]]
    module_id <- sub("-.*$", "", spec$prefix)
    input_prefix <- sub("^[^-]*-", "", spec$prefix)
    html <- htmltools::renderTags(htmltools::tagList(cedar_section_scope_inputs(
      shiny::NS(module_id), input_prefix, test_sections, c(History = "HIST"), 202080)))$html
    ids <- regmatches(html, gregexpr('<select[^>]* id="[^"]+"', html))[[1]]
    ids <- sub('.* id="([^"]+)"', "\\1", ids)
    expect_setequal(ids, paste0(spec$prefix, spec$sep, spec$fields))
  }
})

test_that("the scope inputs come one column per field, in the order asked for", {
  shown <- c("term", "dept", "campus")
  cols <- cedar_section_scope_inputs(identity, "x", test_sections, c(History = "HIST"),
                                     fields = shown)
  expect_length(cols, 3L)
  html <- vapply(cols, function(col) htmltools::renderTags(col)$html, character(1))
  expect_true(all(mapply(function(one, field) grepl(paste0('id="x_', field, '"'), one, fixed = TRUE),
                         html, shown)))
  # Standard widths: Term 2, Department 2, Campus 2 of twelve.
  expect_true(all(grepl('class="col-sm-2"', html, fixed = TRUE)))
})

test_that("the scope inputs open on the default campus, the term given and the level asked for", {
  selected_in <- function(html, id) {
    one <- regmatches(html, regexpr(paste0('(?s)<select[^>]* id="', id, '".*?</select>'), html, perl = TRUE))
    sub('.*value="([^"]*)".*', "\\1", regmatches(one, gregexpr('<option value="[^"]*" selected', one))[[1]])
  }
  render <- function(...) htmltools::renderTags(htmltools::tagList(
    cedar_section_scope_inputs(identity, "x", test_sections, c(History = "HIST"), ...)))$html

  standard <- render(default_term = 202080)
  expect_equal(selected_in(standard, "x_term"), "202080")
  expect_setequal(selected_in(standard, "x_campus"), cedar_campus_default(test_sections))
  expect_equal(selected_in(standard, "x_level"), "lower")
  expect_length(selected_in(standard, "x_college"), 0L)

  # No term given and no level asked for: neither input opens with a choice.
  open <- render(level_selected = NULL)
  expect_length(selected_in(open, "x_term"), 0L)
  expect_length(selected_in(open, "x_level"), 0L)
})

test_that("a page's own width or label replaces the standard one for that field alone", {
  html <- htmltools::renderTags(htmltools::tagList(cedar_section_scope_inputs(
    identity, "x", test_sections, c(History = "HIST"),
    fields = c("pt", "dept"), widths = c(dept = 3), labels = c(pt = "Part of Term"))))$html
  expect_true(grepl('class="col-sm-3"', html, fixed = TRUE))   # Department, widened
  expect_true(grepl('class="col-sm-1"', html, fixed = TRUE))   # Part of term, standard
  expect_true(grepl(">Part of Term<", html, fixed = TRUE))
  expect_true(grepl(">Department<", html, fixed = TRUE))
})

test_that("the scope inputs stop on a field they do not make, or a table without its column", {
  expect_error(cedar_section_scope_inputs(identity, "x", test_sections, c(History = "HIST"),
                                          fields = c("campus", "subject")),
               "fields are distinct names")
  expect_error(cedar_section_scope_inputs(identity, "x", test_sections, c(History = "HIST"),
                                          fields = c("campus", "campus")),
               "fields are distinct names")
  expect_error(cedar_section_scope_inputs(identity, "x", test_sections, c(History = "HIST"),
                                          fields = "campus", widths = c(dept = 3)),
               "named by a field being shown")
  expect_error(cedar_section_scope_inputs(identity, "x", test_sections[, setdiff(names(test_sections), "part_term")],
                                          c(History = "HIST")),
               "needs sections column\\(s\\): part_term")
})

test_that("a folded threshold line says the standard values are in force, or names each one changed", {
  standard <- c(lower = 12, upper = 12, min_enrl = 1)
  labels <- c(lower = "Lower division", upper = "Upper division", min_enrl = "Smallest section listed")
  expect_equal(cedar_threshold_state(list(lower = 12, upper = 12L, min_enrl = 1), standard, labels),
               "standard values")
  expect_equal(cedar_threshold_state(list(lower = 15, upper = 12, min_enrl = 0), standard, labels),
               "changed: Lower division 15 (standard 12); Smallest section listed 0 (standard 1)")
  # An input still blank (not yet bound, or cleared) is not a change.
  expect_equal(cedar_threshold_state(list(lower = NA, upper = NULL, min_enrl = 1), standard, labels),
               "standard values")
  expect_error(cedar_threshold_state(list(grad = 5), standard, c(grad = "Graduate")),
               "none for grad")
})

# ── cedar_rate_scope_inputs(): the inputs a page that reads students over terms asks for ──

test_that("a rate page's scope inputs are the ones its shared link restores", {
  # A link is restored into the spec's ids, so the ids the builder writes and
  # the registry's fields have to be the same set. DFW Rates prefixes its ids;
  # Retention's are bare.
  terms <- sort(unique(test_sections$term))
  campuses <- sort(unique(test_sections$campus))
  term_types <- c(Fall = "fall", Spring = "spring")
  input_ids <- function(html) {
    ids <- c(regmatches(html, gregexpr('<select[^>]* id="[^"]+"', html))[[1]],
             regmatches(html, gregexpr('<div id="[^"]+" class="[^"]*shiny-input-radiogroup', html))[[1]])
    sub('.* id="([^"]+)".*', "\\1", ids)
  }
  for (page in list(list(title = "DFW Rates", prefix = "dr"), list(title = "Retention", prefix = NULL))) {
    spec <- CEDAR_SHARE_SPECS[[page$title]]
    html <- htmltools::renderTags(htmltools::tagList(cedar_rate_scope_inputs(
      shiny::NS(sub("-.*$", "", spec$prefix)), page$prefix, spec$fields,
      choices = list(campus = campuses, from_term = terms, to_term = terms, term_type = term_types))))$html
    expect_setequal(input_ids(html), paste0(spec$prefix, spec$sep, spec$fields))
  }
})

test_that("the rate scope inputs come in the one filter-bar order, whatever order a page names them in", {
  cols <- cedar_rate_scope_inputs(identity, "x", c("term_type", "to_term", "campus"),
                                  choices = list(campus = "ABQ", to_term = 202080L, term_type = c(Fall = "fall")))
  html <- vapply(cols, function(col) htmltools::renderTags(col)$html, character(1))
  expect_length(html, 3L)
  expect_true(all(mapply(function(one, field) grepl(paste0('id="x_', field, '"'), one, fixed = TRUE),
                         html, c("campus", "to_term", "term_type"))))
  # Standard widths: Campus 3, To term 2, Term type 3 of twelve.
  expect_equal(unname(vapply(html, function(one) sub('^<div class="col-sm-([0-9]+)".*', "\\1", one), character(1))),
               c("3", "2", "3"))
})

test_that("the rate scope inputs open where a page says, name the campus they read, and name terms and levels", {
  selected_in <- function(html, id) {
    one <- regmatches(html, regexpr(paste0('(?s)<select[^>]* id="', id, '".*?</select>'), html, perl = TRUE))
    sub('.*value="([^"]*)".*', "\\1", regmatches(one, gregexpr('<option value="[^"]*" selected', one))[[1]])
  }
  render <- function(...) htmltools::renderTags(htmltools::tagList(cedar_rate_scope_inputs(identity, NULL, ...)))$html

  # A teaching campus opens on none (every campus) unless the page picks; a
  # term given as a code is shown by name; a level offers the institution's
  # levels and opens on the first.
  teaching <- render(c("campus", "level", "from_term"), choices = list(campus = c("ABQ", "EA"), from_term = c(202010L, 202080L)))
  expect_length(selected_in(teaching, "campus"), 0L)
  expect_true(grepl(">Campus<", teaching, fixed = TRUE))
  expect_true(grepl("Every campus", teaching, fixed = TRUE))
  expect_true(grepl(paste0(">", fmt_term(202080L), "<"), teaching, fixed = TRUE))
  expect_equal(selected_in(teaching, "from_term"), "202010")
  expect_equal(selected_in(teaching, "level"), names(CEDAR_STUDENT_LEVEL_LABELS)[[1]])
  expect_true(all(vapply(unname(CEDAR_STUDENT_LEVEL_LABELS), function(label) grepl(paste0(">", label, "<"), teaching, fixed = TRUE), logical(1))))

  home <- render(c("campus", "term_type"), campus = "home",
                 choices = list(campus = c("ABQ", "EA"), term_type = c(Fall = "fall", Spring = "spring")),
                 selected = list(campus = "EA", term_type = "spring"))
  expect_equal(selected_in(home, "campus"), "EA")
  expect_true(grepl(">Home campus<", home, fixed = TRUE))
  expect_true(grepl("Every home campus", home, fixed = TRUE))
  expect_true(grepl('value="spring" checked', home, fixed = TRUE))
})

test_that("the rate scope inputs stop on a field they do not make, one with no choices, or a name not shown", {
  expect_error(cedar_rate_scope_inputs(identity, NULL, c("campus", "line"), choices = list(campus = "ABQ")),
               "fields are distinct names")
  expect_error(cedar_rate_scope_inputs(identity, NULL, c("campus", "campus"), choices = list(campus = "ABQ")),
               "fields are distinct names")
  expect_error(cedar_rate_scope_inputs(identity, NULL, c("campus", "to_term"), choices = list(campus = "ABQ")),
               "no choices for to_term")
  expect_error(cedar_rate_scope_inputs(identity, NULL, "campus", choices = list(campus = "ABQ"),
                                       selected = list(level = "UG")),
               "named by a field being shown")
  expect_error(cedar_rate_scope_inputs(identity, NULL, "campus", choices = list(campus = "ABQ"),
                                       widths = c(term_type = 4)),
               "named by a field being shown")
})
