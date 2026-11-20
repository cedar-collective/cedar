# Course Dynamics > Other Courses > Courses Taken Alongside
#
# What else do this course's students take the same term? On each campus,
# first every student together: a treemap of the courses grouped by the
# college that taught them, beside the same courses' shares as bars (one
# figure and its readable list, not two answers). Then the course's own lab
# once, and one card per major (the five largest, then All other majors),
# each listing the courses its students took and the share of the group that
# took each.
#
# Harder Together follows: of those courses, the ones whose students fail
# this course more often than its students of the same term and entering GPA
# who did not take them (get_course_pair_dfw(), cones/course-pair-dfw.R), as
# candidates; the All students bars mark them.
#
# The module holds no analysis: it collects the course, campus and term type,
# calls get_concurrent_courses_by_major() (cones/concurrent-courses-by-major.R)
# and get_course_pair_dfw(), and lays out their payloads. It computes only
# while Other Courses is open, for the course the report was run for.
#
# Exported functions:
#   concurrentByMajorUI(id)
#   concurrentByMajorServer(id, ...)

CONCURRENT_BY_MAJOR_TERM_TYPES <- c(Fall = "fall", Spring = "spring", Summer = "summer")

concurrentByMajorUI <- function(id) {
  ns <- NS(id)
  # Opened by the server while it counts (cedar_with_loading()).
  cedar_loading_overlay(ns("load"), run_button = NULL, emoji = "\U0001f332", loading_label = "Counting the courses taken alongside…",
    dashboard_subsection(
      "Courses Taken Alongside",
      "What else this course's students take the same term: all of them together, then by major.",
      method = uiOutput(ns("method")),
      radioButtons(ns("term_type"), "Term type", choices = CONCURRENT_BY_MAJOR_TERM_TYPES,
                   selected = "fall", inline = TRUE),
      uiOutput(ns("panels"))
    ),
    dashboard_subsection(
      "Harder Together",
      "Which courses taken the same term go with failing this course more often, among students of the same entering GPA.",
      method = uiOutput(ns("pairs_method")),
      uiOutput(ns("pairs_panels"))
    )
  )
}

# ── Layout helpers (no analysis) ─────────────────────────────────────────────

.concurrent_by_major_n <- function(x) format(as.integer(x), big.mark = ",", trim = TRUE)

.concurrent_by_major_terms <- function(meta, campus) {
  terms <- meta$terms$terms[[match(campus, meta$terms$campus)]]
  paste(vapply(terms, fmt_term, character(1)), collapse = ", ")
}

# One major's card: its name and codes, how many student-terms it holds, and
# its courses as bars on the same 0-100% scale as every other card.
.concurrent_by_major_card <- function(g, courses, min_course_n) {
  n <- .concurrent_by_major_n
  scope <- if (is.na(g$program_codes)) paste(n(g$n_majors), "majors") else g$program_codes
  body <- if (nrow(courses) == 0L) {
    tags$p(class = "text-note", paste0(
      "No other course on this campus had ", min_course_n, " or more of them. ",
      "A course they took on another campus is not counted."))
  } else {
    cedar_meter_list(data.frame(
      label = courses$subject_course,
      share = courses$pct / 100,
      text = paste(n(courses$n_student_terms), "of", n(g$n_student_terms)),
      stringsAsFactors = FALSE
    ))
  }
  cedar_finding_card(
    g$group, scope = scope,
    headline = n(g$n_student_terms),
    caption = paste0("student-terms, ", n(g$n_students), " students"),
    body
  )
}

.concurrent_by_major_treemap_id <- function(campus) paste0("treemap_", make.names(campus))

