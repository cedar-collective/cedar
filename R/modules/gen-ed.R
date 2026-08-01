# Minimum graded attempts per group before a rate is reported.
#
# This was a "Min N" filter box on the Gen Ed filter bar. It was removed as a
# user control because it reads as a course-level filter, where it does nothing
# useful — Gen Ed courses are large and always clear it. The rule still matters
# at finer grains: get_course_outcome_rates() applies it to whatever
# `group_cols` it is given, including the instructor-level breakdown behind the
# restricted DFW view, where it is the small-cell guard that stops a rate being
# published for a handful of students. Fixing it here keeps that guard and
# removes the ability to dial it down to 1 from the UI.
GEN_ED_MIN_N <- 5L

# Most departments a comparison card wall will render before falling back to the
# single benchmark row. Past roughly a dozen rows the cards stop being scannable
# and the Department Summary table is the better read.
GEN_ED_MAX_DEPT_ROWS <- 12L


gen_ed_term_choices <- function(sections, current_term = NULL) {
  terms <- sort(unique(sections$term[!is.na(sections$term)]))
  if (!is.null(current_term)) terms <- terms[terms <= current_term]
  stats::setNames(terms, vapply(terms, fmt_term, character(1)))
}


gen_ed_dept_sections <- function(sections, dept = NULL) {
  dept_val <- if (is.function(dept)) dept() else dept
  if (is.null(dept_val) || length(dept_val) == 0 || !nzchar(dept_val[1])) return(sections)

  gen_ed_lu <- gen_ed_course_lookup()
  sections %>%
    dplyr::filter(
      department %in% dept_val,
      subject_course %in% gen_ed_lu$subject_course
    )
}


gen_ed_area_choices <- function(sections) {
  areas <- sort(unique(sections$gen_ed_area[!is.na(sections$gen_ed_area)]))
  stats::setNames(areas, paste("Area", areas))
}


genEdExploreUI <- function(id, sections, dept_choices, current_term = NULL, default_term = NULL) {
  ns <- NS(id)
  term_choices <- gen_ed_term_choices(sections, current_term)
  snapshot_term <- resolve_default_term_choice(
    term_choices,
    default_term = default_term,
    fallback_term = current_term
  )
  area_choices <- gen_ed_area_choices(sections)

  tagList(
    filter_bar(
      "Gen Ed",
      "Aggregate view of Gen Ed enrollment and grade outcomes.",
      fluidRow(class = "explore-filter-row",
        # Campus gets 2 columns so the default ABQ + EA pair sits on one line.
        column(2,
          selectInput(ns("ge_campus"), "Campus", multiple = TRUE,
            choices = sort(unique(sections$campus[!is.na(sections$campus)])),
            selected = intersect(c("ABQ", "EA"), unique(sections$campus)))
        ),
        column(1,
          selectInput(ns("ge_college"), "College", multiple = TRUE,
            choices = sort(unique(sections$college[!is.na(sections$college)])))
        ),
        column(2,
          selectizeInput(ns("ge_from_term"), "From term",
            choices = term_choices, selected = snapshot_term)
        ),
        column(2,
          selectizeInput(ns("ge_to_term"), "To term",
            choices = term_choices, selected = snapshot_term)
        ),
        column(2,
          selectizeInput(ns("ge_dept"), "Department", multiple = TRUE,
            choices = dept_choices)
        ),
        column(2,
          selectInput(ns("ge_gen_ed_area"), "Gen Ed Area", multiple = TRUE,
            choices = area_choices)
        ),
        # Min N is no longer a user control — see GEN_ED_MIN_N in the server.
        column(1,
          filter_actions(
            actionButton(ns("ge_button"), "Run", class = "btn-primary btn-sm", icon = icon("play"))
          )
        )
      )
      # Scope stripe removed: it restated the same course/department/enrollment
      # counts that the summary cards show immediately below, in prose.
    ),

    cedar_loading_overlay(id, "ge_button", emoji = "\U0001f393",
      report_type = "gen-ed-explore", fresh_default = 12,

      subtab_header(
        "Gen Ed Overview",
        "The comparative view of Gen Ed: how one department's courses stack up ",
        "against Gen Ed as a whole, and how peer departments compare with each ",
        "other. Select departments to get a labelled card row for each, measured ",
        "against the overall benchmark. For one department's own Gen Ed detail, ",
        "use Dept Trends > Gen Ed."
      ),

      uiOutput(ns("summary_cards")),

      dashboard_section(
        "Who Takes Gen Ed, and How",
        "Delivery mode and the mix of majors sitting in Gen Ed courses across the selected terms.",
        fluidRow(
          column(6,
            dashboard_subsection(
              "Enrollment by Modality",
              "Face-to-face versus online enrollment each term.",
              plotlyOutput(ns("enrl_modality"), height = "300px")
            )
          ),
          column(6,
            dashboard_subsection(
              "Major Mix in Gen Ed Courses",
              "Which majors the Gen Ed seats are serving.",
              plotlyOutput(ns("major_mix"), height = "300px")
            )
          )
        ),
        dashboard_subsection(
          "Top Gen Ed Course Enrollment Over Time",
          "The highest-enrolling Gen Ed courses, with the average trend across them.",
          plotlyOutput(ns("enrl_course"), height = "360px")
        )
      ),

      dashboard_section(
        "Department Summary",
        "Gen Ed teaching load by department: how many courses each offers and how much enrollment it carries.",
        uiOutput(ns("dept_table_ui"))
      ),

      dashboard_section(
        "DFW Rates by Course",
        tagList(
          tags$p(
            class = "cedar-dashboard-section-description",
            "Grade outcomes for each Gen Ed course. ",
            tags$strong("DFW % counts non-passing grades plus late withdrawals (W)"),
            " as a share of graded attempts, and equals Below C % + W % — the two are ",
            "computed separately from their own counts, so they are a check on each other."
          ),
          tags$p(
            class = "cedar-dashboard-section-description",
            tags$strong("Early drops are not part of DFW."), " Students who dropped before ",
            "the grade deadline are excluded from both the numerator and the denominator. ",
            "Early Drop % is shown for context and uses a different base (attempts plus early ",
            "drops), so it does not add into the other columns."
          )
        ),
        uiOutput(ns("dfw_table_ui"))
      ),

      dashboard_section(
        "Grade Distribution",
        "Full grade spread across the selected Gen Ed courses.",
        uiOutput(ns("grade_table_ui"))
      )
    )
  )
}


