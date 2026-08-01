# health-whatif.R  (Shiny module)
#
# Healthcare Enrollment What-If tab
#
# Lets the user select a set of health programs, specify a % enrollment
# increase, and see a matrix of projected course demand across future
# semesters — with color-coded "sections needed" flags.
#
# ── LAYOUT ────────────────────────────────────────────────────────────────────
#
#   Sidebar: population builder (reuses populationSelectorUI from pathways.R)
#   Main:
#     Card 1 — Subgroup summary: current headcount + % share by program
#     Card 2 — Projection controls (slider, goal, attrition, start term, etc.)
#     Card 3 — Course impact matrix (courses × semesters, click cell for detail)
#     Modal  — Cell detail: breakdown by program, section info, rates
#
# ── DEPENDENCY CHAIN ──────────────────────────────────────────────────────────
#
#   healthWhatIfServer() calls:
#     build_population()          → branches/population.R
#     get_health_course_rates()   → cones/health-whatif.R   (slow: ~10–30s)
#     get_section_size_lookup()   → cones/health-whatif.R   (fast)
#     project_health_increase()   → cones/health-whatif.R   (fast)
#
#   Reactivity strategy:
#     rates_rv   — recomputes only when programs or baseline years change (slow)
#     proj_rv    — recomputes whenever any projection control changes (fast)
#     Modal      — triggered by clicking a cell in the matrix table
#
# ── INPUT PREFIXES ────────────────────────────────────────────────────────────
#   hwi_  = health what-if module inputs


# =============================================================================
# healthWhatIfUI()
# =============================================================================

healthWhatIfUI <- function(id) {
  ns <- NS(id)

  tagList(

    # Uses the shared filter_bar() header band so this tab's title/subtitle match
    # every other tab. (Was a bare div.pathways-header, a class with no stylesheet
    # rule, which rendered as an unstyled browser-default h1.)
    filter_bar(
      "Health Enrollment Views",
      paste(
        "Select a set of health programs and a projected enrollment increase.",
        "The matrix below shows which courses will see additional demand —",
        "how many extra students, how many additional sections, and when.",
        "Click any cell for a detailed breakdown."
      )
    ),

    layout_sidebar(
      sidebar = sidebar(
        width = 320,
        open  = TRUE,

        # ── Program group preset ─────────────────────────────────────────────
        selectInput(
          ns("hwi_preset"),
          "Program Group",
          choices  = c("(Custom)" = "", names(COHORT_PRESETS)),
          selected = "Top 10 by Enrollment"
        ),

        # ── Individual program selector ──────────────────────────────────────
        # Populated server-side from cedar_programs. Preset selection above
        # auto-fills this list; user can add or remove programs freely.
        # Includes both declared majors and pre-majors for each program name.
        selectizeInput(
          ns("hwi_programs"),
          "Programs",
          choices  = character(0),    # populated server-side
          multiple = TRUE,
          options  = list(
            placeholder = "Select programs...",
            plugins     = list("remove_button")
          )
        ),
        p("Includes declared majors and pre-majors.",
          style = "font-size: 0.78em; color: #888; margin-top: -6px;"),

        hr(),

        # ── Baseline control ─────────────────────────────────────────────────
        # How many historical terms to use when computing course-taking rates.
        # More years = more stable rates (larger N); fewer = more recent.
        # 6 terms ≈ 3 academic years of fall + spring each.
        sliderInput(
          ns("hwi_baseline_terms"),
          label   = "Baseline: terms per semester type",
          min = 2, max = 10, value = 6, step = 1,
          post = " terms"
        ),
        p("Number of historical fall (and spring) terms used to compute how often",
          " health students take each course at each year of study.",
          style = "font-size: 0.78em; color: #888; margin-top: -6px;"),

        # ── Hindcast mode ─────────────────────────────────────────────────────
        # Lets the user validate the model by pretending it's a past year and
        # comparing predictions to what actually happened.
        hr(),
        checkboxInput(ns("hwi_hindcast"), "Test forecast accuracy (hindcast)", value = FALSE),
        conditionalPanel(
          condition = sprintf("input['%s']", ns("hwi_hindcast")),
          selectInput(
            ns("hwi_cutoff_term"),
            "Treat this fall as 'now'",
            choices  = c(),
            selected = NULL
          ),
          p("Rates and cohort sizes are computed from data up to this term only. ",
            "Set the % increase to match actual enrollment growth to get a fair comparison. ",
            "The matrix will show both predicted and actual demand for subsequent terms.",
            style = "font-size: 0.78em; color: #888; margin-top: -4px;")
        ),

        hr(),

        # ── Min-N filter ─────────────────────────────────────────────────────
        # Filters out credit-band rate estimates with too few observations.
        # A course with 100 students total but spread thinly across 5 bands
        # (20 each) would be suppressed at min_n = 21 — the denominator at
        # each band is too small to produce a reliable rate.
        numericInput(
          ns("hwi_min_n"),
          "Min student-term observations per credit band",
          value = 20, min = 5, max = 100, step = 5
        ),
        p("Suppresses courses where any credit band has fewer than this many ",
          "student-term observations. Raise to require more data; lower to include ",
          "rare or specialized courses.",
          style = "font-size: 0.78em; color: #888; margin-top: -6px;"),

        hr(),

        # ── Subgroup summary ─────────────────────────────────────────────────
        uiOutput(ns("hwi_subgroup_ui")),
        reactable::reactableOutput(ns("hwi_subgroup_dt"))

      ), # end sidebar

      # ── Main content area ──────────────────────────────────────────────────

      # Status message — shown while rates are computing
      uiOutput(ns("hwi_status")),

      # ── Tabbed analysis cards ─────────────────────────────────────────────
      tabsetPanel(
        type = "tabs",

        # ── Tab 1: Impact Matrix ───────────────────────────────────────────
        tabPanel(
          "Impact Matrix",

          # ── Projection controls ────────────────────────────────────────
          div(
            style = "margin-bottom: 8px;",
            fluidRow(

              column(2,
                radioButtons(
                  ns("hwi_goal"),
                  "Enrollment goal",
                  choices  = c(
                    "More enrolled students" = "enrollments",
                    "More graduates"         = "graduates"
                  ),
                  selected = "enrollments"
                )
              ),

              column(2,
                numericInput(
                  ns("hwi_delta_pct"),
                  "Increase by (%)",
                  value = 10, min = 1, step = 1
                ),
                p("% of avg enrolled headcount added as steady-state demand.",
                  style = "font-size: 0.75em; color: #888; margin-top: -8px;")
              ),

              conditionalPanel(
                condition = sprintf("input['%s'] == 'graduates'", ns("hwi_goal")),
                column(2,
                  numericInput(
                    ns("hwi_attrition"),
                    "Attrition rate (fraction)",
                    value = 0.20, min = 0, max = 1, step = 0.05
                  )
                )
              ),

              column(2,
                selectInput(
                  ns("hwi_start_term"),
                  uiOutput(ns("hwi_start_term_label"), inline = TRUE),
                  choices  = c(),
                  selected = NULL
                )
              ),

              column(2,
                numericInput(
                  ns("hwi_n_years"),
                  "Project for (years)",
                  value = 4, min = 1, step = 1
                ),
                p("Same delta applied in each projected semester (flat, not compounding).",
                  style = "font-size: 0.75em; color: #888; margin-top: -4px;")
              )

            ), # end fluidRow

            fluidRow(

              column(3,
                numericInput(
                  ns("hwi_threshold"),
                  "Min sections impact to show",
                  value = 1.0, min = 0.05, step = 0.05
                )
              ),

              column(3,
                numericInput(
                  ns("hwi_min_rate"),
                  "Min course-taking rate",
                  value = 0.10, min = 0.01, step = 0.01
                )
              ),

              column(6,
                uiOutput(ns("hwi_assumption_text"))
              )

            ) # end fluidRow
          ), # end projection controls

          # Run button
          div(
            style = "margin: 8px 0 12px;",
            actionButton(
              ns("hwi_run_rates"),
              "Run Projections",
              class = "btn-primary",
              icon  = icon("play")
            ),
            span("Re-run after changing programs or baseline terms.",
                 style = "font-size: 0.82em; color: #888; margin-left: 10px;")
          ),

          # Color legend
          div(
            style = "margin: 8px 0; font-size: 0.82em; color: #555;",
            tags$span(style = sprintf("background:%s; padding: 2px 8px; border-radius: 3px;", CEDAR_SURFACE_TINTS[["warning"]]), "meets threshold"),
            tags$span(style = sprintf("background:%s; padding: 2px 8px; border-radius: 3px; margin-left: 6px;", CEDAR_SURFACE_TINTS[["critical"]]), "≥ 1 section needed"),
            tags$span(style = "color: #aaa; margin-left: 12px;", "— = below threshold in this semester"),
            downloadButton(ns("hwi_export"), "Export CSV",
                           class = "btn btn-outline-secondary btn-sm",
                           style = "float: right; margin-top: -2px;")
          ),

          p("Rows = courses most impacted by the enrollment increase. ",
            "Columns = projected semesters. ",
            "Each cell: +N new = additional students from growth; ",
            "0.Xs = sections of additional demand; ",
            "X now → Y total = existing baseline students → projected total. ",
            "Click any cell for a detailed breakdown.",
            style = "font-size: 0.82em; color: #888; margin-bottom: 8px;"),

          uiOutput(ns("hwi_matrix_ui"),
                   placeholder = p("Select programs and click Run Projections to generate the matrix.",
                                   class = "text-muted py-4"))
        ),

        # ── Tab 2: Capacity Pressure ───────────────────────────────────────
        tabPanel(
          "Capacity Pressure",

          # Controls row
          div(
            style = "display: flex; align-items: center; gap: 20px; margin-bottom: 12px;",
            radioButtons(
              ns("hwi_pressure_season"),
              label    = NULL,
              choices  = c("Fall" = "fall", "Spring" = "spring"),
              selected = "fall",
              inline   = TRUE
            ),
            checkboxInput(
              ns("hwi_pressure_undergrad"),
              "Undergrad only",
              value = TRUE
            )
          ),

          div(
            style = "margin: 8px 0 12px;",
            actionButton(
              ns("hwi_run_pressure"),
              "Run Analysis",
              class = "btn-primary",
              icon  = icon("play")
            ),
            span("Re-run after changing programs or baseline terms.",
                 style = "font-size: 0.82em; color: #888; margin-left: 10px;")
          ),

          uiOutput(ns("hwi_pressure_ui"),
                   placeholder = p("Select programs and click Run Analysis.",
                                   class = "text-muted py-4"))
        ),

        # ── Tab 3: Enrollment Matrix ───────────────────────────────────────
        tabPanel(
          "Enrollment Matrix",

          # Controls row: season + undergrad
          div(
            style = "display: flex; align-items: center; gap: 20px; margin-bottom: 4px;",
            radioButtons(
              ns("hwi_matrix_season"),
              label    = NULL,
              choices  = c("Fall" = "fall", "Spring" = "spring"),
              selected = "fall",
              inline   = TRUE
            ),
            checkboxInput(
              ns("hwi_matrix_undergrad"),
              "Undergrad only",
              value = TRUE
            )
          ),

          # Controls: year range + min students
          div(
            style = "display: flex; align-items: flex-end; gap: 20px; margin-bottom: 4px;",
            div(
              style = "flex: 1;",
              sliderInput(
                ns("hwi_matrix_year_range"),
                "Year range (averaged across selected season)",
                min   = 2018,
                max   = 2025,
                value = c(2023, 2025),
                step  = 1,
                sep   = "",
                ticks = FALSE
              )
            ),
            div(
              style = "width: 140px; flex-shrink: 0;",
              numericInput(
                ns("hwi_matrix_min_n"),
                "Min avg students",
                value = 5, min = 1, max = 100, step = 1
              )
            )
          ),

          p("Average students per term from each selected program enrolled in each course. ",
            "Rows = courses (most enrollment at top). ",
            "Columns = program × status, sorted by headcount (most students on left). ",
            "Averages across all terms in the selected year range.",
            style = "font-size: 0.82em; color: #888; margin-bottom: 8px;"),

          div(
            style = "margin: 4px 0 12px;",
            actionButton(
              ns("hwi_run_matrix"),
              "Run Matrix",
              class = "btn-primary",
              icon  = icon("play")
            ),
            span("Re-run after changing programs or baseline terms.",
                 style = "font-size: 0.82em; color: #888; margin-left: 10px;")
          ),

          uiOutput(ns("hwi_enroll_matrix_ui"),
                   placeholder = p("Select programs and click Run Matrix.",
                                   class = "text-muted py-4")),
          DT::DTOutput(ns("hwi_enroll_matrix_dt"))
        )

      ) # end tabsetPanel

    ) # end layout_sidebar
  ) # end tagList
}