# Every student together: the ten largest of the treemap's courses as bars,
# each with its count and its average a term; a Harder Together candidate is
# marked.
.concurrent_by_major_all_card <- function(rows, total, harder = character(0)) {
  n <- .concurrent_by_major_n
  top <- utils::head(rows, 10)
  cedar_finding_card(
    "All students", scope = paste("the", nrow(top), "most taken"),
    headline = n(total), caption = "student-terms",
    cedar_meter_list(data.frame(
      label = ifelse(top$subject_course %in% harder, paste0(top$subject_course, " \u00b7 harder together"),
                     top$subject_course),
      share = top$pct / 100,
      text = paste0(n(top$n_student_terms), " of ", n(total), ", about ", n(round(top$per_term)), " a term"),
      stringsAsFactors = FALSE
    ))
  )
}

.concurrent_by_major_campus <- function(p, campus, ns, harder = character(0)) {
  n <- .concurrent_by_major_n
  g <- p$groups[p$groups$campus == campus, , drop = FALSE]
  lab <- p$lab[p$lab$campus == campus, , drop = FALSE]
  every <- p$all_courses[p$all_courses$campus == campus, , drop = FALSE]
  total <- sum(g$n_student_terms)
  tagList(
    section_heading(paste0(campus, ": ", n(total), " student-terms in ", p$meta$course,
                           " (", .concurrent_by_major_terms(p$meta, campus), ")"), level = "h4"),
    if (nrow(every) > 0L) {
      fluidRow(
        column(7, plotly::plotlyOutput(ns(.concurrent_by_major_treemap_id(campus)), height = "460px")),
        column(5, .concurrent_by_major_all_card(every, total, harder))
      )
    },
    if (nrow(lab) == 1L) {
      cedar_meter_list(data.frame(
        label = paste0(lab$lab_course, ", its lab"),
        share = lab$pct / 100,
        text = paste0(n(lab$n_student_terms), " of ", n(lab$course_student_terms),
                      ", every major together; left out of the cards"),
        stringsAsFactors = FALSE
      ))
    },
    section_heading("By major", level = "h5"),
    div(class = "finding-card-row", lapply(seq_len(nrow(g)), function(i) {
      .concurrent_by_major_card(
        g[i, , drop = FALSE],
        p$courses[p$courses$campus == campus & p$courses$group == g$group[[i]], , drop = FALSE],
        p$meta$min_course_n
      )
    }))
  )
}

.concurrent_by_major_method <- function(p) {
  m <- p$meta
  type <- tolower(names(CONCURRENT_BY_MAJOR_TERM_TYPES)[CONCURRENT_BY_MAJOR_TERM_TYPES == m$term_type])
  tags$ul(
    tags$li(paste0("A student-term is a student registered in ", m$course, " in one term (RE, RS or RR at the pull); ",
                   "one who took it in two terms counts twice.")),
    tags$li(paste0("The terms are ", m$course, "'s last ", m$n_terms, " ", type, " terms on each campus, through ",
                   fmt_term(m$edge), ", the last term whose enrollment has settled.")),
    tags$li(paste0("The major is the student's primary major that term; a pre-major is its own group. The ",
                   m$n_majors, " largest majors with at least ", m$min_n, " student-terms get a card each, and every ",
                   "other student-term is in All other majors. The codes under a name are the programs behind it.")),
    tags$li(paste0("A course counts when the student was registered in it the same term on the same campus; waitlists ",
                   "and drops are not counted, and neither is a course on another campus. A course is listed when at ",
                   "least ", m$min_course_n, " of the group took it, up to ", m$n_courses, " a card, and its share ",
                   "is of the group's student-terms.")),
    tags$li(paste0("All students: the ", m$n_all, " courses taken by the most student-terms, each grouped under the ",
                   "college that taught it on that campus. A block's area is how many took the course; since each ",
                   "student takes several, the areas understate the shares, so each block carries its share of ",
                   "students. The bars beside it are the ten largest of the same courses.")),
    tags$li(paste0("The course's own lab (", m$course, "L) is taken by most of its students whatever their major, ",
                   "so it is shown once per campus and left out of the treemap and the cards."))
  )
}

