# Course Dynamics > Downstream > Later Course
#
# Of the analysed course's students, how many took a later course within a set
# number of regular terms, when, and how did they do in it, read by the term
# they took the course, by the grade they earned in it and, behind the
# instructor gate, by their instructor in it?
#
# The module holds no analysis: it collects inputs, calls
# build_later_course() / later_course_balance() (features/later-course.R), and
# lays out that file's tables, chart and sentences.
#
# Every row that names an instructor sits behind the shared instructor gate
# (modules/instructor-gate.R). The breakdown is on the payload either way; it
# is rendered only while the gate is open.
#
# Exported functions:
#   laterCourseUI(id)
#   laterCourseServer(id, ...)
#   downstream_course_choices(opts, include_rollup, dept)   shared with the
#     Course Sequence picker in server.R

LATER_COURSE_WINDOW_CHOICES <- stats::setNames(
  as.character(1:6),
  c("1 regular term", paste(2:6, "regular terms"))
)

# Later-course choices, grouped by whether the course belongs to the analysed
# course's department and labelled with how many of its students took each
# within the window. The groups are navigation, not evidence for or against a
# sequence: real pathways cross departments.
downstream_course_choices <- function(opts, include_rollup = FALSE, dept = NULL) {
  if (is.null(opts) || nrow(opts) == 0) return(list())
  label <- function(d) stats::setNames(
    d$subject_course,
    paste0(d$subject_course, " — ", format(d$n_students, big.mark = ",", trim = TRUE),
           " students (", formatC(d$pct_of_x, format = "f", digits = 1), "%)")
  )
  same <- opts[opts$same_dept %in% TRUE, , drop = FALSE]
  other <- opts[!(opts$same_dept %in% TRUE), , drop = FALSE]
  if (is.null(dept)) dept <- unique(same$department)
  dept <- dept[!is.na(dept) & nzchar(dept)]
  out <- list()
  if (include_rollup && nrow(same) > 1) {
    out[["Summary"]] <- stats::setNames(
      CR_ROLLUP_SENTINEL,
      paste0("All later courses in this department (", nrow(same), ")")
    )
  }
  if (nrow(same) > 0) {
    out[[paste0("Same department", if (length(dept) == 1L) paste0(" (", dept, ")"))]] <- label(same)
  }
  if (nrow(other) > 0) out[["Other departments"]] <- label(utils::head(other, 40))
  out
}

laterCourseUI <- function(id) {
  ns <- NS(id)
  tagList(
    subtab_header("Later Course", cedar_definition_summary("downstream-outcomes")),
    cedar_definition_panel("downstream-outcomes"),
    fluidRow(
      column(5, uiOutput(ns("picker"))),
      column(2, selectInput(ns("window_terms"), "Within", choices = LATER_COURSE_WINDOW_CHOICES,
                            selected = as.character(DOWNSTREAM_DEFAULT_WINDOW))),
      column(2, numericInput(ns("min_n"), "Min students:", value = 10, min = 5, max = 100)),
      column(3, br(), actionButton(ns("run"), "Show Outcomes", icon = icon("play"), class = "btn-primary"))
    ),
    helpText(
      "Each course in the list shows how many of this course's students took it within the window. ",
      "Students are grouped by the campus that taught them this course; the later course counts on any campus."
    ),
    uiOutput(ns("results"))
  )
}

# ── Layout helpers (no analysis) ─────────────────────────────────────────────

.later_course_fmt_n <- function(x) format(as.integer(x), big.mark = ",", scientific = FALSE, trim = TRUE)

.later_course_fmt_pct <- function(x) {
  if (length(x) == 0L || is.na(x)) "—" else paste0(formatC(x, format = "f", digits = 1), "%")
}

.later_course_table <- function(d, columns, page_size = 25L, searchable = FALSE, ...) {
  reactable::reactable(
    d, theme = cedar_tbl_theme, striped = TRUE, highlight = TRUE, compact = TRUE,
    searchable = searchable, defaultPageSize = page_size,
    showPageSizeOptions = nrow(d) > page_size, pageSizeOptions = c(10, 25, 50),
    columns = columns, ...
  )
}

.later_course_campus_coldef <- function() reactable::colDef(name = "Campus", maxWidth = 90)

.later_course_rate_coldef <- function(name) {
  reactable::colDef(name = name, align = "right", na = "—",
                    format = reactable::colFormat(digits = 1, suffix = "%"))
}

