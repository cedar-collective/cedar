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

# Small-cell guard for the graduate Gen Ed section. Lower than GEN_ED_MIN_N
# because it applies to a cohort of graduates (tens), not to course enrollment
# (thousands): at 5 a department with 20 readable graduates would show almost
# nothing. Three is the floor at which a cell is a pattern rather than one
# student's transcript.
GRAD_GEN_ED_MIN_N <- 3L

# Heatmap display limits. These must match what plot_curriculum_map() is asked
# to draw, because the container height is computed from them — a mismatch gives
# variable tile heights as the course count changes.
# Row-inclusion floor for the timing map. Low because pct_pop is now a share of
# the whole counted cohort rather than of the students who reached each position:
# on a cohort of ~100 a single graduate is 1%, and a course taken by the three
# graduates that clear GRAD_GEN_ED_MIN_N peaks at 3%. A 5% floor — right when the
# denominator was per-position eligibility — silently dropped most of the grid.
GRAD_GEN_ED_MIN_PCT <- 0.005
GRAD_GEN_ED_TOP_N   <- 40L

# A band needs this many graduates to have reached it before any percentage is
# drawn there. Separate from GRAD_GEN_ED_MIN_N, which guards the numerator: this
# one guards the denominator, and the two fail differently. Measured on History,
# eligibility down the UNM-credit axis runs 101, 80, 33, 16, 4 — the top band
# produced a bold "25%" that was one student out of the four who reached it.
GRAD_GEN_ED_MIN_BAND_N <- 10L

# Where a course sits on the timing map. Two honest answers to two different
# questions, offered because no single axis serves every department:
#
#   relative_term    — how far into their time AT UNM. Complete for everyone and
#                      well populated to the tail (History: 101 95 91 85 55 44
#                      28 16). Normally this axis is unreliable in CEDAR because
#                      students already enrolled when the data opens look like
#                      first-semester students; that cannot happen here, because
#                      the cohort is DEFINED as students who first enrolled after
#                      the window opened. This is the one place the axis is safe
#                      without a start-classification filter.
#   unm_credit_band  — how far into their DEGREE, but counting UNM credit only.
#                      Reads as degree progress, and is healthy for departments
#                      whose majors do most of their coursework here (Biology:
#                      453 407 285 209 60). It thins badly where transfer credit
#                      is common — History graduates carry a median 58 UNM
#                      credits against 129.5 on the degree record, so half the
#                      degree is invisible and the upper bands empty out.
#
# `overall_credit_band` is deliberately NOT offered. The Academic Studies totals
# behind it are stamped per program record, not per term: across 641 term-to-term
# transitions in the History cohort only 6% strictly increase, 85% are unchanged
# and 9% decrease. It is a frozen final total applied retroactively, so it would
# place nearly every student in the top band and read as a well-populated axis
# while measuring nothing about timing. See the credit-source table in AGENTS.md.
GRAD_GEN_ED_AXES <- c(
  "Terms enrolled" = "relative_term",
  "UNM credits"    = "unm_credit_band"
)
GRAD_GEN_ED_DEFAULT_AXIS <- "relative_term"

# Enough terms to cover a long undergraduate career; the band guard trims the
# thin tail rather than a fixed cap doing it arbitrarily.
GRAD_GEN_ED_MAX_TERM <- 10L