# Harder Together on one campus: the lead sentence, the candidates, and every
# pair read behind a disclosure.
.concurrent_pairs_table <- function(rows) {
  shown <- data.frame(
    other_course = rows$other_course, n_student_terms = rows$n_student_terms,
    terms = paste(rows$n_terms_worse, "of", rows$n_terms_read),
    dfw_with = rows$dfw_with_pct / 100, dfw_expected = rows$dfw_expected_pct / 100,
    gap_pts = rows$gap_pts, stringsAsFactors = FALSE)
  reactable::reactable(shown, theme = cedar_tbl_theme, compact = TRUE, defaultPageSize = 10, columns = list(
    other_course = reactable::colDef(name = "Taken alongside", minWidth = 130),
    n_student_terms = cedar_count_coldef("Students taking both"),
    terms = reactable::colDef(name = "Terms worse", align = "right"),
    dfw_with = cedar_percent_coldef("DFW with it"),
    dfw_expected = cedar_percent_coldef("Expected"),
    gap_pts = cedar_points_coldef("Gap (points)")))
}

.concurrent_pairs_campus <- function(r, campus) {
  n <- .concurrent_by_major_n
  m <- r$meta
  rows <- r$pairs[r$pairs$campus == campus, , drop = FALSE]
  cand <- rows[rows$harder_together, , drop = FALSE]
  counts <- m$counts[m$counts$campus == campus, , drop = FALSE]
  lead <- if (nrow(rows) == 0L) {
    paste0("No course taken alongside ", m$course, " on ", campus, " had ", m$min_n,
           " or more of these students, so none is read.")
  } else if (nrow(cand) == 0L) {
    paste0("No course taken alongside ", m$course, " on ", campus, " goes with failing it more often in ",
           m$min_terms, " or more terms, of ", n(nrow(rows)), " read.")
  } else {
    paste0(n(nrow(cand)), " of the ", n(nrow(rows)), " courses read go with failing ", m$course, " on ", campus,
           " more often, in ", m$min_terms, " or more terms: candidates to look into, not causes.")
  }
  tagList(
    section_heading(paste0(campus, ": ", n(counts$n_continuing), " continuing student-terms in ", m$course,
                           " (", fmt_term(min(m$terms)), " to ", fmt_term(max(m$terms)), ")"),
                    level = "h5"),
    tags$p(lead),
    if (nrow(cand) > 0L) .concurrent_pairs_table(cand),
    if (nrow(rows) > 0L) info_panel(
      "Every course read",
      description = paste0("Each course at least ", m$min_n, " of these students took alongside it, largest gap first."),
      .concurrent_pairs_table(rows))
  )
}

.concurrent_pairs_method <- function(r) {
  m <- r$meta
  n <- .concurrent_by_major_n
  per_campus <- vapply(seq_len(nrow(m$counts)), function(i) {
    k <- m$counts[i, ]
    paste0(k$campus, ": ", n(k$n_continuing), " of ", n(k$n_graded), " graded student-terms; ",
           n(k$n_first_term), " in a first term and ", n(k$n_invalid), " with an incomplete record left out; ",
           n(k$n_pairs_small), " courses taken alongside by fewer than ", m$min_n, " not read")
  }, character(1))
  tags$ul(
    tags$li(paste0("Continuing students only: a student needs a GPA entering the term, from earlier UNM grades. ",
                   "A first-term student has none, and courses placed by test scores would top the list for who ",
                   "takes them rather than for the pairing.")),
    tags$li(paste0("For each course taken the same term on the same campus, ", m$course, "'s DFW rate among its ",
                   "takers is set against the rate expected from ", m$course, "'s students of the same term and ",
                   "entering-GPA band (", paste(m$gpa_bands, collapse = ", "), ") who did not take it.")),
    tags$li(paste0("A course is a candidate when its gap is beyond chance (at least ", m$z_min, " standard errors), ",
                   "worse in at least ", m$min_terms, " terms with ", m$min_term_n, " or more students taking both, ",
                   "and worse in most such terms. ", m$course, "'s own lab and the other half of a stretch course ",
                   "are left out.")),
    tags$li(paste0("A candidate says the two go together, not that one causes the other: a heavy term, a program's ",
                   "sequence or a schedule can do the same. Graded terms through ", fmt_term(m$edge), ".")),
    tags$li(paste(per_campus, collapse = ". "), ".")
  )
}