# Column name for the pass rate in Y. For a set, the first term with any member
# passes only when everything taken from the set that term passed.
.later_course_passed_label <- function(r) {
  if (isTRUE(r$rollup)) "Passed what they took" else paste("Passed", r$course_y_label)
}

# One campus's counts, from everyone who took X down to the pass rate in Y:
# what is removed, what remains, and what became of it.
.later_course_steps <- function(steps) {
  sign <- c(total = "", removed = "−", denominator = "=", count = "",
            outcome = "", detail = "", unknown = "")
  row_class <- c(total = NA, removed = "text-muted", denominator = "fw-semibold",
                 count = "fw-semibold", outcome = NA, detail = "text-muted",
                 unknown = "text-muted")
  label_class <- c(detail = "ps-4", outcome = "ps-3", unknown = "ps-3")
  tags$table(
    class = "table table-sm mb-2",
    tags$tbody(lapply(seq_len(nrow(steps)), function(i) {
      role <- steps$role[[i]]
      cls <- row_class[[role]]
      tags$tr(
        class = if (!is.na(cls)) cls,
        tags$td(class = "text-end text-nowrap", paste0(sign[[role]], .later_course_fmt_n(steps$n[[i]]))),
        tags$td(class = if (role %in% names(label_class)) label_class[[role]], steps$label[[i]])
      )
    }))
  )
}

# The two rates for one campus, with the counts behind them open underneath.
.later_course_headline_row <- function(h, r) {
  y <- r$course_y_label
  window <- paste0(r$window_terms, " regular term", if (r$window_terms == 1L) "" else "s")
  small <- paste0("fewer than ", r$min_n, " students")
  n <- .later_course_fmt_n
  div(
    class = "stat-row",
    div(class = "stat-row-label",
        tags$span(paste0(r$course_x, " taught on")),
        tags$span(class = "stat-row-code", h$campus)),
    fluidRow(
      column(4, cedar_stat_card(
        .later_course_fmt_pct(h$pct_took_y),
        paste0("took ", y, " within ", window),
        if (is.na(h$pct_took_y)) small else paste0(n(h$n_took_y), " of ", n(h$n_eligible), " who could have")
      )),
      column(4, cedar_stat_card(
        .later_course_fmt_pct(h$pct_pass),
        if (isTRUE(r$rollup)) "of them passed what they took" else paste0("of them passed ", y),
        if (is.na(h$pct_pass)) small else paste0(n(h$n_pass), " of ", n(h$n_graded), " with a grade")
      ))
    ),
    .later_course_steps(h$steps),
    if (isTRUE(r$rollup)) tags$p(class = "text-hint", paste0(
      "Nobody is removed for having passed one of these courses: passing one does not rule out the others. ",
      n(h$n_passed_y_before_x), " had passed one before ", r$course_x, " and ",
      n(h$n_passed_y_same_term), " in the same term; Course Order, below, counts them by year."))
    else if (h$n_passed_y_same_term > 0) tags$p(class = "text-hint", paste0(
      n(h$n_passed_y_same_term), " passed ", y, " in the same term as ", r$course_x,
      ". They stay among the ", n(h$n_eligible), " and count as taking ", y,
      " only if they enrolled in it again later."))
  )
}

.later_course_term_reactable <- function(d, r) {
  x <- r$course_x
  y <- r$course_y_label
  .later_course_table(d, list(
    campus = .later_course_campus_coldef(),
    term_x = reactable::colDef(name = paste("Term of", x), cell = function(v) fmt_term(v), minWidth = 110),
    term_type = reactable::colDef(show = FALSE),
    n_in_x = cedar_count_coldef(paste("Took", x)),
    n_eligible = cedar_count_coldef("Could have taken it"),
    n_took_y = reactable::colDef(show = FALSE),
    pct_took_y = cedar_pct_count_coldef(paste("Took", y), d$n_eligible, of = TRUE),
    n_graded = reactable::colDef(show = FALSE),
    n_pass = reactable::colDef(show = FALSE),
    pct_pass = cedar_pct_count_coldef(.later_course_passed_label(r), d$n_graded, of = TRUE),
    n_not_graded = cedar_count_coldef("Not yet graded")
  ), defaultSorted = list(term_x = "desc"))
}