deptProfileGenEdUI <- function(id, sections = NULL, current_term = NULL, dept = NULL) {
  ns <- NS(id)

  tagList(
    # Header instead of a scope strip and all-time stat cards. The cards
    # reported whole-range totals that this department-scoped view does not act
    # on, and the strip restated the scope already shown under the Dept Trends
    # filter bar. What is worth saying here is which population each number
    # below is drawn from.
    subtab_header(
      "Gen Ed",
      "This department's Gen Ed courses across the available terms. ",
      "Enrollment figures come from section records. The grade and DFW tables ",
      "count individual students who finished with a final grade or a ",
      "withdrawal, so their totals run lower than the enrollment figures."
    ),
    dashboard_section(
      "Gen Ed Enrollment",
      "Department-scoped Gen Ed enrollment across available terms.",
      fluidRow(
        column(6,
          dashboard_subsection(
            "Enrollment by Modality",
            "F2F and online enrollment patterns in the selected Gen Ed scope.",
            plotlyOutput(ns("enrl_modality"), height = "260px")
          )
        ),
        column(6,
          dashboard_subsection(
            "Major Mix",
            "Majors represented in this department's Gen Ed courses.",
            plotlyOutput(ns("major_mix"), height = "260px")
          )
        )
      ),
      dashboard_subsection(
        "Course Enrollment Over Time",
        "Quick-glance enrollment trends for Gen Ed courses in this department.",
        plotlyOutput(ns("enrl_course"), height = "320px")
      ),
      dashboard_subsection(
        "F2F vs Online by Course",
        "Enrollment split by campus modality for each Gen Ed course.",
        plotlyOutput(ns("enrl_course_modality"), height = "320px")
      )
    ),
    dashboard_section(
      "Course Outcomes",
      "Course-level DFW rates and restricted instructor outcome views for the selected Gen Ed scope. Instructor rows are descriptive associations, not causal evidence.",
      dashboard_subsection(
        "DFW Rates by Course",
        "Early Drop % uses attempts plus early drops, while later outcome rates use attempts.",
        uiOutput(ns("dfw_table_ui"))
      ),
      uiOutput(ns("instructor_dfw_access"))
    )
  )
}


gen_ed_render_table <- function(data, columns = NULL, defaultPageSize = 10) {
  if (!is.null(columns)) columns <- columns[names(columns) %in% names(data)]
  reactable::reactable(
    data,
    columns = columns,
    defaultPageSize = defaultPageSize,
    striped = TRUE,
    highlight = TRUE,
    searchable = TRUE,
    defaultSorted = NULL,
    theme = cedar_tbl_theme
  )
}