# =============================================================================
# healthWhatIfServer()
# =============================================================================

healthWhatIfServer <- function(id, programs, students, sections) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ── Populate start-term dropdown ─────────────────────────────────────────
    # Offer all fall terms in the data PLUS the next 3 future falls so users
    # can plan for upcoming admissions cycles.
    observe({
      existing_falls <- programs %>%
        pull(term) %>%
        unique() %>%
        keep(~ grepl("80$", as.character(.x))) %>%
        sort()

      last_year    <- as.integer(substr(as.character(max(existing_falls)), 1, 4))
      future_falls <- as.integer(paste0(seq(last_year + 1, last_year + 3), "80"))
      all_falls    <- c(existing_falls, future_falls)

      choices <- setNames(
        all_falls,
        paste("Fall", substr(as.character(all_falls), 1, 4))
      )

      # Default: first future fall (overridden in hindcast mode below)
      default <- future_falls[1]

      updateSelectInput(session, "hwi_start_term",
                        choices  = choices,
                        selected = default)
    })

    # In hindcast mode, auto-set start term to the fall after the cutoff
    observeEvent(list(input$hwi_hindcast, input$hwi_cutoff_term), {
      if (!isTRUE(input$hwi_hindcast)) return()
      cutoff <- suppressWarnings(as.integer(input$hwi_cutoff_term))
      if (is.null(cutoff) || is.na(cutoff)) return()
      cutoff_year  <- as.integer(substr(as.character(cutoff), 1, 4))
      first_val_fall <- as.integer(paste0(cutoff_year + 1L, "80"))
      updateSelectInput(session, "hwi_start_term", selected = first_val_fall)
    }, ignoreInit = TRUE)

    # ── Program selector ─────────────────────────────────────────────────────
    # Populate selectize choices from cedar_programs (all unique program names,
    # major type — premajors share the same program_name as their major).
    all_program_names <- programs %>%
      filter(program_type == "Major") %>%
      distinct(program_name) %>%
      arrange(program_name) %>%
      pull(program_name)

    observe({
      default_programs <- COHORT_PRESETS[["Top 10 by Enrollment"]]$programs
      updateSelectizeInput(session, "hwi_programs",
                           choices  = all_program_names,
                           selected = intersect(default_programs, all_program_names),
                           server   = TRUE)
    })

    # When preset changes, update program list to match
    observeEvent(input$hwi_preset, {
      req(nchar(input$hwi_preset) > 0)
      preset_programs <- COHORT_PRESETS[[input$hwi_preset]]$programs
      updateSelectizeInput(session, "hwi_programs",
                           selected = intersect(preset_programs, all_program_names))
    }, ignoreInit = TRUE)

    # Single source of truth for selected programs
    selected_programs_rv <- reactive({
      req(length(input$hwi_programs) > 0)
      input$hwi_programs
    })

    # ── Hindcast cutoff term choices ─────────────────────────────────────────
    # Offer all past falls except the most recent (we need at least one
    # post-cutoff term to validate against). Default to 3 years ago.
    observe({
      all_falls <- programs %>%
        pull(term) %>% unique() %>%
        keep(~ grepl("80$", as.character(.x))) %>%
        sort()

      # Exclude the most recent fall — need post-cutoff data to validate
      past_falls <- head(all_falls, -1)
      choices <- setNames(past_falls,
                          paste("Fall", substr(as.character(past_falls), 1, 4)))
      n <- length(past_falls)
      default <- if (n >= 3) past_falls[n - 2] else past_falls[n]

      updateSelectInput(session, "hwi_cutoff_term",
                        choices  = choices,
                        selected = default)
    })

    # ── Hindcast actual demand ────────────────────────────────────────────────
    # Computes actual health-student enrollment change per course per term
    # for all terms after the cutoff. Used to overlay on the projected matrix.
    # This is an eventReactive (not reactive) so it only runs when the user
    # clicks Run Projections — same trigger as rates_rv. This ensures hindcast
    # data and projection data are always computed together and the matrix
    # re-renders once with both available, rather than twice in sequence.
    hindcast_rv <- eventReactive(input$hwi_run_rates, {
      if (!isTRUE(input$hwi_hindcast)) return(NULL)
      cutoff <- suppressWarnings(as.integer(input$hwi_cutoff_term))
      if (is.null(cutoff) || is.na(cutoff)) return(NULL)

      prog_names <- selected_programs_rv()

      all_terms   <- sort(unique(programs$term))
      all_falls   <- all_terms[grepl("80$", as.character(all_terms))]
      all_springs <- all_terms[grepl("10$", as.character(all_terms))]

      baseline_terms   <- c(tail(all_falls[all_falls     <= cutoff], 6),
                            tail(all_springs[all_springs <= cutoff], 6))
      validation_terms <- c(all_falls[all_falls     > cutoff],
                            all_springs[all_springs > cutoff])

      if (length(validation_terms) == 0) return(NULL)

      message("[health-whatif module] Hindcast: cutoff=", cutoff,
              " baseline_terms=", paste(baseline_terms, collapse=","),
              " validation_terms=", paste(validation_terms, collapse=","),
              " prog_names=", paste(prog_names, collapse=","))

      # ── Compute per-program actual headcount change ─────────────────────────
      # For each program independently: baseline avg headcount vs first val fall.
      # Using per-program deltas (not a combined average) correctly handles the
      # case where programs grow at very different rates — e.g. Nursing +4%,
      # Nursing Practice +132%, Dental Hygiene +27%. A combined delta_pct would
      # dilute the fast-growing programs and inflate the slow/shrinking ones.
      first_val_fall    <- min(validation_terms[validation_terms %in% all_falls])
      baseline_falls_hc <- baseline_terms[baseline_terms %in% all_falls]

      # Single vectorized pass for baseline avg — avoids N filter scans.
      bl_avg_tbl <- programs %>%
        filter(program_name %in% prog_names, program_type == "Major",
               term %in% baseline_falls_hc) %>%
        group_by(program_name, term) %>%
        summarise(n = n_distinct(student_id), .groups = "drop") %>%
        group_by(program_name) %>%
        summarise(baseline_hc = round(mean(n)), .groups = "drop")

      vl_tbl <- programs %>%
        filter(program_name %in% prog_names, program_type == "Major",
               term == first_val_fall) %>%
        group_by(program_name) %>%
        summarise(val_hc = n_distinct(student_id), .groups = "drop")

      per_prog_hc <- tibble(program_name = prog_names) %>%
        left_join(bl_avg_tbl, by = "program_name") %>%
        left_join(vl_tbl,     by = "program_name") %>%
        mutate(
          baseline_hc      = coalesce(baseline_hc, 0L),
          val_hc           = coalesce(val_hc, 0L),
          actual_delta_n   = val_hc - baseline_hc,
          actual_delta_pct = if_else(baseline_hc > 0,
                                     round((val_hc - baseline_hc) / baseline_hc * 100, 1),
                                     NA_real_)
        )

      message("[health-whatif module] Hindcast per-program growth (first val fall=", first_val_fall, "):")
      purrr::pwalk(per_prog_hc, function(program_name, baseline_hc, val_hc, actual_delta_n, actual_delta_pct, ...) {
        message("  ", program_name, ": ", baseline_hc, " → ", val_hc,
                " (", if (!is.na(actual_delta_pct)) paste0(actual_delta_pct, "%") else "N/A", ")")
      })

      actual_demand <- tryCatch(
        get_actual_course_demand(
          students         = students,
          programs         = programs,
          program_names    = prog_names,
          baseline_terms   = baseline_terms,
          validation_terms = validation_terms
        ),
        error = function(e) {
          message("[health-whatif module] Hindcast failed: ", e$message)
          NULL
        }
      )

      message("[health-whatif module] Hindcast result: ",
              if (is.null(actual_demand)) "NULL"
              else paste(nrow(actual_demand), "rows,",
                         n_distinct(actual_demand$subject_course), "courses,",
                         "term_labels:", paste(unique(actual_demand$term_label), collapse=",")))

      list(
        actual_demand  = actual_demand,
        per_prog_hc    = per_prog_hc,
        first_val_fall = first_val_fall
      )
    })

    # ── Subgroup summary ─────────────────────────────────────────────────────
    # Shows average fall headcount per program × status (Major / Pre-Major).
    # Computed directly from cedar_programs — no slow rate computation needed.
    # Uses the same baseline_terms slider as the rate model so the summary
    # reflects exactly the population the rates are computed from.
    # Returns a list so the UI can display both the table and the audit trail.
    subgroup_rv <- reactive({
      prog_names <- selected_programs_rv()

      all_fall_terms <- programs %>%
        pull(term) %>%
        unique() %>%
        keep(~ grepl("80$", as.character(.x))) %>%
        sort()

      n_baseline <- isolate(input$hwi_baseline_terms) %||% 6L
      fall_terms <- tail(all_fall_terms, n_baseline)

      # Total rows in cedar_programs before any filtering
      n_rows_total <- nrow(programs)

      # Rows matching selected program names and Major type (any term)
      matched <- programs %>%
        filter(program_name %in% prog_names, program_type == "Major")
      n_rows_matched <- nrow(matched)
      n_students_ever <- n_distinct(matched$student_id)

      # Restricted to baseline fall window
      windowed <- matched %>% filter(term %in% fall_terms)
      n_rows_windowed <- nrow(windowed)
      n_students_windowed <- n_distinct(windowed$student_id)

      summary_tbl <- windowed %>%
        group_by(program_name, is_pre_major, term) %>%
        summarise(n = n_distinct(student_id), .groups = "drop") %>%
        group_by(program_name, is_pre_major) %>%
        summarise(avg_headcount = mean(n), .groups = "drop") %>%
        mutate(
          status    = if_else(is_pre_major, "Pre-Major", "Major"),
          pct_share = avg_headcount / sum(avg_headcount),
          pct_label = scales::percent(pct_share, accuracy = 0.1)
        ) %>%
        arrange(program_name, is_pre_major)

      list(
        tbl                 = summary_tbl,
        prog_names          = prog_names,
        fall_terms          = fall_terms,
        n_rows_total        = n_rows_total,
        n_rows_matched      = n_rows_matched,
        n_students_ever     = n_students_ever,
        n_rows_windowed     = n_rows_windowed,
        n_students_windowed = n_students_windowed
      )
    })

    output$hwi_subgroup_ui <- renderUI({
      sg <- subgroup_rv()
      req(nrow(sg$tbl) > 0)

      tbl      <- sg$tbl
      total_hc <- sum(tbl$avg_headcount)
      delta_pct_preview <- isolate(input$hwi_delta_pct) %||% 10
      delta_n  <- round(total_hc * delta_pct_preview / 100)

      fall_labels <- paste("Fall", substr(as.character(sg$fall_terms), 1, 4))

      tagList(

        # ── Audit trail ───────────────────────────────────────────────────────
        div(
          style = "font-size: 0.82em; color: #555; background: #F6F4F0;
                   border-left: 3px solid #C8BFB0; padding: 10px 14px;
                   margin-bottom: 12px; line-height: 1.7;",
          tags$strong("How this is calculated:"), tags$br(),
          tags$span(
            "Source: ", tags$code("cedar_programs"),
            sprintf(" (%s rows total)", format(sg$n_rows_total, big.mark = ",")),
            tags$br(),
            sprintf("Filtered to program_type = 'Major' and the %d selected program(s) → %s rows, %s unique students ever enrolled.",
                    length(sg$prog_names),
                    format(sg$n_rows_matched, big.mark = ","),
                    format(sg$n_students_ever, big.mark = ",")),
            tags$br(),
            sprintf("Further restricted to the %d most recent fall terms (%s) → %s rows, %s unique students.",
                    length(sg$fall_terms),
                    paste(fall_labels, collapse = ", "),
                    format(sg$n_rows_windowed, big.mark = ","),
                    format(sg$n_students_windowed, big.mark = ",")),
            tags$br(),
            "Avg Fall HC = mean of distinct student counts per fall term within this window.",
            tags$br(),
            sprintf("Share = each row's avg headcount ÷ total avg headcount (%s).",
                    format(round(total_hc), big.mark = ",")),
            tags$br(),
            sprintf("+%d%% would add = avg headcount × %d%%.", delta_pct_preview, delta_pct_preview)
          )
        ),

        # ── Summary sentence ──────────────────────────────────────────────────
        p(
          strong(format(round(total_hc), big.mark = ",")),
          " average fall headcount across all selected programs (majors + pre-majors). ",
          sprintf("A %d%% increase would add roughly ", delta_pct_preview),
          strong(format(delta_n, big.mark = ",")),
          " students.",
          style = "margin-bottom: 8px;"
        ),

      )
    })

    output$hwi_subgroup_dt <- reactable::renderReactable({
      sg <- subgroup_rv()
      req(nrow(sg$tbl) > 0)
      tbl <- sg$tbl
      delta_pct_preview <- isolate(input$hwi_delta_pct) %||% 10
      delta_col <- sprintf("+%d%% would add", delta_pct_preview)
      display <- tbl %>%
        transmute(
          Program       = program_name,
          Status        = status,
          `Avg Fall HC` = round(avg_headcount),
          `Share`       = pct_label,
          !!delta_col  := round(avg_headcount * delta_pct_preview / 100)
        )
      column_defs <- list(
        Program = reactable::colDef(minWidth = 150),
        Status = reactable::colDef(maxWidth = 90),
        `Avg Fall HC` = reactable::colDef(align = "right", maxWidth = 105),
        `Share` = reactable::colDef(align = "right", maxWidth = 80)
      )
      column_defs[[delta_col]] <- reactable::colDef(align = "right", maxWidth = 115)
      reactable::reactable(
        display,
        theme = cedar_tbl_theme,
        striped = TRUE,
        highlight = TRUE,
        compact = TRUE,
        defaultPageSize = 25,
        columns = column_defs
      )
    })

    # ── Rate computation (slow — triggered by button only) ───────────────────
    # get_health_course_rates() joins cedar_programs to cedar_students for each
    # program individually. For 10+ programs this takes 20–40 seconds.
    # We cache in rates_rv so projection re-runs (slider moves) are instant.
    rates_rv <- eventReactive(input$hwi_run_rates, {
      valid_programs <- selected_programs_rv()
      req(length(valid_programs) > 0)

      message("[health-whatif module] Computing course rates for: ",
              paste(valid_programs, collapse = ", "))

      status_id <- "hwi_rates_loading"
      showNotification(
        paste0("Computing course-taking rates for ", length(valid_programs),
               " program(s)... this may take 20–40 seconds."),
        type     = "warning",
        duration = NULL,
        id       = status_id
      )

      result <- tryCatch(
        get_health_course_rates(
          programs         = programs,
          students         = students,
          program_names    = valid_programs,
          n_baseline_terms = input$hwi_baseline_terms,
          min_n            = input$hwi_min_n,
          max_term         = if (isTRUE(input$hwi_hindcast))
                               suppressWarnings(as.integer(input$hwi_cutoff_term))
                             else NULL
        ),
        error = function(e) {
          showNotification(paste("Rate computation failed:", e$message), type = "error")
          NULL
        }
      )

      removeNotification(status_id)

      if (!is.null(result) && nrow(result) > 0) {
        showNotification(
          paste0("Rates ready: ", n_distinct(result$subject_course),
                 " courses across ", n_distinct(result$program_name), " programs."),
          type = "message", duration = 3
        )
      }

      result
    })

    # ── Section size lookup (computed once, lazily on first tab use) ─────────
    # Wrapped in reactive() so it doesn't run at app startup — only when the
    # tab is first opened. Cached thereafter; sections never changes per session.
    section_sizes_rv <- reactive({
      get_section_size_lookup(sections, n_baseline_falls = 3)
    })

    # ── Projection (fast — reruns on every control change) ───────────────────
    # project_health_increase() is pure arithmetic on the rate table.
    # No data joins — runs in < 1 second.
    proj_rv <- reactive({
      rates <- rates_rv()
      section_sizes <- section_sizes_rv()
      req(!is.null(rates), nrow(rates) > 0, !is.null(section_sizes))
      req(nchar(input$hwi_start_term %||% "") > 0)

      start_term <- as.integer(input$hwi_start_term)
      req(!is.na(start_term))

      # In hindcast mode, pass per-program observed headcount changes so the
      # projection uses each program's actual growth rate independently.
      hc <- hindcast_rv()
      per_prog_override <- if (isTRUE(input$hwi_hindcast) && !is.null(hc)) {
        hc$per_prog_hc  # tibble: program_name, actual_delta_n
      } else {
        NULL
      }

      project_health_increase(
        rates             = rates,
        sizes             = section_sizes,
        start_term        = start_term,
        delta_pct         = input$hwi_delta_pct,
        n_years           = input$hwi_n_years,
        goal              = input$hwi_goal,
        attrition         = input$hwi_attrition %||% 0,
        threshold         = input$hwi_threshold,
        per_prog_override = per_prog_override
      )
    })

    # ── Assumption text ───────────────────────────────────────────────────────
    # Explains in plain English exactly what was computed, so every number in
    # the matrix is traceable to user inputs and data sources.
    output$hwi_start_term_label <- renderUI({
      if (isTRUE(input$hwi_hindcast)) {
        tagList("New cohort starts",
                span(" (set by hindcast cutoff)", style = "font-size: 0.8em; color: #888;"))
      } else {
        "New cohort starts"
      }
    })

    output$hwi_assumption_text <- renderUI({
      proj <- proj_rv()
      req(!is.null(proj))

      a    <- proj$assumptions
      goal <- if (a$goal == "graduates") "graduates" else "enrolled students"
      attr_note <- if (a$goal == "graduates" && a$attrition > 0) {
        paste0(
          " (", scales::percent(a$attrition), " attrition assumed — ",
          "demand across all credit levels is uniformly inflated by ",
          round(1 / (1 - a$attrition), 2), "× to reach the graduation target)"
        )
      } else ""

      projection_note <- paste0(
        "Each projected semester shows the same flat increase — ",
        "this is a steady-state snapshot, not a cohort accumulation model. ",
        "The same additional demand appears in every fall and spring across the ",
        a$n_years, "-year window."
      )

      div(
        style = "background: #F6F4F0; border-radius: 4px; padding: 10px 14px; font-size: 0.82em; color: #555;",
        tags$strong("How these numbers are calculated:"),
        tags$ul(
          style = "margin: 4px 0 0 0; padding-left: 18px;",
          tags$li({
            hc <- hindcast_rv()
            if (isTRUE(input$hwi_hindcast) && !is.null(hc)) {
              pph <- hc$per_prog_hc
              summary_str <- paste(
                sprintf("%s: %+.0f", pph$program_name, pph$actual_delta_n),
                collapse = "; "
              )
              paste0(
                "Hindcast mode: per-program observed headcount change used ",
                "instead of the slider. First validation fall: ",
                hc$first_val_fall, ". Changes: ", summary_str, "."
              )
            } else {
              paste0(a$delta_pct, "% more ", goal, " across all selected programs",
                     attr_note, ".")
            }
          }),
          tags$li(
            paste0(
              "Each program's additional students = its average fall headcount × ",
              a$delta_pct, "% (see Subgroup Summary above for per-program counts)."
            )
          ),
          tags$li(
            paste0(
              "Course demand = additional students × entry-band rate. ",
              "Rates are weighted by the historical credit-band distribution of new program ",
              "entrants (what credit level were students at when they first appeared in the ",
              "program?). True freshmen land in band 1; CC transfers in band 2; ",
              "program-switchers wherever their earned credits place them. ",
              "Rates are based on the last ", input$hwi_baseline_terms, " fall and spring terms. ",
              "Caveat: if growth comes primarily from improved retention rather than new admits, ",
              "this will overestimate band-1 demand and underestimate upper-division demand."
            )
          ),
          tags$li(projection_note),
          tags$li(
            paste0(
              "Sections fraction = projected additional students ÷ average section size ",
              "(from the last 3 fall terms). ",
              "Only courses where at least one semester reaches ≥ ", a$threshold,
              " sections impact are shown. Cells below that in a given semester appear blank."
            )
          )
        )
      )
    })

    # ── Matrix table ──────────────────────────────────────────────────────────
    # Renders the courses × semesters matrix.
    # Each cell shows delta_students and sections_fraction.
    # Color-coded by threshold; click triggers detail modal.

    # Store the current proj data for use in the modal (can't pass reactives
    # into JS callbacks directly)
    proj_cache  <- reactiveVal(NULL)
    # Cache max_rate per course so the matrix filter doesn't re-call rates_rv()
    # after it may have been invalidated. Both are set together when rates run.
    max_rate_cache <- reactiveVal(NULL)

    observeEvent(input$hwi_run_rates, {
      r <- rates_rv()
      if (!is.null(r) && nrow(r) > 0) {
        max_rate_cache(
          r %>%
            group_by(subject_course) %>%
            summarise(max_rate = max(rate, na.rm = TRUE), .groups = "drop")
        )
      }
    }, ignoreInit = TRUE)

    output$hwi_matrix_ui <- renderUI({
      proj <- proj_rv()
      req(!is.null(proj), nrow(proj$matrix_long) > 0)
      proj_cache(proj)

      max_rates <- max_rate_cache()
      req(!is.null(max_rates))

      # In hindcast mode, skip the sections_fraction threshold filter — the actual
      # delta_pct is derived from data and may be small or negative, so no courses
      # would pass. Show all courses above the min_rate so comparisons are visible.
      in_hindcast <- isTRUE(input$hwi_hindcast)

      shown_courses <- proj$matrix_long %>%
        left_join(max_rates, by = "subject_course") %>%
        group_by(subject_course) %>%
        filter(max_rate >= input$hwi_min_rate,
               in_hindcast | any(!is.na(sections_fraction) & sections_fraction >= input$hwi_threshold)) %>%
        ungroup() %>%
        pull(subject_course) %>%
        unique()

      ml <- proj$matrix_long %>%
        filter(subject_course %in% shown_courses)

      if (nrow(ml) == 0) {
        return(p("No courses meet the current minimum rate filter. Try lowering it.",
                 style = "color: #888; padding: 16px;"))
      }

      # Build the display table row by row
      # Columns: course title, then one column per calendar semester
      sem_order <- ml %>%
        arrange(calendar_term) %>%
        pull(term_label) %>%
        unique()

      # Wide table: one row per course, one col per semester
      wide <- ml %>%
        select(subject_course, course_title, term_label,
               delta_students, baseline_students, total_students,
               sections_fraction, needs_flag, avg_section_size) %>%
        tidyr::pivot_wider(
          id_cols     = c(subject_course, course_title),
          names_from  = term_label,
          values_from = c(delta_students, baseline_students, total_students,
                          sections_fraction, needs_flag, avg_section_size)
        )

      # Sort by peak sections_fraction across all semesters
      sf_cols <- paste0("sections_fraction_", sem_order)
      sf_cols_present <- intersect(sf_cols, names(wide))
      if (length(sf_cols_present) > 0) {
        wide <- wide %>%
          mutate(peak = pmax(!!!rlang::syms(sf_cols_present), na.rm = TRUE)) %>%
          arrange(desc(peak)) %>%
          select(-peak)
      }

      # Build hindcast lookup: course -> term_label -> actual_delta
      # Computed once here so the per-cell loop doesn't re-call hindcast_rv().
      hc_result      <- hindcast_rv()
      hindcast_data  <- hc_result$actual_demand
      message("[health-whatif matrix] hindcast_data: ",
              if (is.null(hindcast_data)) "NULL"
              else paste(nrow(hindcast_data), "rows"))
      message("[health-whatif matrix] sem_order: ", paste(sem_order, collapse=", "))
      hindcast_lookup <- if (!is.null(hindcast_data) && nrow(hindcast_data) > 0) {
        split(hindcast_data, hindcast_data$subject_course) %>%
          lapply(function(df) setNames(df$actual_delta, df$term_label))
      } else {
        NULL
      }
      message("[health-whatif matrix] hindcast_lookup courses: ",
              if (is.null(hindcast_lookup)) "NULL"
              else paste(length(hindcast_lookup), "courses"))

      # Build an HTML table manually so we can embed color and click handlers
      header_row <- do.call(tags$tr, c(
        list(
          tags$th("Course", style = "min-width: 140px;"),
          tags$th("Title",  style = "min-width: 180px;")
        ),
        purrr::map(sem_order, ~ tags$th(.x, style = "min-width: 110px; text-align: center;"))
      ))

      body_rows <- purrr::map(seq_len(nrow(wide)), function(i) {
        row <- wide[i, ]
        cells <- purrr::map(sem_order, function(sem) {
          delta    <- row[[paste0("delta_students_",    sem)]]
          baseline <- row[[paste0("baseline_students_", sem)]]
          total    <- row[[paste0("total_students_",    sem)]]
          sf       <- row[[paste0("sections_fraction_", sem)]]
          flag     <- row[[paste0("needs_flag_",        sem)]]
          avgsz    <- row[[paste0("avg_section_size_",  sem)]]

          # Hindcast: actual delta for this course/term.
          # Use [ (single bracket) on the named vector — never [[ — so missing
          # names return NA instead of throwing "subscript out of bounds".
          course_hc    <- hindcast_lookup[[row$subject_course]]  # NULL or named vec
          actual_delta <- if (!is.null(course_hc) && sem %in% names(course_hc)) {
            course_hc[sem]
          } else {
            NULL
          }

          if (is.na(delta) || delta < 0.5) {
            # No meaningful predicted impact — but show actual if it exists
            if (!is.null(actual_delta) && !is.na(actual_delta) && abs(actual_delta) >= 0.5) {
              return(tags$td(
                style = "text-align: center; color: #888; padding: 6px 8px;",
                div("— pred", style = "font-size: 0.78em;"),
                div(paste0(if (actual_delta >= 0) "+" else "", round(actual_delta), " actual"),
                    style = "font-size: 0.78em; color: #555;")
              ))
            }
            return(tags$td("—", style = "text-align: center; color: #ccc;"))
          }

          # Color by sections fraction of NEW students only (delta).
          # Red = ≥ 1 full additional section from growth; amber = notable but < 1.
          bg_color <- if (is.na(sf) || sf < input$hwi_threshold) {
            "#ffffff"
          } else if (sf >= 1.0) {
            CEDAR_SURFACE_TINTS[["critical"]]
          } else {
            CEDAR_SURFACE_TINTS[["warning"]]
          }

          sf_label <- if (is.na(sf)) {
            "(no section data)"
          } else {
            paste0(round(sf, 2), "s")
          }

          # Total line: existing + new students combined.
          # Shows planners the full expected health-student load, not just the delta.
          total_line <- if (!is.na(total) && !is.na(baseline) && baseline > 0.5) {
            div(
              paste0(round(baseline), " now → ", round(total), " total"),
              style = "font-size: 0.75em; color: #666; margin-top: 1px;"
            )
          } else NULL

          # Accuracy indicator for hindcast
          actual_line <- if (!is.null(actual_delta) && !is.na(actual_delta)) {
            pct_err <- if (abs(delta) > 0.5) abs(actual_delta - delta) / abs(delta) else NA
            color <- if (is.na(pct_err))      "#888"
                     else if (pct_err <= 0.25) "#2d6a2d"
                     else if (pct_err <= 0.75) "#8a5c00"
                     else                      "#a00000"
            err_label <- if (!is.na(pct_err)) paste0(" (", round(pct_err * 100), "% off)") else ""
            div(
              paste0(if (actual_delta >= 0) "+" else "", round(actual_delta), " actual", err_label),
              style = paste0("font-size: 0.78em; color: ", color,
                             "; font-weight: 600; margin-top: 2px;")
            )
          } else NULL

          click_js <- sprintf(
            "Shiny.setInputValue('%s', {course: '%s', sem: '%s', n: Math.random()}, {priority: 'event'})",
            ns("hwi_cell_click"),
            row$subject_course,
            sem
          )

          tags$td(
            style   = paste0("background:", bg_color, "; text-align: center; ",
                             "cursor: pointer; padding: 6px 8px;"),
            onclick = click_js,
            div(
              paste0("+", round(delta), if (!is.null(actual_line)) " pred" else " new"),
              style = "font-size: 0.88em; font-weight: 600;"
            ),
            div(sf_label, style = "font-size: 0.78em; color: #555;"),
            total_line,
            actual_line
          )
        })

        do.call(tags$tr, c(
          list(
            tags$td(row$subject_course, style = "font-size: 0.85em; white-space: nowrap;"),
            tags$td(row$course_title,   style = "font-size: 0.82em; color: #555;")
          ),
          cells
        ))
      })

      div(
        style = "overflow-x: auto;",
        tags$table(
          class = "table table-sm table-bordered",
          style = "font-size: 0.88em;",
          tags$thead(header_row),
          do.call(tags$tbody, body_rows)
        )
      )
    })

    # ── Cell click → detail modal ────────────────────────────────────────────
    # When the user clicks a cell, show a modal with:
    #   - Total current enrollment for that course (from cedar_sections)
    #   - Per-program breakdown: additional students, rate, credit band
    #   - Section size and how the sections_fraction was calculated
    #   - Assumptions used for this specific cell

    observeEvent(input$hwi_cell_click, {
      click  <- input$hwi_cell_click
      req(!is.null(click$course), !is.null(click$sem))

      proj   <- proj_cache()
      req(!is.null(proj))

      course <- click$course
      sem    <- click$sem

      # Pull the cell's data from matrix_long
      cell <- proj$matrix_long %>%
        filter(subject_course == course, term_label == sem)

      if (nrow(cell) == 0) return()

      # Per-program contributions for this course × semester
      contrib <- cell$program_contributions[[1]]

      avg_size <- cell$avg_section_size[1]
      delta    <- cell$delta_students[1]
      sf       <- cell$sections_fraction[1]

      # Build the modal
      showModal(cedar_info_modal(
        title = paste0(course, " — ", sem),
        size  = "l",

        # ── Summary row ───────────────────────────────────────────────────────
        fluidRow(
          column(3,
            div(class = "stat-box",
              div(class = "stat-value", round(delta)),
              div(class = "stat-label", "Additional students")
            )
          ),
          column(3,
            div(class = "stat-box",
              div(class = "stat-value",
                  if (is.na(sf)) "N/A" else paste0(round(sf, 2), "×")),
              div(class = "stat-label", "Sections fraction")
            )
          ),
          column(3,
            div(class = "stat-box",
              div(class = "stat-value",
                  if (is.na(avg_size)) "N/A" else round(avg_size, 1)),
              div(class = "stat-label", "Avg section size (enrolled)")
            )
          ),
          column(3,
            div(class = "stat-box",
              div(class = "stat-value",
                  if (is.na(sf)) "N/A" else ceiling(sf)),
              div(class = "stat-label", "Full sections needed")
            )
          )
        ),

        hr(),

        # ── Calculation trace ──────────────────────────────────────────────
        tags$h6("How this cell was calculated", class = "cedar-section-heading--sub"),
        p(
          paste0(
            "Additional students (", round(delta, 1), ") = sum across all programs of: ",
            "additional enrolled headcount × ",
            "historical fraction of program students who took this course ",
            "in a ", tolower(sub(" .*", "", sem)), " semester. ",
            "Steady-state model: the same delta applies to every projected semester."
          ),
          style = "font-size: 0.85em; color: #555;"
        ),
        if (!is.na(sf)) {
          p(
            paste0(
              "Sections fraction (", round(sf, 2), ") = ", round(delta, 1),
              " additional students ÷ ", round(avg_size, 1),
              " average section size."
            ),
            style = "font-size: 0.85em; color: #555;"
          )
        },

        # ── Per-program breakdown ───────────────────────────────────────────
        if (!is.null(contrib) && nrow(contrib) > 0) {
          tagList(
            tags$h6("Breakdown by Program",
                    style = "font-weight: 600; margin-top: 12px;"),
            p(
              "Entry rate = weighted by credit band at first program appearance (the historical mix of freshmen, transfers, and program-switchers). ",
              "Steady-state rate shown for comparison — it would apply if growth came from retention rather than new admits. ",
              "Additional = avg enrolled headcount × delta %. Delta = Additional × Entry rate.",
              style = "font-size: 0.82em; color: #888;"
            ),
            reactable::reactable(
              contrib %>%
                transmute(
                  Program              = program_name,
                  `Avg enrolled`       = round(avg_headcount, 0),
                  `Additional`         = round(additional_base, 1),
                  `Steady-state rate`  = scales::percent(rate, accuracy = 0.1),
                  `Entry rate`         = if_else(
                    !is.na(entry_rate),
                    scales::percent(entry_rate, accuracy = 0.1),
                    "(no entry data)"
                  ),
                  `Used`               = scales::percent(effective_rate, accuracy = 0.1),
                  Delta                = round(delta_from_prog, 1)
                ),
              theme = cedar_tbl_theme,
              striped = TRUE,
              highlight = TRUE,
              compact = TRUE,
              defaultPageSize = 30,
              columns = list(
                Program = reactable::colDef(minWidth = 180),
                `Avg enrolled` = reactable::colDef(align = "right"),
                Additional = reactable::colDef(align = "right"),
                `Steady-state rate` = reactable::colDef(align = "right"),
                `Entry rate` = reactable::colDef(align = "right"),
                Used = reactable::colDef(align = "right"),
                Delta = reactable::colDef(align = "right")
              )
            )
          )
        }

      )) # end showModal
    }) # end observeEvent cell click

    # ── Pressure analysis ─────────────────────────────────────────────────────
    # eventReactive: triggered by the tab's own Run Analysis button.
    # Captures season/undergrad at the moment the button is clicked so
    # the display stays stable until the user explicitly re-runs.
    pressure_rv <- eventReactive(input$hwi_run_pressure, {
      prog_names <- selected_programs_rv()
      req(length(prog_names) > 0)
      season <- input$hwi_pressure_season %||% "fall"

      tryCatch(
        get_course_pressure(
          programs         = programs,
          students         = students,
          sections         = sections,
          program_names    = prog_names,
          # Pressure splits its window into early/recent halves, so it needs
          # 2× as many terms as the rate model to get the same half-window size.
          # E.g. slider = 6 → 12 terms total → 6 early + 6 recent.
          n_baseline_terms = input$hwi_baseline_terms * 2L,
          min_health_n     = input$hwi_min_n,
          season           = season,
          undergrad_only   = isTRUE(input$hwi_pressure_undergrad)
        ),
        error = function(e) {
          message("[health-whatif module] Pressure computation failed: ", e$message)
          NULL
        }
      )
    })

    output$hwi_pressure_ui <- renderUI({
      result <- pressure_rv()
      req(!is.null(result))
      pr <- result$pressure
      req(nrow(pr) > 0)

      # ── Audit trail ────────────────────────────────────────────────────────
      season_label <- if (result$season == "fall") "Fall" else "Spring"
      term_fmt <- function(terms) {
        yrs <- as.integer(substr(as.character(terms), 1, 4))
        paste0(season_label, " ", min(yrs), "–", max(yrs))
      }
      early_label  <- term_fmt(result$early_terms)
      recent_label <- term_fmt(result$recent_terms)

      audit_div <- div(
        style = "font-size: 0.82em; color: #555; background: #F6F4F0;
                 border-left: 3px solid #C8BFB0; padding: 10px 14px;
                 margin-bottom: 14px; line-height: 1.8;",
        tags$strong("What is being measured:"), tags$br(),
        tags$strong("Programs: "), paste(result$program_names, collapse = ", "), tags$br(),
        tags$strong("Season: "), season_label,
        " — toggle above to compare fall vs spring patterns.", tags$br(),
        tags$strong("Scope: "),
        if (result$undergrad_only)
          "Undergraduate students only (cedar_programs: student_level = 'Undergraduate'; cedar_students: student_level = 'UG'; sections: level = upper or lower)."
        else
          "All students (no level filter applied).",
        tags$br(),
        tags$strong("Baseline window: "), early_label, " (early) and ",
        recent_label, " (recent). ",
        "The slider value is doubled so each half-window matches the rate model's depth ",
        "(slider = 6 → 12 terms total → 6 early + 6 recent).",
        tags$br(),
        tags$strong("Min health students: "), result$min_health_n,
        " per term average before a course appears.", tags$br(), tags$br(),

        tags$strong("Signal definitions:"), tags$br(),
        tags$strong("Fill"), " — ",
        "How full sections are on average, and whether fill rate is rising. ",
        "Computed as: enrolled ÷ (enrolled + available seats), ",
        "weighted by section size, then averaged across ", season_label, " terms. ",
        "Flagged if avg fill ≥ 85% or rising ≥ 1 percentage point per year. ",
        tags$em("Banner's ‘capacity’ field is unreliable (many sections show 99999); ",
                "‘available’ is used instead as it reflects actual seats remaining."),
        tags$br(),
        tags$strong("Share"), " — ",
        "Health program students as a fraction of all students enrolled in the course, ",
        "averaged across the recent window. ",
        "Flagged if ≥ 30%. High share means program enrollment growth drives this course directly.",
        tags$br(),
        tags$strong("Rate ↓"), " — ",
        "Of all students enrolled in the selected programs combined in a given term, ",
        "what fraction took this course? Compared early vs recent window. ",
        "Flagged if the rate dropped more than 15 percentage points. ",
        "A declining take rate at stable or growing program headcount suggests ",
        "students who need the course are not getting it when they need it. ",
        tags$em("Note: the denominator is the total combined headcount across all selected programs, ",
                "not per-program. A course taken primarily by one program will show a low rate ",
                "when many programs are selected."),
        tags$br(),
        tags$strong("Drift"), " — ",
        "Average credit band (0–30 = band 1, 31–60 = band 2, etc.) at which ",
        "health students are enrolled in the course, compared early vs recent. ",
        "Flagged if the average shifted ≥ 0.3 bands toward a higher credit level. ",
        "Rightward drift means students are taking the course later — ",
        "consistent with repeated failed registration attempts before finally getting a seat.",
        tags$br(), tags$br(),
        tags$em("Each signal is independently noisy. ",
                "3 or 4 flags together is a meaningful pattern; 1–2 flags warrants watching.")
      )

      # Helper: flag cell — red if flagged, light gray if not, "—" if no data
      flag_cell <- function(flagged, label, detail = NULL) {
        if (is.na(flagged)) {
          return(tags$td("—", style = "text-align: center; color: #ccc; font-size: 0.82em;"))
        }
        bg <- if (flagged) CEDAR_SURFACE_TINTS[["critical"]] else "#F6F4F0"
        tags$td(
          div(label,  style = "font-weight: 600; font-size: 0.82em;"),
          if (!is.null(detail)) div(detail, style = "font-size: 0.75em; color: #666;"),
          style = paste0("text-align: center; background:", bg, "; padding: 4px 6px;")
        )
      }

      header_row <- tags$tr(
        tags$th("Course", style = "min-width: 110px;"),
        tags$th("Title",  style = "min-width: 160px;"),
        tags$th(
          div("Fill", class = "fw-bold"),
          div(paste0("enrolled ÷ (enrolled + avail), wtd by section size"),
              style = "font-weight: 400; font-size: 0.75em; color: #666;"),
          div(paste0("✕ flagged if avg ≥85% or rising ≥1pp/yr"),
              style = "font-weight: 400; font-size: 0.75em; color: #888;"),
          style = "min-width: 110px; text-align: center;"
        ),
        tags$th(
          div("Share", class = "fw-bold"),
          div("health students ÷ total enrolled in course",
              style = "font-weight: 400; font-size: 0.75em; color: #666;"),
          div("✕ flagged if avg ≥30% in recent window",
              style = "font-weight: 400; font-size: 0.75em; color: #888;"),
          style = "min-width: 110px; text-align: center;"
        ),
        tags$th(
          div("Rate ↓", class = "fw-bold"),
          div(paste0("% of program students taking this course per term (",
                     early_label, " vs ", recent_label, ")"),
              style = "font-weight: 400; font-size: 0.75em; color: #666;"),
          div("✕ flagged if dropped >15pp early → recent",
              style = "font-weight: 400; font-size: 0.75em; color: #888;"),
          style = "min-width: 130px; text-align: center;"
        ),
        tags$th(
          div("Drift", class = "fw-bold"),
          div(paste0("avg credit band at enrollment (",
                     early_label, " vs ", recent_label, ")"),
              style = "font-weight: 400; font-size: 0.75em; color: #666;"),
          div("✕ flagged if shifted ≥0.3 bands right (later)",
              style = "font-weight: 400; font-size: 0.75em; color: #888;"),
          style = "min-width: 130px; text-align: center;"
        ),
        tags$th("Flags", style = "min-width: 60px; text-align: center;")
      )

      body_rows <- purrr::map(seq_len(nrow(pr)), function(i) {
        row <- pr[i, ]

        # Fill signal: show avg fill % + slope direction
        fill_label  <- if (is.na(row$avg_fill)) NA
                       else paste0(round(row$avg_fill * 100), "%")
        fill_detail <- if (!is.na(row$fill_slope) && row$fill_slope >= 0.005)
                         paste0("↑", round(row$fill_slope * 100, 1), "%/yr")
                       else if (!is.na(row$fill_slope) && row$fill_slope <= -0.005)
                         paste0("↓", round(abs(row$fill_slope) * 100, 1), "%/yr")
                       else NULL

        # Health share signal
        share_label  <- if (is.na(row$avg_health_share)) NA
                        else paste0(round(row$avg_health_share * 100), "%")
        share_detail <- if (!is.na(row$avg_health_n))
                          paste0(round(row$avg_health_n), " students")
                        else NULL

        # Take rate signal
        rate_label  <- if (is.na(row$rate_change_pct)) NA
                       else paste0(if (row$rate_change_pct >= 0) "+" else "",
                                   round(row$rate_change_pct * 100), "%")
        rate_detail <- if (!is.na(row$rate_early) && !is.na(row$rate_recent))
                         paste0(round(row$rate_early * 100, 1), "→",
                                round(row$rate_recent * 100, 1), "%")
                       else NULL

        # Band drift signal
        drift_label  <- if (is.na(row$band_drift)) NA
                        else paste0(if (row$band_drift >= 0) "+" else "",
                                    round(row$band_drift, 2), " bands")
        drift_detail <- if (!is.na(row$band_early) && !is.na(row$band_recent))
                          paste0("band ", round(row$band_early, 1),
                                 "→", round(row$band_recent, 1))
                        else NULL

        # Flag count badge: red for 3-4 flags, amber for 2, gray for 0-1
        n_flags <- row$n_flags
        flag_bg <- if (n_flags >= 3) "#dc3545"
                   else if (n_flags == 2) "#fd7e14"
                   else "#adb5bd"
        flag_badge <- tags$td(
          tags$span(n_flags, style = paste0(
            "display: inline-block; width: 24px; height: 24px; line-height: 24px; ",
            "text-align: center; border-radius: 50%; background:", flag_bg, "; ",
            "color: white; font-weight: 700; font-size: 0.82em;"
          )),
          style = "text-align: center; vertical-align: middle;"
        )

        tags$tr(
          tags$td(row$subject_course, style = "font-size: 0.85em; white-space: nowrap;"),
          tags$td(coalesce(row$course_title, ""),
                  style = "font-size: 0.82em; color: #555;"),
          flag_cell(row$flag_fill,       fill_label,  fill_detail),
          flag_cell(row$flag_share,      share_label, share_detail),
          flag_cell(row$flag_rate_drop,  rate_label,  rate_detail),
          flag_cell(row$flag_band_drift, drift_label, drift_detail),
          flag_badge
        )
      })

      tagList(
        audit_div,
        div(
          style = "overflow-x: auto;",
          tags$table(
            class = "table table-sm table-bordered",
            style = "font-size: 0.88em;",
            tags$thead(header_row),
            do.call(tags$tbody, body_rows)
          )
        )
      )
    })

    # ── Enrollment matrix ────────────────────────────────────────────────────
    # Update year-range slider bounds once data is available
    observe({
      falls <- programs %>%
        pull(term) %>%
        unique() %>%
        keep(~ grepl("80$", as.character(.x))) %>%
        sort()
      years <- as.integer(substr(as.character(falls), 1, 4))
      if (length(years) == 0) return()
      updateSliderInput(session, "hwi_matrix_year_range",
                        min   = min(years),
                        max   = max(years),
                        value = c(max(min(years), 2023L), max(years)))
    })

    # eventReactive: triggered by the tab's own Run Matrix button.
    # Captures all controls at click time so display stays stable until re-run.
    enroll_matrix_rv <- eventReactive(input$hwi_run_matrix, {
      prog_names <- selected_programs_rv()
      req(length(prog_names) > 0)
      year_range <- input$hwi_matrix_year_range
      req(!is.null(year_range), length(year_range) == 2)
      season <- input$hwi_matrix_season %||% "fall"

      tryCatch(
        get_enrollment_matrix(
          programs       = programs,
          students       = students,
          program_names  = prog_names,
          season         = season,
          year_range     = year_range,
          undergrad_only = isTRUE(input$hwi_matrix_undergrad),
          min_students   = max(1L, as.integer(input$hwi_matrix_min_n %||% 5L))
        ),
        error = function(e) {
          message("[health-whatif module] Enrollment matrix failed: ", e$message)
          NULL
        }
      )
    })

    output$hwi_enroll_matrix_ui <- renderUI({
      result <- enroll_matrix_rv()
      req(!is.null(result))
      mat <- result$matrix
      req(nrow(mat) > 0)

      season_label <- if (result$season == "fall") "Fall" else "Spring"
      yr_label     <- paste0(result$year_range[1], "–", result$year_range[2])
      term_labels  <- paste(season_label,
                            sort(as.integer(substr(as.character(result$selected_terms), 1, 4))))

      audit_div <- div(
        style = "font-size: 0.82em; color: #555; background: #F6F4F0;
                 border-left: 3px solid #C8BFB0; padding: 10px 14px;
                 margin-bottom: 14px; line-height: 1.8;",
        tags$strong("Programs: "), paste(result$program_names, collapse = ", "), tags$br(),
        tags$strong("Season: "), season_label, " — years ", yr_label, tags$br(),
        tags$strong("Terms averaged: "), paste(term_labels, collapse = ", "), tags$br(),
        tags$strong("Scope: "),
        if (result$undergrad_only) "Undergraduate students only"
        else "All students (no level filter).",
        tags$br(),
        tags$strong("Min avg students: "), result$min_students,
        " — courses below this average across terms are hidden.", tags$br(),
        tags$strong("Cell value: "),
        "Average number of students from that program group enrolled in that course per term. ",
        "A student enrolled in both Nursing and Dental Hygiene is counted in both columns.", tags$br(),
        tags$strong("Σ Total (row): "),
        "Sum of all column values for that course. Because multi-program students are counted once per program column, ",
        "this total overcounts students enrolled in multiple programs. ",
        "Read it as a demand-units total, not a count of unique students.", tags$br(),
        tags$strong("Column header total: "),
        "Sum of avg students across all rows shown (proxy for program-in-courses demand, not total headcount)."
      )

      premajor_warning <- if (any(grepl("Pre-Maj", result$col_order))) {
        div(
          style = "background: #F4E9D2; border: 1px solid #C7A96B; border-radius: 4px;
                   padding: 8px 14px; margin-bottom: 12px; font-size: 0.82em; color: #664d03;",
          tags$strong("⚠ Pre-Major columns: "),
          "The is_pre_major flag changed computation starting in Fall 2025. ",
          "Pre-Maj columns are most reliable for year ranges ending before Fall 2025. ",
          "Treat Post-2025 Pre-Maj values with caution."
        )
      } else NULL

      tagList(audit_div, premajor_warning)
    })

    # Enrollment matrix table — rendered separately as a DT for performance.
    # Building the matrix as HTML row-by-row is too slow for 400+ courses × 20 columns.
    output$hwi_enroll_matrix_dt <- DT::renderDT({
      result <- enroll_matrix_rv()
      req(!is.null(result))
      mat       <- result$matrix
      col_order <- result$col_order
      req(nrow(mat) > 0)

      # Build display data frame.
      # Replace values < 0.05 with NA so DT renders them as "—" via JS.
      sigma_total <- "Σ Total"
      display_mat <- mat %>%
        select(Course = subject_course, Title = course_title,
               all_of(col_order), row_total) %>%
        rename(!!sigma_total := row_total) %>%
        mutate(across(all_of(col_order), ~ if_else(. < 0.05, NA_real_, .)))

      # Custom header: program column names + avg total in subheading
      header_ths <- purrr::map(col_order, function(cn) {
        tot <- result$col_totals %>% filter(col_name == cn) %>% pull(col_total)
        tot_str <- if (length(tot) > 0 && !is.na(tot[1])) {
          paste0("<br><span style='font-weight:400;font-size:0.80em;color:#888'>(avg ",
                 round(tot[1]), ")</span>")
        } else ""
        htmltools::tags$th(htmltools::HTML(paste0(cn, tot_str)))
      })

      container <- htmltools::withTags(table(
        class = "display",
        thead(do.call(tr, c(
          list(th("Course"), th("Title")),
          header_ths,
          list(th("Σ Total"))
        )))
      ))

      # Column indices for Pre-Maj (1-indexed in DT = offset by Course + Title = 2)
      premaj_col_indices <- which(grepl("Pre-Maj$", col_order)) + 2L

      num_cols <- c(col_order, sigma_total)

      dt <- DT::datatable(
        display_mat,
        container  = container,
        rownames   = FALSE,
        escape     = FALSE,
        options    = list(
          scrollX    = TRUE,
          pageLength = 50,
          dom        = "tip",
          # Show "—" for NA values in display (does not affect sort/filter)
          columnDefs = list(list(
            targets = "_all",
            render  = DT::JS(
              "function(data, type, row, meta) {",
              "  if (type === 'display' && (data === null || data === 'NA')) return '—';",
              "  return data;",
              "}"
            )
          ))
        )
      ) %>%
        DT::formatRound(columns = num_cols, digits = 1) %>%
        DT::formatStyle(columns = "Course",
                        fontFamily = "monospace", fontSize = "0.85em") %>%
        DT::formatStyle(columns = sigma_total,
                        fontWeight = "600", backgroundColor = "#f0f4f8")

      if (length(premaj_col_indices) > 0) {
        dt <- dt %>%
          DT::formatStyle(columns = premaj_col_indices, backgroundColor = "#fafafa")
      }

      dt
    })

    # ── Export ───────────────────────────────────────────────────────────────
    output$hwi_export <- downloadHandler(
      filename = function() {
        paste0("health-whatif-",
               substr(as.character(input$hwi_start_term), 1, 4), "-",
               input$hwi_delta_pct, "pct-",
               format(Sys.Date(), "%Y%m%d"), ".csv")
      },
      content = function(file) {
        proj <- proj_rv()
        req(!is.null(proj))
        # Export the long-format table — easier to use than the wide matrix
        export_df <- proj$matrix_long %>%
          select(subject_course, course_title, subject_code,
                 term_label, calendar_term,
                 delta_students, sections_fraction, needs_flag,
                 avg_section_size) %>%
          mutate(across(where(is.numeric), ~ round(.x, 3)))
        write.csv(export_df, file, row.names = FALSE)
      }
    )

  }) # end moduleServer
}
