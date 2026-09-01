regstatsUI <- function(id, sections, thresholds, dept_choices, default_term = NULL) {
  ns <- NS(id)

  tagList(
    filter_bar(
      "Registration Statistics",
      cedar_definition_summary("regstats"),
      fluidRow(
        column(2,
          selectInput(ns("rs_campus"), "Campus", multiple = TRUE,
            choices  = sort(unique(sections$campus)),
            selected = cedar_campus_default(sections))
        ),
        column(2,
          selectInput(ns("rs_college"), "College", multiple = TRUE,
            choices = sort(unique(sections$college)))
        ),
        column(2,
          selectInput(ns("rs_term"), "Term", multiple = TRUE,
            choices  = sort(unique(c(sections$term_type, sections$term)), decreasing = TRUE),
            selected = if (!is.null(default_term)) as.character(default_term) else NULL)
        ),
        column(2,
          selectInput(ns("rs_pt"), "Part of Term", multiple = TRUE,
            choices = sort(unique(sections$part_term)))
        ),
        column(2,
          selectizeInput(ns("rs_dept"), "Department", multiple = TRUE,
            choices = dept_choices)
        ),
        column(2,
          selectInput(ns("rs_level"), "Level", multiple = TRUE,
            choices  = sort(unique(sections$level)),
            selected = "lower")
        ),
      ),
      fluidRow(
        column(2,
          numericInput(ns("rs_min_impacted"), "Min Impacted",
            value = thresholds[["min_impacted"]])
        ),
        column(2,
          numericInput(ns("rs_pct_sd"), "Min SDs",
            value = thresholds[["pct_sd"]])
        ),
        column(2,
          numericInput(ns("rs_chronic_fill_rate"), "Chronic Fill Rate",
            value = thresholds[["chronic_fill_rate"]], min = 0, max = 1, step = 0.05)
        ),
        column(2,
          numericInput(ns("rs_min_wait"), "Min Waiting",
            value = thresholds[["min_wait"]])
        ),
        column(2,
          numericInput(ns("rs_min_sat_terms"), "Min Terms at Cap",
            value = thresholds[["min_sat_terms"]], min = 1, step = 1)
        ),
        column(2,
          filter_actions(
            actionButton(ns("rs_dashboard_button"), "Get Stats",
              class = "btn-primary", icon = icon("tachometer-alt")),
            actionButton(ns("rs_copy_url"), label = NULL, icon = icon("link"),
              title = "Copy shareable link for current view",
              class = "btn-outline-secondary btn-sm")
          )
        ),
      ),
      filter_scope_stripe(uiOutput(ns("rs_filter_summary")))
    ),

    cedar_loading_overlay(id, "rs_dashboard_button", emoji = "\U0001f332",
      report_type = "regstats_dashboard", fresh_default = 30, cached_default = 2,
      uiOutput(ns("rs_dashboard"))
    )
  )
}


