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


genEdExploreUI <- function(id, sections, dept_choices, current_term = NULL) {
  ns <- NS(id)
  term_choices <- gen_ed_term_choices(sections, current_term)
  area_choices <- gen_ed_area_choices(sections)

  tagList(
    filter_bar(
      "Gen Ed",
      "Aggregate view of Gen Ed enrollment and grade outcomes.",
      fluidRow(class = "explore-filter-row",
        column(1,
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
            choices = term_choices, selected = if (length(term_choices)) unname(term_choices)[1])
        ),
        column(2,
          selectizeInput(ns("ge_to_term"), "To term",
            choices = term_choices, selected = if (length(term_choices)) unname(term_choices)[length(term_choices)])
        ),
        column(2,
          selectizeInput(ns("ge_dept"), "Department", multiple = TRUE,
            choices = dept_choices)
        ),
        column(2,
          selectInput(ns("ge_gen_ed_area"), "Gen Ed Area", multiple = TRUE,
            choices = area_choices)
        ),
        column(1,
          numericInput(ns("ge_min_n"), "Min N", value = 5, min = 1, max = 100)
        ),
        column(1,
          filter_actions(
            actionButton(ns("ge_button"), "Run", class = "btn-primary btn-sm", icon = icon("play"))
          )
        )
      ),
      filter_scope_stripe(uiOutput(ns("scope_summary")))
    ),

    uiOutput(ns("summary_cards")),
    fluidRow(
      column(6,
        h5("Enrollment by Modality", class = "cedar-section-heading"),
        plotlyOutput(ns("enrl_modality"), height = "300px")
      ),
      column(6,
        h5("Major Mix in Gen Ed Courses", class = "cedar-section-heading"),
        plotlyOutput(ns("major_mix"), height = "300px")
      )
    ),
    fluidRow(
      column(12,
        h5("Top Gen Ed Course Enrollment Over Time", class = "cedar-section-heading"),
        plotlyOutput(ns("enrl_course"), height = "360px")
      )
    ),
    hr(),
    h5("Department Summary", class = "cedar-section-heading"),
    uiOutput(ns("dept_table_ui")),
    hr(),
    h5("DFW Rates by Course", class = "cedar-section-heading"),
    uiOutput(ns("dfw_table_ui")),
    hr(),
    h5("Grade Distribution", class = "cedar-section-heading"),
    uiOutput(ns("grade_table_ui"))
  )
}