.later_course_band_reactable <- function(d, r) {
  .later_course_table(d, list(
    campus = .later_course_campus_coldef(),
    x_band = reactable::colDef(name = paste("Grade in", r$course_x), minWidth = 130, sortable = FALSE),
    n_eligible = cedar_count_coldef("Could have taken it"),
    n_took_y = reactable::colDef(show = FALSE),
    pct_took_y = cedar_pct_count_coldef(paste("Took", r$course_y_label), d$n_eligible, of = TRUE),
    n_graded = reactable::colDef(show = FALSE),
    n_pass = reactable::colDef(show = FALSE),
    pct_pass = cedar_pct_count_coldef(.later_course_passed_label(r), d$n_graded, of = TRUE)
  ))
}

.later_course_timing_reactable <- function(d, r) {
  y <- r$course_y_label
  .later_course_table(d, list(
    campus = .later_course_campus_coldef(),
    when = reactable::colDef(name = paste("Took", y), minWidth = 150, sortable = FALSE),
    n = cedar_count_coldef("Students"),
    pct_of_continuers = .later_course_rate_coldef(paste("Share of those who took", y)),
    cum_pct_of_eligible = .later_course_rate_coldef("Had taken it by then, of all who could")
  ))
}

.later_course_instructor_reactable <- function(d, r) {
  x <- r$course_x
  y <- r$course_y_label
  bands <- names(GRADE_LETTER_BANDS)
  passed <- .later_course_passed_label(r)
  band_cols <- unlist(lapply(bands, function(b) {
    stats::setNames(
      list(cedar_pct_count_coldef(paste0("After ", b), d[[paste0("graded_", b)]], of = TRUE),
           reactable::colDef(show = FALSE)),
      c(paste0("pass_", b), paste0("graded_", b))
    )
  }), recursive = FALSE)
  .later_course_table(
    d,
    c(list(
      campus = .later_course_campus_coldef(),
      instructor = reactable::colDef(name = paste("Instructor in", x), minWidth = 170),
      n_eligible = cedar_count_coldef(paste("Could have taken", y)),
      pct_x_pass = .later_course_rate_coldef(paste("Passed", x)),
      pct_x_a_or_b = .later_course_rate_coldef(paste("A or B in", x)),
      n_took_y = reactable::colDef(show = FALSE),
      pct_took_y = cedar_pct_count_coldef(paste("Took", y), d$n_eligible, of = TRUE),
      n_graded = reactable::colDef(show = FALSE),
      n_pass = reactable::colDef(show = FALSE),
      pct_pass = cedar_pct_count_coldef(passed, d$n_graded, of = TRUE),
      n_dfw = reactable::colDef(show = FALSE),
      pct_dfw = cedar_pct_count_coldef(paste("DFW in", y), d$n_graded, of = TRUE)
    ), band_cols),
    searchable = TRUE,
    columnGroups = list(
      reactable::colGroup(name = paste0(passed, ", by grade in ", x), columns = paste0("pass_", bands))
    )
  )
}

.later_course_order_reactable <- function(d, r) {
  x <- r$course_x
  y <- r$course_y_label
  .later_course_table(d, list(
    campus = .later_course_campus_coldef(),
    acad_year = reactable::colDef(name = "Academic year"),
    students_taking_x = cedar_count_coldef(paste("Took", x)),
    passed_y_before_x = cedar_count_coldef(paste("Passed", y, "before")),
    passed_y_same_term = cedar_count_coldef(paste("Passed", y, "the same term")),
    passed_y_before_or_same = cedar_count_coldef("Either"),
    pct_before_or_same = .later_course_rate_coldef("Either, %")
  ))
}

# Whether the two largest instructor groups started alike, or why that cannot
# be said.
.later_course_balance_section <- function(r) {
  b <- r$balance
  x <- r$course_x
  title <- "Did the Two Largest Instructor Groups Start Alike?"
  if (is.null(b)) {
    return(dashboard_subsection(
      title, "The balance check could not be built for this run; the rates above do not depend on it."))
  }
  if (is.null(b$balance)) {
    return(dashboard_subsection(
      title,
      paste0("A balance check compares two instructors' students who went on to ", r$course_y_label,
             ", and needs ", b$min_n, " such students in each group. ", b$n_comparable, " of ",
             b$n_groups, " instructor groups have that many, so no two can be compared.")
    ))
  }
  smd <- b$balance$smd_table
  dashboard_subsection(
    title,
    paste0("Students of ", b$reference_instructor, " (", b$reference_campus, ", ", b$n_treatment,
           ") and of ", b$comparison_instructor, " (", b$comparison_campus, ", ", b$n_control,
           ") who went on to ", r$course_y_label, ", measured as they entered ", x,
           ". This changes nothing above: it says whether those two groups began alike, which a reader needs before reading a gap between their rows as anything about the instructors."),
    if (is.null(smd) || nrow(smd) == 0L) tags$p(class = "text-note", "No balance data.") else tagList(
      cedar_balance_summary(b$balance),
      reactable::reactable(
        cedar_balance_smd_rows(smd, c(b$reference_instructor, b$comparison_instructor)),
        theme = cedar_tbl_theme, compact = TRUE, striped = TRUE, pagination = FALSE
      )
    )
  )
}