gen_ed_empty_table <- function(message) {
  div(class = "alert-box alert-box--info", message)
}


gen_ed_table_output_or_note <- function(data, output_id, message, label = "table") {
  if (is.null(data) || nrow(data) == 0) return(gen_ed_empty_table(message))
  reactable::reactableOutput(output_id)
}


#' @param overlay_id Module id whose cedar_loading_overlay() should be dismissed
#'   when a run finishes. Must equal the `id` passed to cedar_loading_overlay()
#'   in the UI. NULL for the auto-running Dept Trends variant, which is covered
#'   by the parent Dept Trends overlay.
gen_ed_module_server <- function(input, output, session, students, sections, programs,
                                 degrees, current_term, opt_builder, report_timer_name,
                                 run_id = "run", instructor_dfw_enabled = FALSE,
                                 dfw_password = NULL, overlay_id = NULL) {
  data_rv <- reactiveVal(NULL)
  instructor_dfw_authenticated <- reactiveVal(FALSE)
  instructor_dfw_password <- dfw_password %||% Sys.getenv("CEDAR_DFW_PASSWORD", unset = "cedar-dfw-2025")
  associations_require_auth <- function(d) {
    !is.null(d) &&
      !is.null(d$associations) &&
      "instructor_name" %in% names(d$associations)
  }


  run_profile <- function() {
    data_rv(NULL)
    instructor_dfw_authenticated(FALSE)
    # Button-driven (Explore > Gen Ed) shows the shared centered overlay, like
    # every other run-button tab. The auto-running Dept Trends > Gen Ed variant
    # (run_id = NULL) is covered by the parent Dept Trends overlay.
    uses_overlay <- !is.null(overlay_id)
    timer <- start_report_timer(report_timer_name)
    result <- tryCatch(
      get_gen_ed_profile(students, sections, programs, degrees, opt_builder()),
      error = function(e) {
        showNotification(paste("Gen Ed profile failed:", e$message), type = "error")
        NULL
      }
    )
    data_rv(result)
    duration_sec <- end_report_timer(timer)
    if (uses_overlay) {
      signal_load_complete(session, overlay_id, duration_sec = duration_sec,
                           error = is.null(result))
    }
  }

  if (is.null(run_id)) {
    observeEvent(opt_builder(), run_profile(), ignoreInit = FALSE)
  } else {
    observeEvent(input[[run_id]], run_profile())
  }

  # ── Comparative card rows ──────────────────────────────────────────────────
  # This page answers "how do we stack up?" — a chair against all of Gen Ed, a
  # dean across peer departments. So a department's row is only useful next to a
  # reference: counts carry their share of the benchmark, rates carry a signed
  # gap in points. Direction is coloured only where it has a clear meaning (DFW
  # up is worse); enrollment size is shown neutral because bigger is not better.

  .fmt_n   <- function(x) if (is.null(x) || is.na(x)) "-" else format(x, big.mark = ",")
  .fmt_pct <- function(x) if (is.null(x) || is.na(x)) "-" else paste0(x, "%")

  # Share of the benchmark, for count metrics.
  .share_note <- function(value, base) {
    if (is.null(base) || is.na(base) || base == 0 || is.na(value)) return(NULL)
    p(class = "stat-compare", paste0(round(100 * value / base), "% of total"))
  }
  # Signed gap in points, for rate metrics. `worse_when_high` colours it.
  .gap_note <- function(value, base, unit = "", worse_when_high = NA) {
    if (is.null(base) || is.na(base) || is.na(value)) return(NULL)
    gap <- round(value - base, 1)
    if (gap == 0) return(p(class = "stat-compare", "same as overall"))
    cls <- "stat-compare"
    if (!is.na(worse_when_high)) {
      worse <- if (worse_when_high) gap > 0 else gap < 0
      cls <- paste(cls, if (worse) "stat-compare--worse" else "stat-compare--better")
    }
    p(class = cls, paste0(if (gap > 0) "+" else "", gap, unit, " vs overall"))
  }

  .stat_card <- function(value, label, note = NULL) {
    column(2, div(class = "stat-card",
      p(value, class = "stat-num"),
      p(label, class = "stat-lbl"),
      note %||% p(class = "stat-compare", "")
    ))
  }

  # One labelled row. `bench` NULL means this row IS the benchmark.
  .card_row <- function(label, code, s, bench = NULL) {
    is_bench <- is.null(bench)
    second <- if (is_bench) {
      .stat_card(.fmt_n(s$n_departments), "departments")
    } else {
      .stat_card(.fmt_n(s$n_sections), "sections",
                 .share_note(s$n_sections, bench$n_sections))
    }
    div(
      class = paste(c("stat-row", if (is_bench) "stat-row--benchmark"), collapse = " "),
      div(class = "stat-row-label",
        tags$span(label),
        if (!is.null(code) && nzchar(code)) tags$span(class = "stat-row-code", code)
      ),
      fluidRow(
        .stat_card(.fmt_n(s$n_courses), "gen ed courses",
                   if (!is_bench) .share_note(s$n_courses, bench$n_courses)),
        second,
        .stat_card(.fmt_n(s$total_enrl), "section enrollment",
                   if (!is_bench) .share_note(s$total_enrl, bench$total_enrl)),
        .stat_card(.fmt_n(s$avg_section_enrl), "avg enrl / section",
                   if (!is_bench) .gap_note(s$avg_section_enrl, bench$avg_section_enrl)),
        .stat_card(.fmt_n(s$n_students), "distinct students",
                   if (!is_bench) .share_note(s$n_students, bench$n_students)),
        .stat_card(.fmt_pct(s$overall_dfw), "DFW rate",
                   if (!is_bench) .gap_note(s$overall_dfw, bench$overall_dfw,
                                            unit = " pts", worse_when_high = TRUE))
      )
    )
  }

  output$summary_cards <- renderUI({
    d <- data_rv()
    if (is.null(d)) return(NULL)
    s <- d$summary[1, ]

    benchmark <- .card_row("All Gen Ed in scope", NULL, s)

    by_dept <- d$summary_by_dept
    # Per-department rows only when the scope is actually a comparison set. With
    # no department filter this would be one row per department in the
    # university, which is a table, not a card wall.
    if (is.null(by_dept) || nrow(by_dept) < 2 || nrow(by_dept) > GEN_ED_MAX_DEPT_ROWS) {
      return(benchmark)
    }

    dept_rows <- lapply(seq_len(nrow(by_dept)), function(i) {
      row <- by_dept[i, ]
      code <- as.character(row$department)
      name <- if (exists("dept_code_to_name") && code %in% names(dept_code_to_name)) {
        unname(dept_code_to_name[[code]])
      } else code
      .card_row(name, code, row, bench = s)
    })

    tagList(benchmark, dept_rows)
  })

  output$enrl_modality <- renderPlotly({
    d <- data_rv()
    req(!is.null(d), nrow(d$enrl_by_modality) > 0)
    ebm <- d$enrl_by_modality
    chrono <- unique(ebm$term_label[order(ebm$term)])
    modality_colors <- cedar_plotly_palette(ebm$modality, label_order = c("F2F / ABQ", "Online / EA"))
    if ("Unknown" %in% names(modality_colors)) {
      modality_colors["Unknown"] <- unname(CEDAR_SEMANTIC_COLORS["other"])
    }
    plot_ly(ebm, x = ~term_label, y = ~enrl, color = ~modality,
            colors = modality_colors,
            type = "bar",
            hovertemplate = "%{x}: %{y} %{data.name}<extra></extra>") %>%
      layout(
        barmode = "stack",
        xaxis = list(title = "", tickangle = -45, categoryorder = "array", categoryarray = chrono),
        yaxis = list(title = "Enrollment"),
        legend = list(orientation = "h", x = 0, y = 1.1),
        margin = list(t = 30, b = 70, l = 50, r = 10)
      )
  })

  output$enrl_course <- renderPlotly({
    d <- data_rv()
    req(!is.null(d), nrow(d$enrl_by_course) > 0)
    top_n <- if (isTRUE(instructor_dfw_enabled)) NULL else 12L
    plot_gen_ed_course_enrollment_trends(d$enrl_by_course, top_n = top_n)
  })

  output$enrl_course_modality <- renderPlotly({
    d <- data_rv()
    req(!is.null(d), nrow(d$enrl_by_course_modality) > 0)
    top_n <- if (isTRUE(instructor_dfw_enabled)) NULL else 12L
    plot_gen_ed_course_modality_trends(d$enrl_by_course_modality, top_n = top_n)
  })

  output$major_mix <- renderPlotly({
    d <- data_rv()
    req(!is.null(d), !is.null(d$major_mix), nrow(d$major_mix) > 0)

    mm <- d$major_mix %>%
      dplyr::arrange(dplyr::desc(n_enrollments), major_label) %>%
      dplyr::mutate(
        hovertext = paste0(
          major_label,
          "<br>Enrollments: ", format(n_enrollments, big.mark = ","),
          "<br>Distinct students: ", format(n_students, big.mark = ","),
          "<br>Share: ", pct_enrollments, "%"
        )
      )

    color_map <- build_color_map(mm$major_label)
    slice_colors <- unname(color_map[mm$major_label])

    plot_ly(
      mm,
      labels = ~major_label,
      values = ~n_enrollments,
      type = "pie",
      hole = 0.55,
      textinfo = "percent",
      textposition = "inside",
      marker = list(colors = slice_colors, line = list(color = "#ffffff", width = 1)),
      text = ~hovertext,
      hoverinfo = "text"
    ) %>%
      layout(
        showlegend = TRUE,
        legend = list(orientation = "v", x = 1.02, y = 0.5, font = list(size = 10)),
        margin = list(t = 20, b = 10, l = 10, r = 130)
      )
  })

  output$dept_table_ui <- renderUI({
    d <- data_rv()
    if (is.null(d)) return(NULL)
    gen_ed_table_output_or_note(
      d$enrl_by_dept,
      session$ns("dept_table"),
      "No department summary rows are available for this filter scope. If enrollment charts are visible above, check whether the matching section rows are missing department values.",
      "department summary"
    )
  })

  output$dept_table <- reactable::renderReactable({
    d <- data_rv()
    req(!is.null(d), nrow(d$enrl_by_dept) > 0)
    gen_ed_render_table(d$enrl_by_dept, columns = list(
      department = reactable::colDef(name = "Department"),
      n_courses = reactable::colDef(name = "Courses", align = "right"),
      n_sections = reactable::colDef(name = "Sections", align = "right"),
      total_enrl = reactable::colDef(name = "Enrollment", align = "right"),
      avg_section_enrl = reactable::colDef(name = "Avg Enrl / Section", align = "right")
    ))
  })

  output$dfw_table_ui <- renderUI({
    d <- data_rv()
    if (is.null(d)) return(NULL)
    gen_ed_table_output_or_note(
      d$dfw_by_course,
      session$ns("dfw_table"),
      "No DFW table rows met the current filters and Min N. This table uses registered student enrollment records with final grades, so section enrollment can still appear above when grade rows are unavailable or below the threshold.",
      "DFW"
    )
  })

  output$dfw_table <- reactable::renderReactable({
    d <- data_rv()
    req(!is.null(d), nrow(d$dfw_by_course) > 0)
    display <- d$dfw_by_course %>%
      dplyr::select(
        department,
        subject_course,
        n_enrolled,
        early_drop_pct,
        dfw_pct_display,
        below_c_no_w_pct,
        w_pct,
        c_minus_pct,
        d_pct,
        f_pct
      )

    # Every percentage column is on the same 0-100 scale and rendered the same
    # way, so DFW % can be read against Below C % + W % without a unit shift.
    pct_col <- function(label, min_width = 80) {
      reactable::colDef(
        name = label, align = "right", minWidth = min_width,
        cell = function(value) if (!is.na(value)) paste0(value, "%") else "-"
      )
    }

    gen_ed_render_table(display, columns = list(
      department = reactable::colDef(name = "Department"),
      subject_course = reactable::colDef(
        name = "Course", minWidth = 105,
        # Deep-links into Course Dynamics for the same course, using the
        # registered share spec (see CEDAR_SHARE_SPECS in R/trunk/url-state.R).
        cell = function(value) {
          if (is.na(value) || !nzchar(value)) return("")
          htmltools::a(
            href = paste0("?tab=course-dynamics&autorun=true&course=",
                          utils::URLencode(value, reserved = TRUE)),
            title = paste("Open", value, "in Course Dynamics"),
            value
          )
        }
      ),
      n_enrolled = reactable::colDef(name = "Attempts", align = "right"),
      early_drop_pct   = pct_col("Early Drop %", 105),
      dfw_pct_display  = pct_col("DFW %", 90),
      below_c_no_w_pct = pct_col("Below C %", 95),
      w_pct            = pct_col("W %"),
      c_minus_pct      = pct_col("C- %"),
      d_pct            = pct_col("D %"),
      f_pct            = pct_col("F %")
    ))
  })

  observeEvent(input$instructor_dfw_submit, {
    if (identical(input$instructor_dfw_password, instructor_dfw_password)) {
      instructor_dfw_authenticated(TRUE)
      showNotification("Access granted", type = "message", duration = 3)
    } else {
      showNotification("Incorrect password. Please try again.", type = "error", duration = 3)
    }
  }, ignoreInit = TRUE)

  output$instructor_dfw_access <- renderUI({
    if (!isTRUE(instructor_dfw_enabled)) return(NULL)

    d <- data_rv()
    if (is.null(d)) {
      return(empty_state("Run the Gen Ed profile before opening restricted instructor outcomes."))
    }

    ns <- session$ns
    assoc_header <- tagList(
      h5("Course + Instructor Associations", class = "cedar-section-heading"),
      tags$p(
        "Shows instructor-course groups and later major declarations among eligible students; useful for correlation, not causal claims.",
        class = "text-hint"
      )
    )
    instructor_header <- tagList(
      h5("Restricted Instructor DFW", class = "cedar-section-heading"),
      tags$p(
        "Shows instructor-level DFW patterns for the same filtered courses, alongside course averages for context.",
        class = "text-hint"
      )
    )
    assoc_section <- tagList(
      assoc_header,
      uiOutput(ns("assoc_meta")),
      uiOutput(ns("assoc_table_ui"))
    )
    instructor_section <- tagList(
      instructor_header,
      plotlyOutput(ns("instructor_dfw_plot"), height = "320px"),
      uiOutput(ns("instructor_dfw_table_ui"))
    )

    if (!isTRUE(instructor_dfw_authenticated())) {
      return(div(
        class = "alert alert-warning my-3",
        h5(icon("lock"), " Access Restricted"),
        p("Instructor-level associations and DFW outcomes require authentication."),
        assoc_header,
        instructor_header,
        div(
          style = "display: flex; gap: 10px; align-items: flex-start;",
          div(
            style = "flex: 1; max-width: 300px;",
            passwordInput(ns("instructor_dfw_password"), "", placeholder = "Enter password")
          ),
          actionButton(ns("instructor_dfw_submit"), "Access",
            class = "btn-primary", style = "margin-top: 0; white-space: nowrap;")
        )
      ))
    }

    tagList(
      assoc_section,
      hr(),
      instructor_section
    )
  })

  output$instructor_dfw_plot <- renderPlotly({
    d <- data_rv()
    req(
      isTRUE(instructor_dfw_enabled),
      isTRUE(instructor_dfw_authenticated()),
      !is.null(d),
      !is.null(d$instructor_dfw),
      nrow(d$dfw_by_course) > 0,
      nrow(d$instructor_dfw) > 0
    )

    course_avg <- d$dfw_by_course %>%
      dplyr::mutate(subject_course = factor(subject_course, levels = unique(subject_course)))

    instructor_avg <- d$instructor_dfw %>%
      dplyr::mutate(
        subject_course = factor(subject_course, levels = levels(course_avg$subject_course)),
        hovertext = paste0(
          "Instructor: ", instructor_name,
          "<br>Course: ", subject_course,
          "<br>Instructor DFW: ", round(100 * dfw_rate, 1), "%",
          "<br>Attempts: ", n_attempts,
          "<br>Terms: ", n_terms
        )
      )

    role_colors <- cedar_plotly_palette(c("Course average", "Instructor average"))

    p <- plot_ly() %>%
      add_bars(
        data = course_avg,
        x = ~round(100 * dfw_rate, 1),
        y = ~subject_course,
        orientation = "h",
        name = "Course average",
        marker = list(color = unname(role_colors[["Course average"]])),
        hovertemplate = "Course: %{y}<br>Course DFW: %{x:.1f}%<extra></extra>"
      ) %>%
      add_markers(
        data = instructor_avg,
        x = ~round(100 * dfw_rate, 1),
        y = ~subject_course,
        name = "Instructor average",
        marker = list(size = 8, color = unname(role_colors[["Instructor average"]]), opacity = 0.85),
        text = ~hovertext,
        hoverinfo = "text"
      )

    p %>%
      layout(
        barmode = "overlay",
        xaxis = list(title = "DFW %"),
        yaxis = list(title = ""),
        legend = list(orientation = "h", x = 0, y = 1.12),
        margin = list(t = 35, b = 45, l = 80, r = 20)
      )
  })

  output$instructor_dfw_table_ui <- renderUI({
    d <- data_rv()
    if (
      !isTRUE(instructor_dfw_enabled) ||
      !isTRUE(instructor_dfw_authenticated()) ||
      is.null(d)
    ) {
      return(NULL)
    }

    gen_ed_table_output_or_note(
      d$instructor_dfw,
      session$ns("instructor_dfw_table"),
      "No instructor DFW rows met the current filters and Min N. This can happen when course-level rows exist but each instructor group is below the threshold.",
      "instructor DFW"
    )
  })

  output$instructor_dfw_table <- reactable::renderReactable({
    d <- data_rv()
    req(
      isTRUE(instructor_dfw_enabled),
      isTRUE(instructor_dfw_authenticated()),
      !is.null(d),
      !is.null(d$instructor_dfw),
      nrow(d$instructor_dfw) > 0
    )

    gen_ed_render_table(d$instructor_dfw, columns = list(
      subject_course = reactable::colDef(name = "Course"),
      instructor_name = reactable::colDef(name = "Instructor", minWidth = 160),
      n_attempts = reactable::colDef(name = "Attempts", align = "right"),
      n_dfw = reactable::colDef(name = "DFW", align = "right"),
      dfw_rate = reactable::colDef(
        name = "Instructor DFW", align = "right",
        format = reactable::colFormat(percent = TRUE, digits = 1)
      ),
      course_dfw_rate = reactable::colDef(
        name = "Course DFW", align = "right",
        format = reactable::colFormat(percent = TRUE, digits = 1)
      ),
      dfw_diff_pp = reactable::colDef(
        name = "Diff", align = "right",
        cell = function(value) if (!is.na(value)) paste0(value, " pp") else "-"
      ),
      c_minus_pct = reactable::colDef(
        name = "C- %", align = "right",
        cell = function(value) if (!is.na(value)) paste0(value, "%") else "-"
      ),
      d_pct = reactable::colDef(
        name = "D %", align = "right",
        cell = function(value) if (!is.na(value)) paste0(value, "%") else "-"
      ),
      f_pct = reactable::colDef(
        name = "F %", align = "right",
        cell = function(value) if (!is.na(value)) paste0(value, "%") else "-"
      ),
      w_pct = reactable::colDef(
        name = "W %", align = "right",
        cell = function(value) if (!is.na(value)) paste0(value, "%") else "-"
      ),
      early_drop_pct = reactable::colDef(
        name = "Early Drop %", align = "right",
        cell = function(value) if (!is.na(value)) paste0(value, "%") else "-"
      ),
      n_terms = reactable::colDef(name = "Terms", align = "right")
    ))
  })

  output$grade_table_ui <- renderUI({
    d <- data_rv()
    if (is.null(d)) return(NULL)
    gen_ed_table_output_or_note(
      d$grade_dist,
      session$ns("grade_table"),
      "No grade distribution rows are available for this scope. This table requires registered student rows with final grades; current/future terms or sparse departments may have section enrollment without grade detail.",
      "grade distribution"
    )
  })

  output$grade_table <- reactable::renderReactable({
    d <- data_rv()
    req(!is.null(d), nrow(d$grade_dist) > 0)
    gd <- d$grade_dist
    pct_cols <- intersect(paste0(c("A", "B", "C", "D", "F", "W", "Other"), "_pct"), names(gd))
    display <- gd[, intersect(c("department", "subject_course", "total", pct_cols), names(gd)), drop = FALSE]
    cols <- list(
      department = reactable::colDef(name = "Department"),
      subject_course = reactable::colDef(name = "Course"),
      total = reactable::colDef(name = "Attempts", align = "right")
    )
    for (pc in pct_cols) {
      cols[[pc]] <- reactable::colDef(
        name = sub("_pct$", "", pc), align = "right",
        cell = function(value) if (!is.na(value)) paste0(value, "%") else "-"
      )
    }
    gen_ed_render_table(display, columns = cols)
  })

  output$assoc_table_ui <- renderUI({
    d <- data_rv()
    if (is.null(d)) return(NULL)
    if (associations_require_auth(d) && !isTRUE(instructor_dfw_authenticated())) {
      return(gen_ed_empty_table(
        "Instructor-level course association rows require authentication. Use the restricted instructor access section on this tab to unlock them."
      ))
    }
    gen_ed_table_output_or_note(
      d$associations,
      session$ns("assoc_table"),
      "No course association rows met the current filters and Min N. This means no qualifying course groups had enough eligible students after excluding students with prior majors or pre-majors in the course department.",
      "course association"
    )
  })

  output$assoc_meta <- renderUI({
    d <- data_rv()
    if (associations_require_auth(d) && !isTRUE(instructor_dfw_authenticated())) {
      return(NULL)
    }
    if (is.null(d) || is.null(d$associations) || nrow(d$associations) == 0) {
      return(NULL)
    }
    total_eligible <- sum(d$associations$n_eligible)
    total_later <- sum(d$associations$n_later_declared)
    p(sprintf(
      "%d groups. %s eligible students, %s later declared (%s%%).",
      nrow(d$associations),
      format(total_eligible, big.mark = ","),
      format(total_later, big.mark = ","),
      formatC(100 * total_later / max(total_eligible, 1), format = "f", digits = 1)
    ), class = "text-hint")
  })

  output$assoc_table <- reactable::renderReactable({
    d <- data_rv()
    req(!is.null(d), !is.null(d$associations), nrow(d$associations) > 0)
    req(!associations_require_auth(d) || isTRUE(instructor_dfw_authenticated()))
    cols <- list(
      department = reactable::colDef(name = "Department"),
      subject_course = reactable::colDef(name = "Course"),
      instructor_name = reactable::colDef(name = "Instructor", minWidth = 160),
      n_eligible = reactable::colDef(name = "Eligible", align = "right"),
      n_later_declared = reactable::colDef(name = "Later Declared", align = "right"),
      declaration_pct = reactable::colDef(
        name = "Declaration %", align = "right",
        format = reactable::colFormat(percent = TRUE, digits = 1)
      ),
      pct_of_eligible = reactable::colDef(
        name = "% of Pool", align = "right",
        format = reactable::colFormat(percent = TRUE, digits = 1)
      ),
      n_terms = reactable::colDef(name = "Terms", align = "right")
    )
    cols <- cols[names(cols) %in% names(d$associations)]
    gen_ed_render_table(d$associations, columns = cols)
  })

  for (output_id in c("enrl_modality", "major_mix", "enrl_course", "enrl_course_modality",
                      "dept_table", "dfw_table", "grade_table", "assoc_table",
                      "instructor_dfw_plot", "instructor_dfw_table")) {
    outputOptions(output, output_id, suspendWhenHidden = FALSE)
  }

  data_rv
}