deptProfileGenEdUI <- function(id, sections = NULL, current_term = NULL, dept = NULL) {
  ns <- NS(id)

  tagList(
    p(
      "Department-scoped Gen Ed snapshot across available terms. Instructor rows are descriptive associations, not causal evidence.",
      class = "text-hint"
    ),
    uiOutput(ns("scope_summary")),
    uiOutput(ns("summary_cards")),
    fluidRow(
      column(6,
        h5("Enrollment by Modality", class = "cedar-section-heading"),
        plotlyOutput(ns("enrl_modality"), height = "260px")
      ),
      column(6,
        h5("Major Mix in Gen Ed Courses", class = "cedar-section-heading"),
        plotlyOutput(ns("major_mix"), height = "260px")
      )
    ),
    h5("Gen Ed Course Enrollment Over Time", class = "cedar-section-heading"),
    plotlyOutput(ns("enrl_course"), height = "320px"),
    h5("F2F vs Online by Gen Ed Course", class = "cedar-section-heading"),
    plotlyOutput(ns("enrl_course_modality"), height = "320px"),
    hr(),
    h5("DFW Rates by Course", class = "cedar-section-heading"),
    tags$p(
      "Course-level DFW rates for the selected Gen Ed scope; Early Drop % uses attempts plus early drops, while later outcome rates use attempts.",
      class = "text-hint"
    ),
    uiOutput(ns("dfw_table_ui")),
    hr(),
    uiOutput(ns("instructor_dfw_access"))
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


gen_ed_module_server <- function(input, output, session, students, sections, programs,
                                 degrees, current_term, opt_builder, report_timer_name,
                                 run_id = "run", instructor_dfw_enabled = FALSE,
                                 dfw_password = NULL) {
  data_rv <- reactiveVal(NULL)
  instructor_dfw_authenticated <- reactiveVal(FALSE)
  instructor_dfw_password <- dfw_password %||% Sys.getenv("CEDAR_DFW_PASSWORD", unset = "cedar-dfw-2025")
  associations_require_auth <- function(d) {
    !is.null(d) &&
      !is.null(d$associations) &&
      "instructor_name" %in% names(d$associations)
  }

  output$scope_summary <- renderUI({
    d <- data_rv()
    if (is.null(d)) {
      msg <- if (is.null(run_id)) {
        "Select a department to load the Gen Ed profile."
      } else {
        "Set filters and click Run."
      }
      return(div(
        class = "gen-ed-scope-summary gen-ed-scope-summary--empty",
        p(msg, class = "text-hint")
      ))
    }
    m <- d$summary[1, ]
    div(
      class = "gen-ed-scope-summary",
      p(sprintf(
        "%s courses across %s departments. %s registered enrollments from %s distinct students.",
        format(m$n_courses, big.mark = ","),
        format(m$n_departments, big.mark = ","),
        format(m$registered_enrollments, big.mark = ","),
        format(m$n_students, big.mark = ",")
      ), class = "text-hint"),
      p(
        if (!is.null(d$associations)) {
          "Enrollment figures use section rows. DFW and grade tables use registered student rows with final grades or late withdrawals; associations also need program declaration history and must meet Min N."
        } else {
          "Enrollment figures use section rows. DFW and grade tables use registered student rows with final grades or late withdrawals and must meet Min N."
        },
        class = "text-hint"
      )
    )
  })

  run_profile <- function() {
    data_rv(NULL)
    instructor_dfw_authenticated(FALSE)
    show_loading_notification <- !is.null(run_id)
    timer <- start_report_timer(report_timer_name)
    if (show_loading_notification) {
      showNotification("Computing Gen Ed profile...", type = "message",
                       duration = NULL, id = session$ns("loading"))
    }
    result <- tryCatch(
      get_gen_ed_profile(students, sections, programs, degrees, opt_builder()),
      error = function(e) {
        showNotification(paste("Gen Ed profile failed:", e$message), type = "error")
        NULL
      }
    )
    if (show_loading_notification) {
      removeNotification(session$ns("loading"))
    }
    data_rv(result)
    if (!is.null(result) && show_loading_notification) {
      showNotification(
        paste0("Gen Ed profile complete (", round(end_report_timer(timer), 1), "s)"),
        type = "message", duration = 3
      )
    } else if (!is.null(result)) {
      end_report_timer(timer)
    }
  }

  if (is.null(run_id)) {
    observeEvent(opt_builder(), run_profile(), ignoreInit = FALSE)
  } else {
    observeEvent(input[[run_id]], run_profile())
  }

  output$summary_cards <- renderUI({
    d <- data_rv()
    if (is.null(d)) return(NULL)
    s <- d$summary[1, ]
    fluidRow(
      column(2, div(class = "stat-card",
        p(format(s$n_courses, big.mark = ","), class = "stat-num"),
        p("gen ed courses", class = "stat-lbl")
      )),
      column(2, div(class = "stat-card",
        p(format(s$n_departments, big.mark = ","), class = "stat-num"),
        p("departments", class = "stat-lbl")
      )),
      column(2, div(class = "stat-card",
        p(format(s$total_enrl, big.mark = ","), class = "stat-num"),
        p("section enrollment", class = "stat-lbl")
      )),
      column(2, div(class = "stat-card",
        p(if (!is.na(s$avg_section_enrl)) format(s$avg_section_enrl, big.mark = ",") else "-", class = "stat-num"),
        p("avg enrl / section", class = "stat-lbl")
      )),
      column(2, div(class = "stat-card",
        p(format(s$n_students, big.mark = ","), class = "stat-num"),
        p("distinct students", class = "stat-lbl")
      )),
      column(2, div(class = "stat-card",
        p(if (!is.na(s$overall_dfw)) paste0(s$overall_dfw, "%") else "-", class = "stat-num"),
        p("overall DFW rate", class = "stat-lbl")
      ))
    )
  })

  output$enrl_modality <- renderPlotly({
    d <- data_rv()
    req(!is.null(d), nrow(d$enrl_by_modality) > 0)
    ebm <- d$enrl_by_modality
    chrono <- unique(ebm$term_label[order(ebm$term)])
    modality_colors <- c("F2F / ABQ" = "#1565c0", "Online / EA" = "#e65100", "Unknown" = "#6b7280")
    other_modalities <- setdiff(unique(ebm$modality), names(modality_colors))
    if (length(other_modalities) > 0) {
      modality_colors <- c(modality_colors, build_color_map(other_modalities))
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
        n_early_drop,
        early_drop_pct,
        n_dfw,
        dfw_rate,
        c_minus_pct,
        d_pct,
        f_pct,
        w_pct,
        below_c_no_w_pct
      )

    gen_ed_render_table(display, columns = list(
      department = reactable::colDef(name = "Department"),
      subject_course = reactable::colDef(name = "Course"),
      n_enrolled = reactable::colDef(name = "Attempts", align = "right"),
      n_early_drop = reactable::colDef(name = "Early Drops", align = "right"),
      early_drop_pct = reactable::colDef(
        name = "Early Drop %", align = "right",
        cell = function(value) if (!is.na(value)) paste0(value, "%") else "-"
      ),
      n_dfw = reactable::colDef(name = "DFW", align = "right"),
      dfw_rate = reactable::colDef(
        name = "DFW %", align = "right",
        format = reactable::colFormat(percent = TRUE, digits = 1)
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
      below_c_no_w_pct = reactable::colDef(
        name = "Below C %", align = "right",
        cell = function(value) if (!is.na(value)) paste0(value, "%") else "-"
      )
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

    p <- plot_ly() %>%
      add_bars(
        data = course_avg,
        x = ~round(100 * dfw_rate, 1),
        y = ~subject_course,
        orientation = "h",
        name = "Course average",
        marker = list(color = "#5b8def"),
        hovertemplate = "Course: %{y}<br>Course DFW: %{x:.1f}%<extra></extra>"
      ) %>%
      add_markers(
        data = instructor_avg,
        x = ~round(100 * dfw_rate, 1),
        y = ~subject_course,
        name = "Instructor average",
        marker = list(size = 8, color = "#c45a1c", opacity = 0.85),
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
        dept = if (length(input$ge_dept) > 0) input$ge_dept else NULL,
        gen_ed_area = if (length(input$ge_gen_ed_area) > 0) input$ge_gen_ed_area else NULL,
        terms = build_terms(),
        min_n = as.integer(input$ge_min_n),
        # Course-major associations are a per-department recruitment signal and
        # are not comparable across departments, so they live only on the
        # department-scoped Gen Ed profile, not this aggregate Explore view.
        include_associations = FALSE
      )
    })

    gen_ed_module_server(
      input, output, session, students, sections, programs, degrees,
      current_term, opt_builder, "gen-ed-explore", run_id = "ge_button"
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
        dept = dept_val,
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