# Axis-appropriate label for an x position, for prose that has to name a band
# the map is not drawing.
grad_gen_ed_band_label <- function(pos, x_axis) {
  if (identical(x_axis, "relative_term")) return(paste("term", pos))
  c("0-30", "31-60", "61-90", "91-120", "121+")[pos]
}


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
            selected = cedar_campus_default(sections))
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
            actionButton(ns("ge_button"), "Run", class = "btn-sm btn-primary", icon = icon("play"))
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
            "Grade outcomes for each Gen Ed course, split by campus. ",
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
        "Full grade spread across the selected Gen Ed courses, split by campus so rows line up with the DFW table above.",
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
    # Everything above is this department as a Gen Ed PROVIDER — its courses, its
    # seats, its grades. The two sections below turn the question around and ask
    # what Gen Ed the department's own majors consume, which needs a different
    # population and a much stricter one. Kept on the same subtab because chairs
    # ask both questions in the same breath, separated by their own headers
    # because the numbers are not comparable with the ones above.
    #
    # Own-unit comes FIRST and carries the shared cohort strip. A chair opening
    # their own Gen Ed page wants their own courses; "what our majors take
    # everywhere" is the context for that, not the other way round.
    dashboard_section(
      "This Unit's Own Gen Ed, Taken by Its Graduates",
      tagList(
        tags$p(
          class = "cedar-dashboard-section-description",
          "Which of this department's own Gen Ed courses its graduates took, and when. ",
          "Every graduate whose entire UNM record falls inside the available data is counted \u2014 ",
          "those who first enrolled after the data begins and earned an awarded degree before ",
          "it ends. Graduates already enrolled when the data starts are left out because their ",
          "early coursework is missing, and including them would understate every rate here."
        ),
        tags$p(
          class = "cedar-dashboard-section-description",
          tags$strong("This counts enrollment, not requirement satisfaction."),
          " CEDAR sees that a graduate took a course; it does not see the degree audit that ",
          "decided what the course counted for. That distinction bites hardest right here: when ",
          "a History major takes a History course from the Gen Ed catalog, it may have satisfied ",
          "a Gen Ed area, a major requirement, both, or neither, and this data cannot tell those ",
          "apart. Read this section as how much of its own Gen Ed teaching the department ",
          "supplies to its own majors \u2014 not as how they met Gen Ed."
        )
      ),
      uiOutput(ns("grad_ge_meta")),
      dashboard_subsection(
        "Who These Graduates Are",
        tagList(
          "Gen Ed averages depend almost entirely on how much of the degree happened at UNM. ",
          "A graduate who transferred in as a junior satisfied most of Gen Ed somewhere CEDAR ",
          "cannot see, and shows up here with very few courses \u2014 not because they skipped ",
          "Gen Ed, but because it is not in this data. Read the headline averages against this ",
          "table. This department's own Gen Ed courses are counted separately from everyone ",
          "else's, so the two never blend into a single figure."
        ),
        reactable::reactableOutput(ns("grad_ge_entry_table"))
      ),
      uiOutput(ns("grad_ge_own_meta")),
      dashboard_subsection(
        "When Graduates Take This Unit's Gen Ed",
        tagList(
          "Each cell is the share of ", tags$strong("every graduate counted here"),
          " who took that course at that point \u2014 not a share of the students who happened ",
          "to reach that point. Every cell is therefore on one scale: a position only a handful ",
          "of graduates reached shows a small percentage, rather than a large one resting on a ",
          "handful of transcripts. Read across a row and the cells sum to that course's ",
          tags$strong("% of Grads"), " in the table below. ",
          "The control below sets what \"that point\" means, and governs both heatmaps here."
        ),
        div(class = "explore-filter-row",
          radioButtons(ns("grad_ge_axis"), "Position courses by",
            choices  = GRAD_GEN_ED_AXES,
            selected = GRAD_GEN_ED_DEFAULT_AXIS,
            inline   = TRUE)
        ),
        uiOutput(ns("grad_ge_axis_note")),
        uiOutput(ns("grad_ge_own_plot_ui")),
        uiOutput(ns("grad_ge_guard_note"))
      ),
      dashboard_subsection(
        "Which of This Unit's Gen Ed Courses Graduates Take",
        tagList(
          tags$strong("% of Grads"), " is the share of the graduates counted here who took the course ",
          "at least once before graduating. Retakes count once. Percentages do not sum to 100 — a ",
          "graduate takes many Gen Ed courses, and the same student appears in every row they took."
        ),
        uiOutput(ns("grad_ge_own_table_ui"))
      )
    ),
    # The same cohort and the same three views, widened from the unit's own Gen
    # Ed to all of it. Second because it is the context for the section above:
    # the own-unit numbers only mean something against the total.
    dashboard_section(
      "All Gen Ed Taken by This Department's Graduates",
      tagList(
        tags$p(
          class = "cedar-dashboard-section-description",
          "The same graduates as above, now counting every Gen Ed course they took anywhere at ",
          "UNM rather than only this department's. Read it against the section above: that one ",
          "is the part the department supplied to its own majors, this one is the whole of what ",
          "they took."
        ),
        tags$p(
          class = "cedar-dashboard-section-description",
          "The cohort is small in the early years of the data window and grows as the window ",
          "lengthens. Read these as patterns, not as departmental statistics."
        )
      ),
      uiOutput(ns("grad_ge_all_meta")),
      dashboard_subsection(
        "When Graduates Take Gen Ed",
        tagList(
          "Same axis, same cohort and same denominator as the heatmap above \u2014 the share is out ",
          "of every graduate counted here, whichever department taught the course. That keeps the ",
          "two maps comparable cell for cell. Use the control in the section above to change the axis."
        ),
        uiOutput(ns("grad_ge_plot_ui"))
      ),
      dashboard_subsection(
        "Which Gen Ed Courses Graduates Take",
        tagList(
          tags$strong("% of Grads"), " is the share of the cohort who took the course at least once ",
          "before graduating — the same rows and the same numbers as the table above, with the ",
          "rest of UNM's Gen Ed added back in. The ", tags$strong("Own Unit"), " column marks the ",
          "rows that also appear above."
        ),
        uiOutput(ns("grad_ge_table_ui"))
      )
    ),
    dashboard_section(
      "Course Outcomes",
      "Course and instructor DFW rates for this department's Gen Ed courses, each split by campus. Instructor rows are descriptive associations, not causal evidence, and are not a basis for evaluating teaching.",
      dashboard_subsection(
        "DFW Rates by Course",
        tagList(
          "One row per course per campus, so face-to-face and online sections are ",
          "not blended into a single rate. ",
          tags$strong("DFW % equals Below C % + W %"),
          ", each computed from its own counts. Early drops are excluded from both: ",
          "Early Drop % uses attempts plus early drops as its base, so it does not ",
          "add into the other columns."
        ),
        uiOutput(ns("dfw_table_ui"))
      ),
      uiOutput(ns("instructor_dfw_access"))
    )
  )
}


