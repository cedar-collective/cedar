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
# The module holds no analysis: it collects the course, campus and term type,
# calls get_concurrent_courses_by_major() (cones/concurrent-courses-by-major.R)
# and lays out its payload. It computes only while Other Courses is open, for
# the course the report was run for.
#
# Exported functions:
#   concurrentByMajorUI(id)
#   concurrentByMajorServer(id, ...)

CONCURRENT_BY_MAJOR_TERM_TYPES <- c(Fall = "fall", Spring = "spring", Summer = "summer")

concurrentByMajorUI <- function(id) {
  ns <- NS(id)
  dashboard_subsection(
    "Courses Taken Alongside",
    "What else this course's students take the same term: all of them together, then by major.",
    method = uiOutput(ns("method")),
    radioButtons(ns("term_type"), "Term type", choices = CONCURRENT_BY_MAJOR_TERM_TYPES,
                 selected = "fall", inline = TRUE),
    uiOutput(ns("panels"))
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
# each with its count and its average a term.
.concurrent_by_major_all_card <- function(rows, total) {
  n <- .concurrent_by_major_n
  top <- utils::head(rows, 10)
  cedar_finding_card(
    "All students", scope = paste("the", nrow(top), "most taken"),
    headline = n(total), caption = "student-terms",
    cedar_meter_list(data.frame(
      label = top$subject_course,
      share = top$pct / 100,
      text = paste0(n(top$n_student_terms), " of ", n(total), ", about ", n(round(top$per_term)), " a term"),
      stringsAsFactors = FALSE
    ))
  )
}

.concurrent_by_major_campus <- function(p, campus, ns) {
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
        column(5, .concurrent_by_major_all_card(every, total))
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

# ── Server ───────────────────────────────────────────────────────────────────

# course, campus   reactives: the course the report was run for (its course
#                  id; NULL before a run) and the campus input (NULL means
#                  every campus, each read apart).
# active           reactive: TRUE while Other Courses is the open tab.
# registrations, student_terms, dims, edges
#                  the loaded class list, cedar_student_terms, cedar_dims and
#                  the data edges.
concurrentByMajorServer <- function(id, course, campus, active, registrations, student_terms, dims, edges) {
  moduleServer(id, function(input, output, session) {
    payload <- reactive({
      req(isTRUE(active()), course(), input$term_type)
      withProgress(message = "Counting the courses taken alongside…", value = 0.4, {
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
      tagList(lapply(unique(p$groups$campus), function(cp) .concurrent_by_major_campus(p, cp, session$ns)))
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