genEdExploreServer <- function(id, students, sections, programs, degrees = NULL,
                               current_term = NULL) {
  moduleServer(id, function(input, output, session) {
    build_terms <- reactive({
      all_terms <- sort(unique(sections$term[!is.na(sections$term)]))
      from_term <- as.integer(input$ge_from_term)
      to_term <- as.integer(input$ge_to_term)
      all_terms[all_terms >= from_term & all_terms <= to_term]
    })

    opt_builder <- reactive({
      list(
        campus = if (length(input$ge_campus) > 0) input$ge_campus else NULL,
        college = if (length(input$ge_college) > 0) input$ge_college else NULL,
        dept_code = if (length(input$ge_dept) > 0) input$ge_dept else NULL,
        gen_ed_area = if (length(input$ge_gen_ed_area) > 0) input$ge_gen_ed_area else NULL,
        terms = build_terms(),
        min_n = GEN_ED_MIN_N,
        # Course-major associations are a per-department recruitment signal and
        # are not comparable across departments, so they live only on the
        # department-scoped Gen Ed profile, not this aggregate Explore view.
        include_associations = FALSE
      )
    })

    gen_ed_module_server(
      input, output, session, students, sections, programs, degrees,
      current_term, opt_builder, "gen-ed-explore", run_id = "ge_button",
      overlay_id = id
    )
  })
}