regstatsServer <- function(id, students, sections, course_flows, data_summary, thresholds) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ── Helpers ────────────────────────────────────────────────────────────────

    tier_badge <- function(value) {
      cfg <- switch(value,
        critical_high   = list(bg = "#F2E3DE", col = "#7A2A1C", lbl = "Critical ↑"),
        critical_low    = list(bg = "#F2E3DE", col = "#7A2A1C", lbl = "Critical ↓"),
        moderate_high   = list(bg = "#F4E9D2", col = "#7A5010", lbl = "Moderate ↑"),
        moderate_low    = list(bg = "#F4E9D2", col = "#7A5010", lbl = "Moderate ↓"),
        marginally_high = list(bg = "#FFF8EE", col = "#8B6020", lbl = "Marginal ↑"),
        marginally_low  = list(bg = "#FFF8EE", col = "#8B6020", lbl = "Marginal ↓"),
        normal          = list(bg = "#E4EEE7", col = "#2D4336", lbl = "Normal"),
        list(bg = "#f0f0f0", col = "#555", lbl = value)
      )
      htmltools::div(
        style = paste0(
          "display:inline-block;padding:2px 8px;border-radius:10px;",
          "font-size:0.75rem;font-weight:600;white-space:nowrap;",
          "background:", cfg$bg, ";color:", cfg$col
        ),
        cfg$lbl
      )
    }

    fill_bar <- function(value) {
      if (is.na(value)) return("")
      pct  <- round(value * 100)
      col  <- if (value >= 0.90) "#A15D4E" else if (value >= 0.75) "#C7A96B" else "#6F8B78"
      htmltools::div(
        style = "display:flex;align-items:center;gap:6px",
        htmltools::div(
          style = "flex:0 0 56px;background:#e0dbd2;border-radius:3px;overflow:hidden",
          htmltools::div(style = paste0("width:", pct, "%;height:8px;background:", col, ";border-radius:3px"))
        ),
        htmltools::span(style = "font-size:0.82rem;color:#666", paste0(pct, "%"))
      )
    }

    sd_style <- function(value) {
      if (is.na(value)) return(list())
      av <- abs(value)
      bg <- if (av >= 1.5) "#F2E3DE" else if (av >= 1.0) "#F4E9D2" else if (av >= 0.5) "#FFF8EE" else "#ffffff"
      list(background = bg, fontWeight = if (av >= 1.0) "600" else "normal")
    }

    # make_sparkline() and trend_cell_html() (with trend_slope/fmt_slope) now live in
    # modules/ui-helpers.R so the waitlists course overview can render the same
    # enrollment sparkline. They're sourced before this module and used unchanged
    # by create_regstats_reactable(), the snapshot cards, and the saturation table.

    create_regstats_reactable <- function(table_data) {
      if (is.null(table_data) || nrow(table_data) == 0) return(NULL)
      table_data <- dplyr::ungroup(table_data)

      # Trend sparkline of the flagged metric across the course's same-term-type history
      # (the report attaches trend_hist / trend_terms). Precompute the HTML via the shared
      # trend_cell_html (pct = FALSE → counts), then drop the list-columns before reactable.
      if (all(c("trend_hist", "trend_terms") %in% names(table_data))) {
        mean_col <- intersect(c("dr_early_mean", "dr_late_mean", "census_enrl_mean"), names(table_data))[1]
        table_data$trend <- vapply(seq_len(nrow(table_data)),
          function(i) trend_cell_html(table_data$trend_hist[[i]], table_data$trend_terms[[i]],
                                      table_data$term[i], pct = FALSE,
                                      baseline_mean = table_data[[mean_col]][i],
                                      baseline_n = table_data$n_hist_terms[i]),
          character(1))
        table_data <- dplyr::select(table_data, -dplyr::any_of(c("trend_hist", "trend_terms")))
      }

      # Consistent column order across every regstats table: Term, College, Course,
      # Title lead, then PoT and Tier; Trend then Hist Terms are always last. Remaining
      # columns keep their relative order.
      table_data <- table_data %>%
        dplyr::relocate(dplyr::any_of(c("term", "college", "subject_course", "course_title",
                                        "part_term", "concern_tier"))) %>%
        dplyr::relocate(dplyr::any_of("n_hist_terms"), .after = dplyr::last_col())
      if ("trend" %in% names(table_data))
        table_data <- dplyr::relocate(table_data, dplyr::any_of("trend"),
                                      .before = dplyr::any_of("n_hist_terms"))

      drop_col <- intersect(c("drop_early", "drop_late"), names(table_data))
      mean_col <- intersect(c("dr_early_mean", "dr_late_mean"), names(table_data))

      col_defs <- list(
        concern_tier   = reactable::colDef(name = "Tier",       width = 105, cell = tier_badge),
        subject_course = reactable::colDef(name = "Course",     minWidth = 90,
          cell = function(v) htmltools::span(class = "fw-semibold", v)),
        course_title   = reactable::colDef(name = "Title",      minWidth = 130,
          cell = function(v) if (!is.na(v)) htmltools::span(class = "text-sub", v) else ""),
        part_term      = cedar_pot_coldef(),
        college        = reactable::colDef(name = "College",    maxWidth = 80),
        term           = reactable::colDef(name = "Term",       maxWidth = 75),
        term_type      = reactable::colDef(show = FALSE),
        campus         = reactable::colDef(show = FALSE),
        pop_sd         = reactable::colDef(name = "Hist SD",   maxWidth = 75, align = "right", format = reactable::colFormat(digits = 2)),
        trend          = reactable::colDef(name = "Trend", minWidth = 108, maxWidth = 150,
          align = "left", html = TRUE),
        n_hist_terms   = reactable::colDef(name = "Hist Terms", maxWidth = 85, align = "right"),
        census_enrl      = reactable::colDef(name = "Enrolled",  maxWidth = 80, align = "right"),
        census_enrl_mean = reactable::colDef(name = "Hist Avg",  maxWidth = 80, align = "right", format = reactable::colFormat(digits = 1)),
        drop_denominator = reactable::colDef(name = "Rate N",    maxWidth = 70, align = "right"),
        drop_rate        = reactable::colDef(name = "Drop Rate", maxWidth = 85, align = "right",
          format = reactable::colFormat(percent = TRUE, digits = 1)),
        drop_rate_mean   = reactable::colDef(name = "Rate Hist", maxWidth = 85, align = "right",
          format = reactable::colFormat(percent = TRUE, digits = 1)),
        drop_rate_change_pp = reactable::colDef(name = "Rate Delta", maxWidth = 88,
          align = "right", format = reactable::colFormat(digits = 1, suffix = " pp")),
        rate_hist_terms  = reactable::colDef(name = "Rate Terms", maxWidth = 88, align = "right"),
        sd_deviation    = reactable::colDef(name = "SDs",       maxWidth = 65, align = "right",
          format = reactable::colFormat(digits = 2), style = sd_style),
        impacted        = reactable::colDef(name = "Outside SD",  maxWidth = 100, align = "right",
          format = reactable::colFormat(digits = 1),
          style = function(v) {
            if (is.na(v) || v <= 0) list(color = "#aaa")
            else list(color = "#A15D4E", fontWeight = "600")
          })
      )

      if (length(drop_col) > 0)
        col_defs[[drop_col]] <- reactable::colDef(name = "Drops",      maxWidth = 70, align = "right")
      if (length(mean_col) > 0)
        col_defs[[mean_col]] <- reactable::colDef(name = "Drops Hist", maxWidth = 85, align = "right", format = reactable::colFormat(digits = 1))

      col_defs <- col_defs[intersect(names(col_defs), names(table_data))]

      reactable::reactable(
        table_data,
        theme               = cedar_tbl_theme,
        striped             = TRUE,
        highlight           = TRUE,
        compact             = TRUE,
        defaultPageSize     = 10,
        showPageSizeOptions = TRUE,
        pageSizeOptions     = c(10, 25, 50),
        columns             = col_defs
      )
    }

    build_opt <- function() {
      opt <- list(
        shiny          = TRUE,
        course_campus  = input$rs_campus,
        course_college = input$rs_college,
        dept_code      = input$rs_dept,
        term           = input$rs_term,
        pt             = input$rs_pt,
        level          = input$rs_level,
        thresholds     = list(
          min_impacted      = input$rs_min_impacted,
          min_wait          = input$rs_min_wait,
          pct_sd            = input$rs_pct_sd,
          chronic_fill_rate = input$rs_chronic_fill_rate,
          min_sat_terms     = input$rs_min_sat_terms
        )
      )
      opt
    }

    # ── Reactive state ─────────────────────────────────────────────────────────

    regstats_data   <- reactiveVal(NULL)
    signals_data    <- reactiveVal(NULL)
    rs_selected_tab <- reactiveVal(NULL)

    observeEvent(input$rs_tabs, {
      rs_selected_tab(input$rs_tabs)
    }, ignoreInit = TRUE, ignoreNULL = TRUE)

    # ── Generate dashboard ─────────────────────────────────────────────────────

    rs_run <- cedar_run_trigger(input, session, "rs_dashboard_button", "Regstats")
    observeEvent(rs_run(), {
      opt <- build_opt()

      log_report_generation(session, "regstats_dashboard", list(
        campus     = input$rs_campus,
        college    = input$rs_college,
        dept       = input$rs_dept,
        term       = input$rs_term,
        thresholds = opt$thresholds
      ))

      timer <- start_report_timer("regstats_dashboard", list(
        campus = input$rs_campus, college = input$rs_college, term = input$rs_term
      ))

      tryCatch({
        result       <- get_reg_stats(students, sections, opt)
        cache_info   <- result$cache_info %||% list()
        is_cached    <- isTRUE(cache_info$loaded_from_cache) || isTRUE(cache_info$cached)
        duration_sec <- end_report_timer(timer, cached = is_cached)
        signals_data(NULL)
        regstats_data(list(flagged = result, opt = opt, generated_at = Sys.time(),
                           duration_sec = round(duration_sec, 1)))
        signal_load_complete(session, id, duration_sec = duration_sec, cached = is_cached)
      }, error = function(e) {
        handle_error(e, "regstats_dashboard")
        signal_load_complete(session, id, error = TRUE)
      })
    }, ignoreInit = TRUE)

    # ── Regenerate (bypass cache) ──────────────────────────────────────────────

    observeEvent(input$rs_regenerate, {
      opt <- build_opt()
      opt[["bypass_cache"]] <- TRUE

      regen_start <- Sys.time()
      tryCatch({
        result       <- get_reg_stats(students, sections, opt)
        duration_sec <- round(as.numeric(difftime(Sys.time(), regen_start, units = "secs")), 1)
        signals_data(NULL)
        regstats_data(list(flagged = result, opt = opt, generated_at = Sys.time(),
                           duration_sec = duration_sec))
        signal_load_complete(session, id, duration_sec = duration_sec, cached = FALSE)
      }, error = function(e) {
        handle_error(e, "regstats_regenerate")
        signal_load_complete(session, id, error = TRUE)
      })
    }, ignoreInit = TRUE)

    # ── Load downstream signals on demand ─────────────────────────────────────

    observeEvent(input$rs_load_signals, {
      data <- regstats_data()
      if (is.null(data)) return()

      showNotification("Computing downstream concerns...",
        type = "message", duration = NULL, id = "signals_loading")

      tryCatch({
        campus_filter <- data$opt$course_campus
        signals_result <- get_next_term_signals(data$flagged, students, campus = campus_filter)

        log_data_filter(session, "downstream_campus_filter",
          paste0("[", paste(campus_filter, collapse = ","), "] rows_before=",
                 nrow(signals_result$downstream)))

        if (!is.null(campus_filter) && length(campus_filter) > 0 &&
            !is.null(signals_result$downstream) && nrow(signals_result$downstream) > 0) {
          if ("campus" %in% names(signals_result$downstream)) {
            signals_result$downstream <- signals_result$downstream %>%
              filter(campus %in% campus_filter)
          } else {
            campus_courses <- sections %>%
              filter(campus %in% campus_filter) %>%
              pull(subject_course) %>%
              unique()
            signals_result$downstream <- signals_result$downstream %>%
              filter(dest_course %in% campus_courses)
          }
          log_data_filter(session, "downstream_campus_filter",
            paste0("rows_after=", nrow(signals_result$downstream)))
        }

        signals_data(signals_result)
        removeNotification("signals_loading")
        updateTabsetPanel(session, "rs_tabs", selected = "Downstream Concerns")
      }, error = function(e) {
        removeNotification("signals_loading")
        handle_error(e, "rs_load_signals", "signals_loading")
      })
    }, ignoreInit = TRUE)

    # ── Copy shareable URL ─────────────────────────────────────────────────────

    cedar_copy_url_observer(input, session, "rs_copy_url", spec_title = "Regstats",
      values_fn = function() list(
        campus            = input$rs_campus,
        college           = input$rs_college,
        dept              = input$rs_dept,
        term              = input$rs_term,
        level             = input$rs_level,
        pt                = input$rs_pt,
        min_impacted      = input$rs_min_impacted,
        pct_sd            = input$rs_pct_sd,
        chronic_fill_rate = input$rs_chronic_fill_rate,
        min_wait          = input$rs_min_wait,
        min_sat_terms     = input$rs_min_sat_terms
      ))

    # ── Scope stripe ───────────────────────────────────────────────────────────

    output$rs_filter_summary <- renderUI({
      data    <- regstats_data()
      signals <- signals_data()

      if (is.null(data)) {
        return(div(class = "scope-bar scope-bar--stacked scope-bar-placeholder",
          tags$span("Set filters and click Get Stats to load data.")
        ))
      }

      flagged    <- data$flagged
      thresholds <- if (is.null(data$opt$thresholds)) thresholds else data$opt$thresholds

      bumps_count       <- if ("bumps"       %in% names(flagged)) nrow(flagged$bumps)       else 0
      dips_count        <- if ("dips"        %in% names(flagged)) nrow(flagged$dips)        else 0
      waits_count       <- if ("waits"       %in% names(flagged)) nrow(flagged$waits)       else 0
      sat_count         <- if ("sat"         %in% names(flagged)) nrow(flagged$sat)         else 0
      early_drops_count <- if ("early_drops" %in% names(flagged)) nrow(flagged$early_drops) else 0
      late_drops_count  <- if ("late_drops"  %in% names(flagged)) nrow(flagged$late_drops)  else 0

      scope_campus  <- if (length(data$opt$course_campus)  == 0) "All" else paste(data$opt$course_campus,  collapse = ", ")
      scope_college <- if (length(data$opt$course_college) == 0) "All" else paste(data$opt$course_college, collapse = ", ")
      scope_dept    <- if (length(data$opt$dept_code)      == 0) "All" else paste(data$opt$dept_code,      collapse = ", ")
      scope_term    <- if (length(data$opt$term)           == 0) "All" else paste(data$opt$term,           collapse = ", ")
      scope_level   <- if (length(data$opt$level)          == 0) "All levels" else paste(data$opt$level, collapse = ", ")
      scope_pt      <- if (length(data$opt$pt)             == 0) "All parts" else paste(data$opt$pt, collapse = ", ")

      sections_dates  <- data_summary$sections_term_dates
      data_as_of_date <- if (length(sections_dates) > 0)
        as.Date(max(unlist(sections_dates), na.rm = TRUE)) else Sys.Date()
      age_days  <- as.numeric(Sys.Date() - data_as_of_date)
      age_label <- format(data_as_of_date, "%b %d, %Y")
      age_class <- if (age_days <= 1) "rs-age-fresh" else if (age_days <= 7) "rs-age-warn" else "rs-age-stale"
      calc_label <- if (!is.null(data$duration_sec)) paste0(" · calc ", data$duration_sec, "s") else ""
      cache_info <- flagged$cache_info %||% list()
      cache_label <- if (isTRUE(cache_info$loaded_from_cache) || isTRUE(cache_info$cached)) {
        age <- cache_info$cache_age_hours
        if (!is.null(age)) paste0("cache hit · ", round(age, 1), "h old") else "cache hit"
      } else if (isTRUE(cache_info$using_standard_thresholds %||% TRUE)) {
        "fresh run · cacheable"
      } else {
        "fresh run · custom thresholds"
      }
      baseline <- flagged$baseline_info
      hist_label <- if (!is.null(baseline$n_hist_terms)) {
        paste0(baseline$n_hist_terms, " distinct prior comparison term",
               if (baseline$n_hist_terms != 1) "s" else "")
      } else {
        "historical baseline available in tables"
      }
      baseline_label <- if (!is.null(baseline$scope)) {
        baseline$scope
      } else {
        "strictly earlier same-season/part-of-term means and population SD"
      }

      div(class = "scope-bar scope-bar--stacked",
        div(class = "rs-stripe-row",
          tags$span(class = "rs-stripe-label", "Scope:"),
          tags$span(scope_campus,  class = "rs-stripe-val"),
          tags$span("·", class = "rs-stripe-sep"),
          tags$span(scope_college, class = "rs-stripe-val"),
          tags$span("·", class = "rs-stripe-sep"),
          tags$span(scope_dept,    class = "rs-stripe-val"),
          tags$span("·", class = "rs-stripe-sep"),
          tags$span(scope_term,    class = "rs-stripe-val"),
          tags$span("·", class = "rs-stripe-sep"),
          tags$span(scope_level,   class = "rs-stripe-val"),
          tags$span("·", class = "rs-stripe-sep"),
          tags$span(scope_pt,      class = "rs-stripe-val"),
          tags$span(class = paste("rs-data-age rs-stripe-right", age_class),
            paste0("Data as of ", age_label, calc_label))
        ),
        div(class = "rs-stripe-row",
          tags$span(class = "rs-stripe-label", "Thresholds:"),
          tags$span(
            paste0("min impacted · ", thresholds$min_impacted,
                   "  —  min SDs · ", thresholds$pct_sd,
                   "  —  chronic fill · ", thresholds$chronic_fill_rate,
                   "  —  min terms at cap · ", thresholds$min_sat_terms,
                   "  —  min wait · ", thresholds$min_wait),
            class = "rs-stripe-thresholds"),
          div(class = "rs-stripe-counts rs-stripe-right",
            tags$span(class = "rs-count-item rs-count-bump",    tags$strong(bumps_count),       " bumps"),
            tags$span("·", class = "rs-stripe-sep"),
            tags$span(class = "rs-count-item rs-count-dip",    tags$strong(dips_count),        " dips"),
            tags$span("·", class = "rs-stripe-sep"),
            tags$span(class = "rs-count-item rs-count-wait",   tags$strong(waits_count),       " waitlists"),
            tags$span("·", class = "rs-stripe-sep"),
            tags$span(class = "rs-count-item rs-count-squeeze",tags$strong(sat_count),         " saturation"),
            tags$span("·", class = "rs-stripe-sep"),
            tags$span(class = "rs-count-item rs-count-drop",   tags$strong(early_drops_count), " early drops"),
            tags$span("·", class = "rs-stripe-sep"),
            tags$span(class = "rs-count-item rs-count-drop",   tags$strong(late_drops_count),  " late drops")
          )
        ),
        div(class = "rs-stripe-row",
          tags$span(class = "rs-stripe-label", "Method:"),
          tags$span(paste0(hist_label, " · ", baseline_label, " · ", cache_label),
            class = "rs-stripe-thresholds")
        ),
        div(class = "rs-stripe-row", tags$span(baseline$coverage_note, class = "rs-stripe-thresholds"))
      )
    })

    # ── Main dashboard UI ──────────────────────────────────────────────────────

    output$rs_dashboard <- renderUI({
      data    <- regstats_data()
      signals <- signals_data()
      cedar_debug("[regstats] rs_dashboard renderUI called. Data is null: ", is.null(data))

      if (is.null(data)) {
        return(div(
          class = "alert alert-info m-4",
          icon("chart-line"), " ",
          "Set your filters and click ", tags$strong("Get Stats"),
          " to view registration anomalies for the selected term.",
          tags$br(), tags$br(),
          tags$small(
            "Registration statistics flag courses with unusual enrollment bumps, high waitlists,
             near-capacity squeezes, or unusual drop counts — compared against each course's own
             historical pattern. Use this to identify where demand is outpacing supply before
             the end of registration."
          )
        ))
      }

      cedar_debug("[regstats] Rendering dashboard with data. Names: ", paste(names(data), collapse = ", "))
      flagged <- data$flagged

      bumps_count       <- if ("bumps"       %in% names(flagged)) nrow(flagged$bumps)       else 0
      dips_count        <- if ("dips"        %in% names(flagged)) nrow(flagged$dips)        else 0
      waits_count       <- if ("waits"       %in% names(flagged)) nrow(flagged$waits)       else 0
      sat_count         <- if ("sat"         %in% names(flagged)) nrow(flagged$sat)         else 0
      early_drops_count <- if ("early_drops" %in% names(flagged)) nrow(flagged$early_drops) else 0
      late_drops_count  <- if ("late_drops"  %in% names(flagged)) nrow(flagged$late_drops)  else 0

      downstream_df <- filter_downstream_by_dept(
        if (!is.null(signals$downstream)) signals$downstream else tibble(),
        data$opt$dept_code,
        sections
      )
      downstream_count      <- nrow(downstream_df)
      downstream_scope_note <- if (length(data$opt$dept_code) > 0)
        paste0("Showing destinations within ", paste(data$opt$dept_code, collapse = ", "),
               ". Run without a dept filter to see all.")
      else
        "Showing all destination courses. Select a dept to narrow to a specific unit."

      # Chronic fill ceiling actually used by this run (drives current-term flag AND
      # the "Terms at Cap" historical count); shown in the saturation help text.
      chronic_fill_pct <- {
        cfr <- data$opt$thresholds$chronic_fill_rate
        if (is.null(cfr)) 90 else round(cfr * 100)
      }
      # Min prior near-full terms required for a chronic flag (the "Min Terms at Cap" input).
      min_cap_terms <- data$opt$thresholds$min_sat_terms %||% 3

      snap_ui <- local({
        s <- data$flagged$summary
        if (is.null(s)) return(NULL)

        term_lbl <- paste(sapply(s$target_terms, fmt_term), collapse = ", ")
        hist_lbl <- paste0(term_lbl, " · anomaly baselines use ",
                           s$n_hist_terms, " distinct prior matching term",
                           if (s$n_hist_terms != 1) "s" else "")
        scope_note <- s$snapshot_scope_note %||%
          "Overview cards count active section rows and distinct courses in the current term."

        snap_card <- function(...) div(class = "rs-snap-card", ...)

        trend   <- s$trend_by_term
        cur_idx <- if (!is.null(trend))
          which(trend$term == as.character(s$target_terms[1]))
        else NULL
        cur_idx <- if (length(cur_idx) == 1L) cur_idx else NULL

        make_level_row <- function(label, lv) {
          if (is.null(lv)) return(NULL)
          ch_ok <- !is.null(lv$total_credit_hours) && !is.na(lv$total_credit_hours) &&
                   lv$total_credit_hours > 0L
          div(class = "rs-snap-level-row",
            div(class = "rs-snap-level-label", label),
            snap_card(
              div(class = "rs-snap-val", lv$n_sections),
              div(class = "rs-snap-lbl", "sections"),
              div(class = "text-note",
                tags$strong(lv$n_courses), " courses")
            ),
            snap_card(
              div(style = "display:flex; align-items:center;",
                div(class = "rs-snap-val", format(lv$total_enrolled, big.mark = ",")),
                if (!is.null(trend)) make_sparkline(trend$total_enrolled, cur_idx) else NULL
              ),
              div(class = "rs-snap-lbl", "registrations")
            ),
            snap_card(
              div(style = "display:flex; align-items:center;",
                div(class = "rs-snap-val", lv$avg_size),
                if (!is.null(trend)) make_sparkline(trend$avg_size, cur_idx) else NULL
              ),
              div(class = "rs-snap-lbl", "avg section size")
            ),
            if (ch_ok)
              snap_card(
                div(style = "display:flex; align-items:center;",
                  div(class = "rs-snap-val", format(lv$total_credit_hours, big.mark = ",")),
                  if (!is.null(trend) && "total_credit_hours" %in% names(trend))
                    make_sparkline(trend$total_credit_hours, cur_idx) else NULL
                ),
                div(class = "rs-snap-lbl", "credit hours")
              )
          )
        }

        div(class = "rs-snapshot",
          tags$p(class = "rs-snap-scope", hist_lbl),
          tags$p(class = "rs-snap-scope", scope_note),
          make_level_row("Lower", s$lower),
          make_level_row("Upper", s$upper)
        )
      })

      tagList(
        snap_ui,
        fluidRow(
          column(12,
            tabsetPanel(
              id = ns("rs_tabs"),
              selected = isolate(rs_selected_tab()),

              tabPanel("Enrollment Bumps",
                cedar_definition_panel(c("census-enrollment", "regstats"), "About enrollment bumps"),
                if (bumps_count > 0) reactable::reactableOutput(ns("rs_bumps_table"))
                else div(class = "alert alert-info mt-2",
                  icon("circle-check"), " No enrollment bumps found with the current filters and thresholds.")
              ),

              tabPanel("Enrollment Dips",
                cedar_definition_panel(c("census-enrollment", "regstats"), "About enrollment dips"),
                if (dips_count > 0) reactable::reactableOutput(ns("rs_dips_table"))
                else div(class = "alert alert-info mt-2",
                  icon("circle-check"), " No enrollment dips found with the current filters and thresholds.")
              ),

              tabPanel("High Waitlists",
                tags$p("Class-list true demand at or above Min Waiting. The linked Waitlists view uses the same student exclusion and reporting grain."),
                cedar_definition_panel(c("waitlist"), "About high waitlists"),
                if (waits_count > 0) reactable::reactableOutput(ns("rs_waits_table"))
                else div(class = "alert alert-info mt-2",
                  icon("circle-check"), " No high waitlist courses found with the current filters.")
              ),

              tabPanel("Saturation",
                info_panel("About saturation",
                  tags$p(sprintf(
                    "Fill uses the class-list census proxy (registered plus late drops) over DESR scheduled capacity. Full now uses the selected %s%% threshold. Chronically full requires %s comparison terms at that threshold, even if the course is not full now. Running hot marks fill above its comparison pattern.",
                    chronic_fill_pct, min_cap_terms
                  )),
                  cedar_definition_note("regstats"),
                  cedar_docs_link("users/regstats#saturation")
                ),
                if (sat_count > 0) reactable::reactableOutput(ns("rs_sat_table"))
                else div(class = "alert alert-info mt-2",
                  icon("circle-check"), " No saturation found with the current filters.")
              ),

              tabPanel("Early Drops",
                tags$p("Early-drop counts (DR/DD) decide which rows appear. Drop Rate divides that count by the class-list first-day proxy so enrollment growth can be interpreted separately; these are not DFW outcomes."),
                cedar_definition_panel(c("regstats"), "About early drops"),
                if (early_drops_count > 0) reactable::reactableOutput(ns("rs_early_drops_table"))
                else div(class = "alert alert-info mt-2",
                  icon("circle-check"), " No early drop anomalies found with the current filters.")
              ),

              tabPanel("Late Drops",
                tags$p("Late-drop counts (DG/DW) decide which rows appear. Drop Rate divides that count by reconstructed census enrollment so enrollment growth can be interpreted separately."),
                cedar_definition_panel(c("regstats"), "About late drops"),
                if (late_drops_count > 0) reactable::reactableOutput(ns("rs_late_drops_table"))
                else div(class = "alert alert-info mt-2",
                  icon("circle-check"), " No late drop anomalies found with the current filters.")
              ),

              tabPanel("Downstream Concerns",
                info_panel("About downstream concerns",
                  tags$ul(
                    tags$li("Courses expected to see extra demand next term, based on historical enrollment flow patterns."),
                    tags$li(tags$strong("Bump"), " — destination course commonly taken after a bump course. ",
                            tags$strong("Drop"), " — course has unusually high drops, suggesting students may re-enroll."),
                    tags$li("Most meaningful without a department filter. With one selected, only destination courses within that department are shown.")
                  ),
                  cedar_docs_link("users/regstats#downstream-concerns")
                ),
                if (is.null(signals)) {
                  div(class = "my-4",
                    tags$p(class = "text-muted-sm",
                      "Downstream analysis requires scanning the full enrollment history and may take 30+ seconds."),
                    actionButton(ns("rs_load_signals"), "Load Downstream Concerns",
                      class = "btn-primary", icon = icon("arrow-right"))
                  )
                } else if (downstream_count > 0) {
                  tagList(
                    tags$p(class = "text-muted-sm", downstream_scope_note),
                    reactable::reactableOutput(ns("rs_signals_downstream_table"))
                  )
                } else {
                  empty_state("No downstream concerns found for the current scope.")
                }
              )
            )
          )
        )
      )
    })

    # ── Data tables ────────────────────────────────────────────────────────────

    output$rs_bumps_table <- reactable::renderReactable({
      data <- regstats_data()
      if (!is.null(data) && "bumps" %in% names(data$flagged))
        create_regstats_reactable(data$flagged$bumps)
    })

    output$rs_dips_table <- reactable::renderReactable({
      data <- regstats_data()
      if (!is.null(data) && "dips" %in% names(data$flagged))
        create_regstats_reactable(data$flagged$dips)
    })

    output$rs_early_drops_table <- reactable::renderReactable({
      data <- regstats_data()
      if (!is.null(data) && "early_drops" %in% names(data$flagged))
        create_regstats_reactable(data$flagged$early_drops)
    })

    output$rs_late_drops_table <- reactable::renderReactable({
      data <- regstats_data()
      if (!is.null(data) && "late_drops" %in% names(data$flagged))
        create_regstats_reactable(data$flagged$late_drops)
    })

    output$rs_waits_table <- reactable::renderReactable({
      data <- regstats_data()
      if (is.null(data) || !"waits" %in% names(data$flagged)) return(NULL)
      df <- data$flagged$waits %>%
        dplyr::ungroup() %>%   # else select() below re-adds grouping vars (campus)
        mutate(waiting_link = ifelse(
          waiting > 0,
          sprintf(
            '<a href="javascript:void(0)" onclick="Shiny.setInputValue(\'waitlist-wl_navigate\',{course:\'%s\',term:\'%s\'},{priority:\'event\'})">%d</a>',
            htmltools::htmlEscape(subject_course),
            htmltools::htmlEscape(as.character(term)),
            waiting
          ),
          as.character(waiting)
        )) %>%
        dplyr::select(-waiting) %>%
        dplyr::rename(waiting = waiting_link) %>%
        # Explicit display columns in the shared lead order (Term · College · Course ·
        # Title · PoT · …). Drops get_enrl's leaked extras (sections, xl_sections,
        # reg_sections, avg_size, total_enrl, enrolled, avail) so only the waitlist view
        # shows, matching the other regstats tables.
        dplyr::select(dplyr::any_of(c("term", "campus", "college", "subject_course", "course_title",
                                      "part_term", "gen_ed_area", "waiting")))
      reactable::reactable(
        df,
        theme               = cedar_tbl_theme,
        striped             = TRUE,
        highlight           = TRUE,
        compact             = TRUE,
        defaultPageSize     = 10,
        showPageSizeOptions = TRUE,
        pageSizeOptions     = c(10, 25, 50),
        columns = local({
          defs <- list(
            campus         = reactable::colDef(name = "Campus", maxWidth = 80),
            subject_course = reactable::colDef(name = "Course",   minWidth = 90,
              cell = function(v) htmltools::span(class = "fw-semibold", v)),
            course_title   = reactable::colDef(name = "Title",    minWidth = 130,
              cell = function(v) if (!is.na(v)) htmltools::span(class = "text-sub", v) else ""),
            college        = reactable::colDef(name = "College",  maxWidth = 80),
            part_term      = cedar_pot_coldef(),
            term           = reactable::colDef(name = "Term",     maxWidth = 75),
            gen_ed_area    = reactable::colDef(name = "Gen Ed",   maxWidth = 90),
            waiting        = reactable::colDef(name = "Waiting",  maxWidth = 80,
              align = "right", html = TRUE)
          )
          defs[intersect(names(defs), names(df))]
        })
      )
    })

    output$rs_sat_table <- reactable::renderReactable({
      data <- regstats_data()
      if (is.null(data) || !"sat" %in% names(data$flagged)) return(NULL)
      df <- data$flagged$sat
      # Precompute the Fill Trend sparkline HTML from the per-course history list-columns
      # (attached in the report) via the shared trend_cell_html (pct = TRUE → census fill
      # rate), then let the display-order select drop the list-columns so they never reach
      # reactable's JSON serializer.
      df$fill_trend <- if (all(c("fill_hist", "fill_hist_terms") %in% names(df)))
        vapply(seq_len(nrow(df)),
               function(i) trend_cell_html(df$fill_hist[[i]], df$fill_hist_terms[[i]], df$term[i], pct = TRUE,
                                           baseline_mean = df$fill_rate_mean[i], baseline_n = df$n_hist_terms[i]),
               character(1))
      else rep("", nrow(df))

      # Status badges from the report's saturation flags. A course can be full right now,
      # chronically full (historically, even if soft this term), and/or running hot — shown
      # together so each row's saturation type is obvious at a glance. These are visual
      # tags; sort by Term Fill for "full now" and Hist Fill for "historically full".
      sat_badge <- function(txt, bg, fg) paste0(
        "<span style=\"display:inline-block;font-size:0.68rem;font-weight:600;line-height:1.5;",
        "border-radius:8px;padding:0 6px;margin:1px 3px 1px 0;white-space:nowrap;background:",
        bg, ";color:", fg, "\">", txt, "</span>")
      flag_col <- function(nm) if (nm %in% names(df)) as.logical(df[[nm]]) else rep(FALSE, nrow(df))
      .full_now <- flag_col("is_full_now")
      .chr_hist <- flag_col("is_chronic_hist")
      .running_hot <- flag_col("is_running_hot")
      df$status <- vapply(seq_len(nrow(df)), function(i) {
        b <- character(0)
        if (isTRUE(.full_now[i])) b <- c(b, sat_badge("Full now", "#F2E3DE", "#A15D4E"))
        if (isTRUE(.chr_hist[i])) b <- c(b, sat_badge("Chronically full", "#F4E9D2", "#7A5010"))
        if (isTRUE(.running_hot[i])) b <- c(b, sat_badge("Running hot", "#E3ECF2", "#3A5A7A"))
        paste(b, collapse = "")
      }, character(1))

      # Select only what the table shows, in display order (Term · College · Course ·
      # Title · Status lead, Hist Terms last). Three fill columns: Term Fill (current
      # term), Hist Fill (historic mean), and Fill Trend (the historic series). The DESR
      # snapshot fill and late-drop count are kept for the Term Fill tooltip/chip.
      # Everything else get_enrl or the history join leaked (xl_sections, reg_sections,
      # avg_size, total_enrl, waiting, avail, campus, the is_* flag + fill_hist columns)
      # is dropped here.
      display_order <- c(
        "term", "college", "subject_course", "course_title", "part_term", "status",
        "census_enrl", "capacity", "sections",
        "fill_rate", "fill_rate_mean", "fill_trend", "sd_above_mean", "n_chronic_terms", "n_hist_terms",
        "enrolled", "desr_snapshot_fill", "dr_late"
      )
      df <- df[, intersect(display_order, names(df)), drop = FALSE]

      sat_col_defs <- list(
        enrolled        = reactable::colDef(show = FALSE),
        desr_snapshot_fill = reactable::colDef(show = FALSE),
        dr_late         = reactable::colDef(show = FALSE),
        subject_course  = reactable::colDef(name = "Course", minWidth = 82,
          cell = function(v) htmltools::span(class = "fw-semibold", v)),
        course_title    = reactable::colDef(name = "Title", minWidth = 150,
          cell = function(v) if (!is.na(v)) htmltools::span(class = "text-sub", v) else ""),
        college         = reactable::colDef(name = "College", maxWidth = 64, align = "center"),
        part_term       = cedar_pot_coldef(),
        term            = reactable::colDef(name = "Term", maxWidth = 64, align = "center"),
        status          = reactable::colDef(name = "Status", minWidth = 132, align = "left",
          html = TRUE, sortable = FALSE),
        census_enrl     = reactable::colDef(name = "Census", maxWidth = 68, align = "right"),
        capacity        = reactable::colDef(name = "Cap", maxWidth = 56, align = "right"),
        sections        = reactable::colDef(name = "Sects", maxWidth = 58, align = "right"),
        # The class-list census proxy is the headline numerator. Hover shows the
        # independently timed DESR snapshot fill; the chip reports late drops
        # included in the class-list census proxy.
        fill_rate       = reactable::colDef(name = "Term Fill", minWidth = 140, maxWidth = 178,
          align = "left",
          cell = function(value, index) {
            if (is.na(value)) return("")
            snapshot <- if ("desr_snapshot_fill" %in% names(df)) df$desr_snapshot_fill[index] else NA_real_
            late <- if ("dr_late" %in% names(df)) df$dr_late[index] else NA_real_
            snapshot_txt <- if (!is.na(snapshot))
              paste0("DESR snapshot fill ", round(snapshot * 100), "%; extract timing can differ")
            else "No DESR snapshot fill"
            htmltools::div(
              title = paste0("Class-list census proxy over DESR capacity. ", snapshot_txt),
              style = "display:flex;align-items:center;gap:6px",
              fill_bar(value),
              if (!is.na(late) && late >= 5)
                htmltools::span(
                  title = paste0(late, " late drops included in the class-list census proxy"),
                  style = paste0("font-size:0.72rem;color:#7A5010;font-weight:600;",
                                 "white-space:nowrap;background:#F4E9D2;border-radius:8px;padding:0 6px"),
                  paste0("▾", late))
              else NULL
            )
          }),
        fill_rate_mean  = reactable::colDef(name = "Hist Fill", minWidth = 96, maxWidth = 120,
          align = "left",
          # Historic mean census fill — "how full is this course usually", independent of
          # this term. Same bar as Term Fill so the two read side by side; sort desc to
          # bring perennially-packed courses to the top even when they're soft right now.
          cell = function(value) if (is.na(value)) "" else fill_bar(value)),
        fill_trend      = reactable::colDef(name = "Fill Trend", minWidth = 108, maxWidth = 150,
          align = "left", html = TRUE),
        sd_above_mean   = reactable::colDef(name = "SDs Hist", maxWidth = 78, align = "right",
          format = reactable::colFormat(digits = 2),
          style = function(v) {
            if (is.na(v)) return(list())
            if (v >= 1.5) list(background = "#F2E3DE", fontWeight = "600")
            else if (v >= 1.0) list(background = "#F4E9D2", fontWeight = "600")
            else if (v >= 0.5) list(background = "#FFF8EE")
            else list()
          }),
        n_chronic_terms = reactable::colDef(name = "Terms at Cap", maxWidth = 92, align = "right",
          style = function(v) {
            if (is.na(v)) return(list())
            if (v >= 5) list(color = "#A15D4E", fontWeight = "700")
            else if (v >= 3) list(color = "#C7A96B", fontWeight = "600")
            else list()
          }),
        n_hist_terms    = reactable::colDef(name = "Hist Terms", maxWidth = 78, align = "right")
      )
      reactable::reactable(
        df,
        theme               = cedar_tbl_theme,
        striped             = TRUE,
        highlight           = TRUE,
        compact             = TRUE,
        defaultPageSize     = 10,
        showPageSizeOptions = TRUE,
        pageSizeOptions     = c(10, 25, 50),
        defaultSorted       = list(fill_rate = "desc"),
        columns             = sat_col_defs[intersect(names(sat_col_defs), names(df))]
      )
    })

    output$rs_signals_downstream_table <- reactable::renderReactable({
      signals <- signals_data()
      data    <- regstats_data()
      df <- filter_downstream_by_dept(signals$downstream, data$opt$dept_code, sections)
      if (is.null(df) || nrow(df) == 0) return(NULL)
      display <- df %>%
        dplyr::rename(`Course` = dest_course, `Reason` = reason, `Top feeders` = top_feeders)
      display_cols <- intersect(c("campus", "Course", "Reason", "Top feeders"), names(display))
      reactable::reactable(
        display %>% dplyr::select(dplyr::all_of(display_cols)),
        theme           = cedar_tbl_theme,
        striped         = TRUE,
        highlight       = TRUE,
        compact         = TRUE,
        defaultPageSize = 25,
        columns = list(
          Course        = reactable::colDef(minWidth = 100,
            cell = function(v) htmltools::span(class = "fw-semibold", v)),
          Reason        = reactable::colDef(minWidth = 80),
          `Top feeders` = reactable::colDef(minWidth = 200)
        )
      )
    })

  })
}