# The whole result. `access` is whether the instructor gate is open now.
later_course_view <- function(r, ns, access) {
  x <- r$course_x
  y <- r$course_y_label
  window <- paste0(r$window_terms, " regular term", if (r$window_terms == 1L) "" else "s")
  types <- later_course_term_types(r)
  tagList(
    div(class = "scope-bar scope-bar--stacked", later_course_scope_note(r)),
    dashboard_section(
      paste0(x, " → ", y),
      paste0("Students who took ", x, " and had ", window, " afterwards to take ", y,
             ", all terms pooled. The pass rate is among those who took it and have a grade. Under each pair of rates are the counts they come from."),
      if (isTRUE(r$rollup)) tags$p(class = "text-hint", paste0(
        "Each student counts once, at the first term they took any of these courses, and passed only if they passed everything they took from them that term: ",
        paste(r$course_y, collapse = ", "), ".")),
      lapply(later_course_headline(r), .later_course_headline_row, r = r)
    ),
    dashboard_subsection(
      "Over Time",
      paste0("The same two rates by the term students took ", x, ". Read one term type at a time: a Fall cohort and a Spring one are different students. A term needs ",
             r$min_n, " students for a rate; a recent term's students may not all be graded in ", y,
             " yet, and the table counts them. Each term type has its own lines. The sentences under the chart judge each line across all of its terms: its slope a year beside the slope that chance and the terms' own scatter would give with no trend."),
      checkboxGroupInput(ns("term_type"), "Term types",
                         choices = stats::setNames(types, tools::toTitleCase(types)),
                         selected = r$main_term_type, inline = TRUE),
      plotly::plotlyOutput(ns("trend_plot"), height = "340px"),
      uiOutput(ns("trend_text")),
      reactable::reactableOutput(ns("term_table"))
    ),
    dashboard_subsection(
      paste0("Results in ", y, " by Grade in ", x),
      paste0("The grade a student earned in ", x, " separates their later results more than anything else here. Each rate is shown with its denominator; a rate for fewer than ",
             r$min_n, " students is not shown."),
      .later_course_band_reactable(later_course_band_table(r), r)
    ),
    dashboard_subsection(
      paste0("When They Took ", y),
      paste0("Regular terms after ", x, " among the students who took ", y,
             " within the window; a summer course counts toward the next regular term."),
      .later_course_timing_reactable(later_course_timing_table(r), r)
    ),
    dashboard_subsection(
      paste0("By Instructor in ", x),
      paste0("Students grouped by their instructor in their first attempt at ", x, ". Read the ", x,
             " columns first: an instructor who passed fewer students sends a stronger group on, so their students' later pass rate can be higher without those students being better prepared. The last columns compare students with the same grade in ",
             x, ". Not a measure of teaching and not a basis for evaluating anyone."),
      if (access) .later_course_instructor_reactable(later_course_instructor_table(r), r)
      else instructorGateUI(ns("instructor_gate"))
    ),
    if (access) .later_course_balance_section(r),
    dashboard_subsection(
      "Course Order",
      paste0("Students who had already passed ", y, " before ", x, " or in the same term, by the academic year of their first ",
             x, " attempt. A strictly earlier pass leaves the denominator above",
             if (isTRUE(r$rollup)) " for a single later course; for a set nobody leaves" else "",
             "; a same-term pass stays in it. Either is their union, not their sum."),
      .later_course_order_reactable(later_course_order_table(r), r)
    )
  )
}

# ── Server ───────────────────────────────────────────────────────────────────