deptProfileGenEdServer <- function(id, students, sections, programs, degrees = NULL,
                                   dept, campus = NULL, current_term = NULL,
                                   dfw_password = NULL) {
  moduleServer(id, function(input, output, session) {
    build_terms <- reactive({
      term_sections <- gen_ed_dept_sections(sections, dept)
      all_terms <- sort(unique(term_sections$term[!is.na(term_sections$term)]))
      if (!is.null(current_term)) all_terms <- all_terms[all_terms <= current_term]
      all_terms
    })

    opt_builder <- reactive({
      dept_val <- if (is.function(dept)) dept() else dept
      campus_val <- if (is.null(campus)) NULL else if (is.function(campus)) campus() else campus
      req(dept_val, nzchar(dept_val))
      list(
        dept_code = dept_val,
        campus = if (length(campus_val) > 0) campus_val else NULL,
        level = c("lower", "upper"),
        terms = build_terms(),
        min_n = 5L,
        include_associations = TRUE,
        include_instructor_dfw = TRUE,
        association_group_cols = c("subject_course", "instructor_name")
      )
    })

    gen_ed_module_server(
      input, output, session, students, sections, programs, degrees,
      current_term, opt_builder, "dept-profile-gen-ed",
      run_id = NULL,
      instructor_dfw_enabled = TRUE,
      dfw_password = dfw_password
    )
  })
}