# Every percentage column across the Gen Ed tables is on the same 0-100 scale
# and rendered the same way, so DFW % can be read against Below C % + W %
# without a unit shift. Shared by the course, instructor, and association
# tables — they used to render percentages three different ways.
gen_ed_pct_col <- function(label, min_width = 80) {
  reactable::colDef(
    name = label, align = "right", minWidth = min_width,
    cell = function(value) if (!is.na(value)) paste0(value, "%") else "-"
  )
}


# Campus reads as a scope column, not a measure: narrow, left, first.
gen_ed_campus_col <- function() {
  reactable::colDef(name = "Campus", minWidth = 80)
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
        dplyr::any_of("campus"),
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

    pct_col <- gen_ed_pct_col

    gen_ed_render_table(display, columns = list(
      campus = gen_ed_campus_col(),
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
        "Instructor-course groups by campus, and how often students with no prior tie to the department later declared in it. Eligible counts students who had no department program record at or before the term they took the course. A correlation, not a causal claim.",
        class = "text-hint"
      )
    )
    instructor_header <- tagList(
      h5("Restricted Instructor DFW", class = "cedar-section-heading"),
      tags$p(
        "Instructor DFW rates by campus for the same courses, each shown against the course rate on that campus and the gap between them. Attempts is the denominator; read a gap on a small number of attempts as noise.",
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

    # dfw_by_course is one row per course *per campus*, so the y axis has to
    # carry campus too — keying on subject_course alone would put an ABQ and an
    # EA bar at the same position and silently draw one over the other. The
    # campus suffix is only added when the scope actually spans campuses, so
    # single-campus views keep clean labels. Both frames build the label the
    # same way, which is what keeps instructor markers on their own course bar.
    multi_campus <- "campus" %in% names(d$dfw_by_course) &&
      dplyr::n_distinct(d$dfw_by_course$campus) > 1
    course_label <- function(df) {
      if (multi_campus) paste0(df$subject_course, " · ", df$campus)
      else as.character(df$subject_course)
    }

    course_avg <- d$dfw_by_course
    course_avg$course_key <- course_label(course_avg)
    course_avg <- course_avg %>%
      dplyr::mutate(course_key = factor(course_key, levels = unique(course_key)))

    instructor_avg <- d$instructor_dfw
    instructor_avg$course_key <- course_label(instructor_avg)
    instructor_avg <- instructor_avg %>%
      dplyr::mutate(
        course_key = factor(course_key, levels = levels(course_avg$course_key)),
        hovertext = paste0(
          "Instructor: ", instructor_name,
          "<br>Course: ", subject_course,
          if (multi_campus) paste0("<br>Campus: ", campus) else "",
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
        y = ~course_key,
        orientation = "h",
        name = "Course average",
        marker = list(color = unname(role_colors[["Course average"]])),
        hovertemplate = "Course: %{y}<br>Course DFW: %{x:.1f}%<extra></extra>"
      ) %>%
      add_markers(
        data = instructor_avg,
        x = ~round(100 * dfw_rate, 1),
        y = ~course_key,
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

    # Same column order and naming as DFW Rates by Course, with the two columns
    # that make this table worth opening — the course rate on the same campus,
    # and the gap to it — sitting next to the instructor's own DFW. Raw n_dfw is
    # dropped: Attempts is the denominator a reader needs to judge whether a
    # rate is meaningful, and the counts behind it are what turn a descriptive
    # rate into an apparent tally of a named person's failures.
    display <- d$instructor_dfw %>%
      dplyr::select(
        dplyr::any_of("campus"),
        subject_course,
        instructor_name,
        n_attempts,
        early_drop_pct,
        dfw_pct_display,
        course_dfw_pct_display,
        dfw_diff_pp,
        below_c_no_w_pct,
        w_pct,
        c_minus_pct,
        d_pct,
        f_pct,
        n_terms
      )

    gen_ed_render_table(display, columns = list(
      campus = gen_ed_campus_col(),
      subject_course = reactable::colDef(name = "Course", minWidth = 105),
      instructor_name = reactable::colDef(name = "Instructor", minWidth = 160),
      n_attempts = reactable::colDef(name = "Attempts", align = "right"),
      early_drop_pct         = gen_ed_pct_col("Early Drop %", 105),
      dfw_pct_display        = gen_ed_pct_col("DFW %", 90),
      course_dfw_pct_display = gen_ed_pct_col("Course DFW %", 115),
      dfw_diff_pp = reactable::colDef(
        name = "Diff", align = "right", minWidth = 85,
        cell = function(value) if (!is.na(value)) paste0(value, " pp") else "-"
      ),
      below_c_no_w_pct = gen_ed_pct_col("Below C %", 95),
      w_pct            = gen_ed_pct_col("W %"),
      c_minus_pct      = gen_ed_pct_col("C- %"),
      d_pct            = gen_ed_pct_col("D %"),
      f_pct            = gen_ed_pct_col("F %"),
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
    display <- gd[, intersect(c("campus", "department", "subject_course", "total", pct_cols), names(gd)), drop = FALSE]
    cols <- list(
      campus = gen_ed_campus_col(),
      department = reactable::colDef(name = "Department"),
      subject_course = reactable::colDef(name = "Course", minWidth = 105),
      total = reactable::colDef(name = "Attempts", align = "right")
    )
    for (pc in pct_cols) {
      cols[[pc]] <- gen_ed_pct_col(paste0(sub("_pct$", "", pc), " %"))
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
    # Eligible is the denominator, so it stays; the raw later-declared count is
    # dropped in favour of the rate it produces. The running totals under this
    # table still come from the full data, which keeps both columns.
    display_cols <- c("campus", "department", "subject_course", "instructor_name",
                      "n_eligible", "declaration_pct", "pct_of_eligible", "n_terms")
    display <- d$associations[, intersect(display_cols, names(d$associations)), drop = FALSE]

    # declaration_pct and pct_of_eligible are 0-1 rates owned by the
    # associations cone, so they are formatted rather than pasted. The rendered
    # result matches gen_ed_pct_col() exactly.
    rate_col <- function(label, min_width = 110) {
      reactable::colDef(
        name = label, align = "right", minWidth = min_width,
        format = reactable::colFormat(percent = TRUE, digits = 1)
      )
    }

    cols <- list(
      campus = gen_ed_campus_col(),
      department = reactable::colDef(name = "Department"),
      subject_course = reactable::colDef(name = "Course", minWidth = 105),
      instructor_name = reactable::colDef(name = "Instructor", minWidth = 160),
      n_eligible = reactable::colDef(name = "Eligible", align = "right"),
      declaration_pct = rate_col("Declared %"),
      pct_of_eligible = rate_col("% of Pool", 100),
      n_terms = reactable::colDef(name = "Terms", align = "right")
    )
    cols <- cols[names(cols) %in% names(display)]
    gen_ed_render_table(display, columns = cols)
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


#' @param term_credits Data frame or NULL. The `cedar_student_term_credits`
#'   table, required by the graduate Gen Ed section for its credit-band x-axis.
#'   NULL hides that section rather than drawing it against a different credit
#'   source — the program-record credit fields cannot answer the question. See
#'   `R/features/gen-ed.R`.
deptProfileGenEdServer <- function(id, students, sections, programs, degrees = NULL,
                                   dept, campus = NULL, current_term = NULL,
                                   dfw_password = NULL, term_credits = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

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
        association_group_cols = c("campus", "subject_course", "instructor_name")
      )
    })

    gen_ed_module_server(
      input, output, session, students, sections, programs, degrees,
      current_term, opt_builder, "dept-profile-gen-ed",
      run_id = NULL,
      instructor_dfw_enabled = TRUE,
      dfw_password = dfw_password
    )

    # ── Gen Ed taken by this department's graduates ─────────────────────────
    # Deliberately separate from gen_ed_module_server(): that server is shared
    # with Explore > Gen Ed, which has no single department and therefore no
    # graduate cohort to build. This section only makes sense department-scoped.

    # Committed to a reactiveVal by an observer rather than read from a plain
    # reactive(), matching gen_ed_module_server() above. The difference is not
    # style: the Dept Trends campus observer calls updateSelectizeInput() on the
    # department picker, which momentarily reports input$dept as "". A reactive()
    # re-runs on that blip, hits the req() in opt_builder(), and blanks these
    # outputs while every sibling table on the page keeps showing the department
    # the user chose. Holding the last computed value means a transient empty
    # input recomputes nothing and erases nothing.
    grad_ge_rv <- reactiveVal(NULL)

    # Department/campus scope and the axis choice both invalidate the payload,
    # so they are combined into one trigger. The axis is read here rather than
    # inside the renderers because it changes what get_course_timing() computes,
    # not merely how it is drawn.
    grad_ge_trigger <- reactive({
      list(opt = opt_builder(),
           x_axis = input$grad_ge_axis %||% GRAD_GEN_ED_DEFAULT_AXIS)
    })

    observeEvent(grad_ge_trigger(), {
      if (is.null(term_credits) || is.null(degrees)) return()
      trig <- grad_ge_trigger()
      opt <- trig$opt
      if (is.null(opt$dept_code) || !nzchar(opt$dept_code)) return()

      timer <- start_report_timer("dept-profile-gen-ed-grads")
      result <- tryCatch(
        get_gen_ed_grad_profile(students, degrees, term_credits, opt = list(
          dept_code         = opt$dept_code,
          campus            = opt$campus,
          x_axis            = trig$x_axis,
          max_relative_term = GRAD_GEN_ED_MAX_TERM,
          min_n             = GRAD_GEN_ED_MIN_N,
          min_band_n        = GRAD_GEN_ED_MIN_BAND_N
        )),
        error = function(e) {
          showNotification(paste("Graduate Gen Ed profile failed:", e$message),
                           type = "error")
          NULL
        }
      )
      end_report_timer(timer)
      grad_ge_rv(result)
    }, ignoreInit = FALSE)

    grad_ge_data <- reactive(grad_ge_rv())

    output$grad_ge_meta <- renderUI({
      d <- grad_ge_data()
      if (is.null(d)) return(NULL)
      m <- d$cohort_meta
      s <- d$summary

      # The excluded counts are the point of this strip, not a footnote. A reader
      # who sees "22 graduates" without "of 247" will read the tables as the
      # department's graduating class.
      excluded <- m$n_no_records + m$n_left_truncated

      if (m$n_cohort == 0) {
        return(div(class = "alert-box alert-box--info",
          sprintf(
            paste("No graduates of this department have a complete UNM record in the",
                  "available data. All %s awarded graduates either first enrolled before",
                  "%s, when the data begins, or have no enrollment records at all."),
            format(m$n_awarded, big.mark = ","), fmt_term(m$min_data_term)
          )
        ))
      }

      # Cohort definition ONLY. The all-Gen-Ed averages used to sit here, which
      # put "avg gen ed courses per graduate" under a heading that reads This
      # Unit's Own Gen Ed and directly above the own-unit card row — two rows of
      # student counts, one of them about a different scope. They now render in
      # the all-Gen-Ed section, where they belong.
      tagList(
        div(class = "stat-row",
          fluidRow(
            column(4, div(class = "stat-card",
              p(format(m$n_cohort, big.mark = ","), class = "stat-num"),
              p("graduates counted", class = "stat-lbl"),
              p(class = "stat-compare",
                sprintf("of %s undergraduate degrees awarded here",
                        format(m$n_awarded, big.mark = ",")))
            )),
            column(4, div(class = "stat-card",
              p(format(excluded, big.mark = ","), class = "stat-num"),
              p("graduates not readable", class = "stat-lbl"),
              p(class = "stat-compare", "their record starts or ends outside the data")
            )),
            column(4, div(class = "stat-card",
              # Calendar years, not fmt_term()'s season labels — stripping the
              # season off "Fall 2019" leaves "Fall", which is what this showed.
              p(sprintf("%d\u2013%d", m$min_data_term %/% 100L, m$max_data_term %/% 100L),
                class = "stat-num"),
              p("enrollment data window", class = "stat-lbl"),
              p(class = "stat-compare",
                sprintf("%s to %s", fmt_term(m$min_data_term), fmt_term(m$max_data_term)))
            ))
          )
        ),
        tags$p(class = "text-muted-sm",
          sprintf(
            paste("Data window %s to %s. Excluded: %s graduates enrolled before the window",
                  "opened, %s with no enrollment records, %s whose only enrollment postdates",
                  "their degree, %s graduate-level degrees (Gen Ed is an undergraduate",
                  "requirement). Averages count every graduate counted here, including those",
                  "with no Gen Ed on record.",
                  "\n\nThese are counts of courses taken that appear in the Gen Ed catalog, not",
                  "requirements satisfied. They run BELOW the requirement where a student",
                  "arrived with AP, IB, dual-credit or transfer work that CEDAR cannot see, and",
                  "ABOVE it where a course on the Gen Ed list also served a major or elective",
                  "slot. Neither direction is an error; the number answers what was taken here,",
                  "not what was owed."),
            fmt_term(m$min_data_term), fmt_term(m$max_data_term),
            format(m$n_left_truncated, big.mark = ","),
            format(m$n_no_records, big.mark = ","),
            format(m$n_post_grad_entry %||% 0L, big.mark = ","),
            format(m$n_graduate_degrees %||% 0L, big.mark = ",")
          )
        )
      )
    })

    # Why the headline average is what it is.
    #
    # A single mean over this cohort describes nobody: on History it blends 11
    # graduates who did the whole degree here (13.4 Gen Ed courses each) with 58
    # who arrived as juniors or seniors having done Gen Ed somewhere CEDAR
    # cannot see (2.5 each). A chair looking at the blended number and knowing
    # the requirement is four will reasonably conclude the figure is broken. It
    # is not — it is an average of two different populations, and this shows
    # them separately.
    output$grad_ge_entry_table <- reactable::renderReactable({
      d <- grad_ge_data()
      req(d, !is.null(d$by_entry), nrow(d$by_entry) > 0)
      dept <- d$cohort_meta$dept_code
      labels <- c(freshman = "Started here as a freshman",
                  sophomore = "Arrived as a sophomore",
                  junior_senior = "Arrived as a junior or senior",
                  other = "Other / not classified")

      gen_ed_render_table(
        d$by_entry %>%
          dplyr::mutate(entry_standing = dplyr::coalesce(labels[entry_standing],
                                                         entry_standing)) %>%
          dplyr::select(entry_standing, n_graduates, mean_dept_courses,
                        mean_other_courses, mean_courses),
        columns = list(
          entry_standing = reactable::colDef(name = "How they arrived at UNM", minWidth = 200),
          n_graduates = reactable::colDef(name = "Graduates", align = "right", maxWidth = 100),
          mean_dept_courses = reactable::colDef(
            name = sprintf("Avg %s gen ed", dept), align = "right", maxWidth = 150),
          mean_other_courses = reactable::colDef(
            name = "Avg other gen ed", align = "right", maxWidth = 150),
          mean_courses = reactable::colDef(name = "Avg total", align = "right", maxWidth = 110)
        ),
        defaultPageSize = 5
      )
    })

    # What the counted graduates took across ALL of Gen Ed. Rendered in the
    # all-Gen-Ed section rather than beside the cohort definition, so a count of
    # students is never adjacent to a differently-scoped count of students.
    output$grad_ge_all_meta <- renderUI({
      d <- grad_ge_data()
      if (is.null(d)) return(NULL)
      m <- d$cohort_meta
      s <- d$summary
      if (m$n_cohort == 0) return(NULL)

      div(class = "stat-row",
        fluidRow(
          column(4, div(class = "stat-card",
            p(s$mean_courses, class = "stat-num"),
            p("avg gen ed courses per graduate", class = "stat-lbl"),
            p(class = "stat-compare", sprintf("median %s", s$median_courses))
          )),
          column(4, div(class = "stat-card",
            p(s$mean_areas, class = "stat-num"),
            p("avg gen ed areas per graduate", class = "stat-lbl"),
            p(class = "stat-compare", "of 6 areas with defined courses")
          )),
          column(4, div(class = "stat-card",
            p(format(s$n_with_any, big.mark = ","), class = "stat-num"),
            p("took any gen ed at UNM", class = "stat-lbl"),
            p(class = "stat-compare",
              if (s$n_with_any < m$n_cohort)
                sprintf("of the %s counted; %s took none on record",
                        format(m$n_cohort, big.mark = ","), m$n_cohort - s$n_with_any)
              else "all graduates counted")
          ))
        )
      )
    })

    # ── Own-unit card row ──────────────────────────────────────────────────
    # Deliberately NOT a repeat of the cohort strip above. The cohort is
    # identical, so restating "200 counted of 513 awarded" here would invite the
    # reader to treat these as two populations. What changes between the two
    # sections is only the course scope, so these cards report only the
    # quantities that actually differ, each against its all-Gen-Ed counterpart.
    output$grad_ge_own_meta <- renderUI({
      d <- grad_ge_data()
      if (is.null(d) || is.null(d$summary_dept)) return(NULL)
      m  <- d$cohort_meta
      sd <- d$summary_dept
      s  <- d$summary
      n_courses <- nrow(d$by_course_dept)

      if (n_courses == 0) {
        return(div(class = "alert-box alert-box--info",
          sprintf(
            paste("None of this department's own Gen Ed courses were taken by at least",
                  "%d of them. The department may teach no Gen Ed, or its",
                  "own majors may satisfy Gen Ed elsewhere."),
            GRAD_GEN_ED_MIN_N)
        ))
      }

      pct_takers <- if (m$n_cohort > 0) round(100 * sd$n_with_any / m$n_cohort) else NA

      div(class = "stat-row",
        fluidRow(
          column(3, div(class = "stat-card",
            p(format(sd$n_with_any, big.mark = ","), class = "stat-num"),
            p(sprintf("took any %s gen ed", m$dept_code), class = "stat-lbl"),
            p(class = "stat-compare",
              sprintf("%s%% of the %s graduates counted",
                      pct_takers, format(m$n_cohort, big.mark = ",")))
          )),
          column(3, div(class = "stat-card",
            p(sd$mean_courses, class = "stat-num"),
            p(sprintf("avg %s gen ed courses per graduate", m$dept_code),
              class = "stat-lbl"),
            p(class = "stat-compare",
              sprintf("of %s gen ed courses overall", s$mean_courses))
          )),
          column(3, div(class = "stat-card",
            p(paste0(sd$dept_share_pct, "%"), class = "stat-num"),
            p("of their gen ed came from this unit", class = "stat-lbl"),
            p(class = "stat-compare", "share of all gen ed courses taken")
          )),
          column(3, div(class = "stat-card",
            p(format(n_courses, big.mark = ","), class = "stat-num"),
            p("of this unit's gen ed courses taken", class = "stat-lbl"),
            p(class = "stat-compare",
              sprintf("by %s+ graduates each", GRAD_GEN_ED_MIN_N))
          ))
        )
      )
    })

    # Each axis has a different blind spot, and the reader has to know which one
    # is in force to read the map correctly. Stating it next to the control keeps
    # the caveat attached to the choice rather than buried in a section preamble.
    output$grad_ge_axis_note <- renderUI({
      axis <- input$grad_ge_axis %||% GRAD_GEN_ED_DEFAULT_AXIS
      if (identical(axis, "relative_term")) {
        tags$p(class = "text-muted-sm",
          tags$strong("Terms enrolled"),
          " counts from each graduate's first term at UNM, so term 1 really is their first ",
          "semester — this cohort is defined as students who started inside the data window. ",
          "Summer does not advance the count. It measures time at UNM rather than progress ",
          "through the degree: a student who transferred in arrives with standing this axis ",
          "cannot see, so their term 1 may be junior-level work."
        )
      } else {
        tags$p(class = "text-muted-sm",
          tags$strong("UNM credits"), " counts credits completed entering the term, in 30-credit ",
          "bands, so a course in the 0-30 band was taken in the first year of coursework. ",
          tags$strong("Transfer, AP, dual-credit and CLEP hours are not counted."),
          " A student who arrived with credit places earlier here than their true standing, and ",
          "the upper bands hold far fewer graduates than the lower ones — sharply so in ",
          "departments where transfer credit is common."
        )
      }
    })

    # A dropped band is a hole in the axis, and a reader who is not told about
    # it will read the shortened axis as "nobody was ever there". Say which
    # bands went and why, using the eligibility counts that made the call.
    output$grad_ge_guard_note <- renderUI({
      d <- grad_ge_data()
      if (is.null(d) || is.null(d$timing_guards)) return(NULL)
      g <- d$timing_guards
      # Nothing is dropped under the population denominator, so this normally
      # renders nothing. Kept because a caller can still pass a course-level
      # min_n, and a reader deserves to know when courses are being withheld.
      if (length(g$dropped_bands) == 0) return(NULL)

      dropped <- g$band_eligible %>%
        dplyr::filter(relative_term %in% g$dropped_bands)
      phrase <- paste(sprintf("%s (%d)",
                              grad_gen_ed_band_label(dropped$relative_term, g$x_axis),
                              dropped$n_eligible), collapse = ", ")

      tags$p(class = "text-muted-sm",
        sprintf(
          paste("Positions not shown, with the number of graduates who ever",
                "reached them: %s. A position needs %d graduates to be drawn and a cell",
                "needs %d, so one transcript is never rendered as a percentage.%s"),
          phrase, g$min_band_n, g$min_n,
          if (identical(g$x_axis, "unm_credit_band"))
            paste(" Few graduates reach the highest credit bands because these are UNM",
                  "credits only — most of this cohort earned part of their degree elsewhere.")
          else "")
      )
    })

    # ── Shared renderers for the two scopes ────────────────────────────────
    # The all-Gen-Ed and own-unit blocks are the same three views over different
    # slices of one payload, so they are built by shared helpers. Two copies
    # would drift — the heights would stop matching plot_curriculum_map()'s
    # filters in one of them first, and the tiles would start changing size.

    # Height tracks the rows plot_curriculum_map() will actually draw, mirroring
    # the min_pct / top_n it is handed. Same approach as the Pathways timing map:
    # a fixed height gives variable tile heights as the course count changes.
    .grad_ge_plot_rows <- function(timing) {
      if (is.null(timing) || nrow(timing) == 0) return(0L)
      n <- timing %>%
        dplyr::group_by(subject_course) %>%
        dplyr::summarize(peak = max(pct_pop, na.rm = TRUE), .groups = "drop") %>%
        dplyr::filter(peak >= GRAD_GEN_ED_MIN_PCT) %>%
        nrow()
      min(n, GRAD_GEN_ED_TOP_N)
    }

    .grad_ge_plot_ui <- function(timing, plot_id, empty_msg) {
      n_plot <- .grad_ge_plot_rows(timing)
      # Zero drawable rows is its own case. Handing plot_curriculum_map() a frame
      # whose every course falls under min_pct returns an axis with no tiles,
      # which reads as a broken chart next to a table that has rows.
      if (n_plot == 0) return(gen_ed_empty_table(empty_msg))
      plotOutput(ns(plot_id), height = paste0(min(max(n_plot * 20 + 140, 220), 8000), "px"))
    }

    .grad_ge_map <- function(timing, title) {
      plot_curriculum_map(timing, opt = list(
        title   = title,
        min_pct = GRAD_GEN_ED_MIN_PCT,
        top_n   = GRAD_GEN_ED_TOP_N
      ))
    }

    .grad_ge_table <- function(by_course) {
      gen_ed_render_table(
        by_course %>%
          dplyr::select(subject_course, course_title, department, area_label,
                        is_dept_course, n_students, pct_cohort),
        columns = list(
          subject_course = reactable::colDef(name = "Course", minWidth = 110,
            cell = function(value) htmltools::span(class = "fw-semibold", value)),
          course_title = reactable::colDef(name = "Title", minWidth = 200),
          department = reactable::colDef(name = "Taught By", minWidth = 90),
          area_label = reactable::colDef(name = "Gen Ed Area", minWidth = 130),
          is_dept_course = reactable::colDef(name = "Own Unit", minWidth = 85,
            align = "center",
            cell = function(value) if (isTRUE(value)) "✓" else ""),
          n_students = reactable::colDef(name = "Grads", align = "right",
            maxWidth = 80),
          pct_cohort = gen_ed_pct_col("% of Grads", min_width = 100)
        ),
        defaultPageSize = 15
      )
    }

    # ── All Gen Ed ─────────────────────────────────────────────────────────
    output$grad_ge_plot_ui <- renderUI({
      d <- grad_ge_data()
      .grad_ge_plot_ui(
        if (is.null(d)) NULL else d$timing, "grad_ge_plot",
        "No Gen Ed course timing to show for this department's counted graduates."
      )
    })

    output$grad_ge_plot <- renderPlot({
      d <- grad_ge_data()
      req(d, nrow(d$timing) > 0)
      m <- d$cohort_meta
      .grad_ge_map(d$timing, sprintf(
        "Gen Ed Timing — %s %s graduates with a complete UNM record",
        format(m$n_cohort, big.mark = ","), m$dept_code))
    })

    output$grad_ge_table_ui <- renderUI({
      d <- grad_ge_data()
      gen_ed_table_output_or_note(
        if (is.null(d)) NULL else d$by_course,
        ns("grad_ge_table"),
        sprintf("No Gen Ed courses were taken by at least %d of these graduates.",
                GRAD_GEN_ED_MIN_N)
      )
    })

    output$grad_ge_table <- reactable::renderReactable({
      d <- grad_ge_data()
      req(d, nrow(d$by_course) > 0)
      .grad_ge_table(d$by_course)
    })

    # ── This unit's own Gen Ed ─────────────────────────────────────────────
    output$grad_ge_own_plot_ui <- renderUI({
      d <- grad_ge_data()
      .grad_ge_plot_ui(
        if (is.null(d)) NULL else d$timing_dept, "grad_ge_own_plot",
        "No Gen Ed courses taught by this department were taken by enough of these graduates to map."
      )
    })

    output$grad_ge_own_plot <- renderPlot({
      d <- grad_ge_data()
      req(d, nrow(d$timing_dept) > 0)
      m <- d$cohort_meta
      .grad_ge_map(d$timing_dept, sprintf(
        "%s Gen Ed Timing — %s %s graduates with a complete UNM record",
        m$dept_code, format(m$n_cohort, big.mark = ","), m$dept_code))
    })

    output$grad_ge_own_table_ui <- renderUI({
      d <- grad_ge_data()
      gen_ed_table_output_or_note(
        if (is.null(d)) NULL else d$by_course_dept,
        ns("grad_ge_own_table"),
        sprintf(paste("None of this department's own Gen Ed courses were taken by at",
                      "least %d of these graduates."), GRAD_GEN_ED_MIN_N)
      )
    })

    output$grad_ge_own_table <- reactable::renderReactable({
      d <- grad_ge_data()
      req(d, nrow(d$by_course_dept) > 0)
      .grad_ge_table(d$by_course_dept)
    })

    for (output_id in c("grad_ge_meta", "grad_ge_plot", "grad_ge_table",
                        "grad_ge_own_meta", "grad_ge_own_plot", "grad_ge_own_table",
                        "grad_ge_guard_note", "grad_ge_axis_note",
                        "grad_ge_all_meta", "grad_ge_entry_table")) {
      outputOptions(output, output_id, suspendWhenHidden = FALSE)
    }
  })
}