# ── Server ───────────────────────────────────────────────────────────────────

# course, campus   reactives: the course the report was run for (its course
#                  id; NULL before a run) and the campus input (NULL means
#                  every campus, each read apart).
# active           reactive: TRUE while Other Courses is the open tab.
# registrations, student_terms, dims, edges, attempts
#                  the loaded class list, cedar_student_terms, cedar_dims, the
#                  data edges and cedar_attempts.
concurrentByMajorServer <- function(id, course, campus, active, registrations, student_terms, dims, edges,
                                    attempts) {
  moduleServer(id, function(input, output, session) {
    payload <- reactive({
      req(isTRUE(active()), course(), input$term_type)
      cedar_with_loading(session, session$ns("load"), label = "Counting the courses taken alongside…", report_type = "concurrent_by_major", {
        tryCatch(
          get_concurrent_courses_by_major(registrations, student_terms, dims, list(
            course = course(), term_type = input$term_type, campus = campus(), data_edges = edges)),
          error = function(e) {
            showNotification(paste("Courses Taken Alongside:", conditionMessage(e)), type = "error", duration = 10)
            NULL
          }
        )
      })
    })

    pairs <- reactive({
      req(isTRUE(active()), course(), input$term_type)
      cedar_with_loading(session, session$ns("load"), label = "Reading which courses go with failing it…", report_type = "concurrent_by_major", {
        tryCatch(
          get_course_pair_dfw(attempts, student_terms, list(
            course = course(), term_type = input$term_type, campus = campus(), data_edges = edges)),
          error = function(e) {
            showNotification(paste("Harder Together:", conditionMessage(e)), type = "error", duration = 10)
            NULL
          }
        )
      })
    })

    output$pairs_method <- renderUI({
      r <- pairs()
      req(r)
      .concurrent_pairs_method(r)
    })

    output$pairs_panels <- renderUI({
      if (is.null(course())) return(empty_state("Analyze a course to see which courses taken alongside it go with failing it."))
      r <- pairs()
      req(r)
      if (nrow(r$meta$counts) == 0L) {
        return(empty_state(paste0("No graded student-term in ", r$meta$course, " in a ", r$meta$term_type,
                                  " term through ", fmt_term(r$meta$edge), ".")))
      }
      tagList(lapply(r$meta$counts$campus, function(cp) .concurrent_pairs_campus(r, cp)))
    })

    output$method <- renderUI({
      p <- payload()
      req(p)
      .concurrent_by_major_method(p)
    })

    output$panels <- renderUI({
      if (is.null(course())) return(empty_state("Analyze a course to see what its students take alongside it."))
      p <- payload()
      req(p)
      if (nrow(p$groups) == 0L) {
        return(empty_state(paste0("No student was registered in ", p$meta$course, " in a ", p$meta$term_type,
                                  " term through ", fmt_term(p$meta$edge), ". Try another term type.")))
      }
      r <- pairs()
      harder <- function(cp) if (is.null(r)) character(0) else
        r$pairs$other_course[r$pairs$campus == cp & r$pairs$harder_together]
      tagList(lapply(unique(p$groups$campus), function(cp)
        .concurrent_by_major_campus(p, cp, session$ns, harder(cp))))
    })

    # One treemap per campus with all-students courses, drawn into the outputs
    # the panels lay out.
    observe({
      p <- payload()
      req(p)
      for (cp in unique(p$all_courses$campus)) {
        local({
          campus <- cp
          output[[.concurrent_by_major_treemap_id(campus)]] <- plotly::renderPlotly(
            plot_concurrent_courses_treemap(prepare_concurrent_courses_treemap(p, campus))
          )
        })
      }
    })
  })
}