# course, campus      reactives: the Course Dynamics course (its course id)
#                     and campus inputs (campus NULL means every campus).
# students, attempts, programs, applicants, student_terms, edges
#                     CEDAR tables and the data edges; applicants may be NULL.
# default_options     reactive: get_downstream_course_options() at the default
#                     window, shared with the Course Sequence picker.
# instructor_access   the session's shared instructor-gate flag.
# instructor_password the configured password ("" when none is).
laterCourseServer <- function(id, course, campus, students, attempts, programs, applicants,
                              student_terms, edges, default_options, instructor_access,
                              instructor_password) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    result <- reactiveVal(NULL)
    instructorGateServer("instructor_gate", instructor_access, instructor_password,
                         what = "Later-course results by instructor")

    # A result always describes the course and campus above it.
    observeEvent(list(course(), campus()), result(NULL), ignoreInit = TRUE)

    window_terms <- reactive(as.integer(input$window_terms %||% DOWNSTREAM_DEFAULT_WINDOW))

    course_options <- reactive({
      req(course())
      k <- window_terms()
      tryCatch(
        if (identical(k, DOWNSTREAM_DEFAULT_WINDOW)) default_options() else {
          get_downstream_course_options(students, attempts, course(), list(
            campus = campus(), window_terms = k, min_n = 15L, data_edges = edges))
        },
        error = function(e) {
          showNotification(paste("Later-course list:", conditionMessage(e)), type = "error", duration = 10)
          NULL
        }
      )
    })

    output$picker <- renderUI({
      choices <- downstream_course_choices(course_options(), include_rollup = TRUE)
      offered <- unlist(choices, use.names = FALSE)
      selectizeInput(
        ns("course_y"), "Later course(s)", choices = choices,
        selected = intersect(isolate(input$course_y), offered), multiple = TRUE, width = "100%",
        options = list(placeholder = if (length(offered) > 0) "Choose one or more…"
                                     else "No later course had 15 students")
      )
    })

    observeEvent(input$run, {
      req(course())
      y <- input$course_y
      if (length(y) == 0) {
        showNotification("Choose at least one later course.", type = "warning")
        return()
      }
      if (CR_ROLLUP_SENTINEL %in% y) {
        opts <- course_options()
        y <- union(setdiff(y, CR_ROLLUP_SENTINEL), opts$subject_course[opts$same_dept %in% TRUE])
      }
      result(NULL)
      opt <- list(course_x = course(), course_y = y, campus = campus(),
                  window_terms = window_terms(), min_n = as.integer(input$min_n %||% 10L),
                  data_edges = edges)
      withProgress(message = "Following students into the later course…", value = 0.3, {
        payload <- tryCatch(
          build_later_course(students, attempts, opt),
          error = function(e) {
            showNotification(paste("Later Course:", conditionMessage(e)), type = "error", duration = 10)
            NULL
          }
        )
        if (!is.null(payload) && !is.null(programs)) {
          setProgress(0.8, detail = "instructor balance")
          # The outcomes stand without the balance check; the page says it is
          # missing rather than failing the run.
          payload <- tryCatch(
            later_course_balance(payload, students, attempts, programs, applicants, student_terms,
                                 list(data_edges = edges)),
            error = function(e) {
              showNotification(paste("Instructor balance check unavailable:", conditionMessage(e)),
                               type = "warning", duration = 8)
              payload
            }
          )
        }
        result(payload)
        setProgress(1)
      })
    })

    output$results <- renderUI({
      r <- result()
      if (is.null(r)) return(empty_state("Choose a later course, then click Show Outcomes."))
      later_course_view(r, ns, isTRUE(instructor_access()))
    })

    output$trend_plot <- plotly::renderPlotly({
      r <- result()
      req(r, length(input$term_type) > 0)
      p <- plot_later_course_trend(r, input$term_type)
      req(!is.null(p))
      p
    })
    output$trend_text <- renderUI({
      r <- result()
      req(r, length(input$term_type) > 0)
      sentences <- later_course_trend_sentences(r, input$term_type)
      if (length(sentences) == 0L) {
        return(tags$p(class = "text-note", paste0("No term of this type has ", r$min_n, " students to give a rate.")))
      }
      tags$ul(lapply(sentences, tags$li))
    })
    output$term_table <- reactable::renderReactable({
      r <- result()
      req(r, length(input$term_type) > 0)
      .later_course_term_reactable(later_course_term_table(r, input$term_type), r)
    })
  })
}
