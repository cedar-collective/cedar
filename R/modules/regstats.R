regstatsUI <- function(id, sections, thresholds, dept_choices, default_term = NULL) {
  ns <- NS(id)

  tagList(
    filter_bar(
      "Registration Statistics",
      "Flags courses where enrollment pressure is concentrated — sections filling faster than usual, growing waitlists, or drop rates above a course's own historical average. All comparisons are term-type matched and use historical-only means.",
      fluidRow(
        column(2,
          selectInput(ns("rs_campus"), "Campus", multiple = TRUE,
            choices  = sort(unique(sections$campus)),
            selected = c("ABQ", "EA"))
        ),
        column(1,
          selectInput(ns("rs_college"), "College", multiple = TRUE,
            choices = sort(unique(sections$college)))
        ),
        column(2,
          selectizeInput(ns("rs_dept"), "Department", multiple = TRUE,
            choices = dept_choices)
        ),
        column(2,
          selectInput(ns("rs_term"), "Term", multiple = TRUE,
            choices  = sort(unique(c(sections$term_type, sections$term)), decreasing = TRUE),
            selected = if (!is.null(default_term)) as.character(default_term) else NULL)
        ),
        column(2,
          selectInput(ns("rs_level"), "Level", multiple = TRUE,
            choices  = sort(unique(sections$level)),
            selected = "lower")
        ),
        column(2,
          selectInput(ns("rs_pt"), "Part of Term", multiple = TRUE,
            choices = sort(unique(sections$part_term)))
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

    div(class = "loader-anchor",

      div(
        id = "regstats-loading-overlay",
        style = "display: none;",
        div(class = "dash-loader-backdrop"),
        div(class = "dash-loader-box",
          div(class = "dash-loader-icon",
            div(class = "dash-spinner"),
            tags$span("\U0001f332", class = "dash-tree-icon")
          ),
          div(id = "regstats-loading-label", class = "dash-loader-msg", "Loading…"),
          div(id = "regstats-timing-msg",    class = "dash-timing-msg")
        )
      ),

      tags$script(HTML(paste0('
      (function() {
        var expectedSec = ', {
          avg <- get_average_report_time("regstats_dashboard")
          if (!is.null(avg)) round(avg) else 15L
        }, ';
        var hideTimer = null;

        $(document).on("shiny:inputchanged", function(e) {
          if (e.name !== "regstats-rs_dashboard_button") return;
          showOverlay();
        });

        Shiny.addCustomMessageHandler("regstats_load_complete", function(msg) {
          completeOverlay(msg.duration_sec, msg.avg_sec);
        });

        function showOverlay() {
          clearTimeout(hideTimer);
          var el    = document.getElementById("regstats-loading-overlay");
          var label = document.getElementById("regstats-loading-label");
          var timing = document.getElementById("regstats-timing-msg");
          if (!el) return;
          label.textContent  = "Loading… (est. " + Math.round(expectedSec) + "s)";
          timing.textContent = "";
          el.style.opacity    = "0";
          el.style.display    = "flex";
          el.style.transition = "opacity 0.2s ease";
          el.offsetWidth;
          el.style.opacity = "1";
        }

        function completeOverlay(durationSec, avgSec) {
          var el     = document.getElementById("regstats-loading-overlay");
          var timing = document.getElementById("regstats-timing-msg");
          if (!el || el.style.display === "none") return;
          var txt = "Loaded in " + durationSec + "s";
          if (avgSec !== null && avgSec !== undefined) txt += " · avg " + avgSec + "s";
          timing.textContent = txt;
          hideTimer = setTimeout(function() {
            el.style.transition = "opacity 0.4s ease";
            el.style.opacity    = "0";
            setTimeout(function() {
              el.style.display    = "none";
              el.style.transition = "";
              el.style.opacity    = "1";
            }, 400);
          }, 800);
        }
      })();
      '))),

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

    make_sparkline <- function(values, current_idx = NULL, width = 80, height = 20,
                               col = "#8BAF99", cur_col = "#3F5E4B") {
      vals <- suppressWarnings(as.numeric(values))
      vals <- vals[!is.na(vals)]
      if (length(vals) < 2) return(htmltools::span())
      n    <- length(vals)
      vmin <- min(vals); vmax <- max(vals)
      if (vmax == vmin) return(htmltools::span())
      pad <- 2
      xs  <- round((seq_len(n) - 1) / (n - 1) * (width - pad * 2) + pad, 1)
      ys  <- round((1 - (vals - vmin) / (vmax - vmin)) * (height - pad * 2) + pad, 1)
      pts <- paste(xs, ys, sep = ",", collapse = " ")
      dot <- if (!is.null(current_idx) && current_idx >= 1 && current_idx <= n)
        paste0('<circle cx="', xs[current_idx], '" cy="', ys[current_idx],
               '" r="2.5" fill="', cur_col, '"/>')
      else ""
      htmltools::HTML(paste0(
        '<svg width="', width, '" height="', height,
        '" style="display:inline-block;vertical-align:middle;margin-left:4px;">',
        '<polyline points="', pts, '" fill="none" stroke="', col,
        '" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"/>',
        dot, '</svg>'
      ))
    }

    # ── Trend cell (shared by the saturation Fill Trend and the anomaly Trend columns) ──
    # Linear (scaled) units-per-term slope; NA when fewer than 3 points.
    trend_slope <- function(v, scale = 1) {
      v <- v[!is.na(v)]
      if (length(v) < 3) return(NA_real_)
      round(unname(stats::coef(stats::lm(I(v * scale) ~ seq_along(v)))[2]), 1)
    }
    fmt_slope <- function(s, unit) if (is.na(s)) "n/a" else
      paste0(if (s >= 0) "+" else "", formatC(s, format = "f", digits = 1), unit)

    # Renders a metric's same-term-type history as a sparkline with the viewed term dotted,
    # a ▲/▼ chip for the trend *heading into* that term, and a tooltip carrying the full-arc
    # trend and historic average. pct = TRUE for rate metrics (fill rate 0–1, shown as
    # points/term); FALSE for counts (enrollment, drops — shown as units/term).
    trend_cell_html <- function(series, terms, cur_term, pct = FALSE) {
      if (is.null(series) || length(series) < 2) return("")
      cur   <- match(cur_term, terms)
      scale <- if (pct) 100 else 1
      unit  <- if (pct) " pts/term" else "/term"
      todot <- if (!is.na(cur)) trend_slope(series[seq_len(cur)], scale) else NA_real_
      arc   <- trend_slope(series, scale)
      avg_v <- if (!is.na(cur) && cur > 1) mean(series[-cur], na.rm = TRUE) else mean(series, na.rm = TRUE)
      avg_t <- if (pct) paste0(round(avg_v * 100), "%") else formatC(avg_v, format = "f", digits = 1)
      spark <- as.character(make_sparkline(series, cur, width = 66, height = 18, cur_col = "#A15D4E"))
      tip   <- paste0("Trend into ", cur_term, ": ", fmt_slope(todot, unit),
                      " · full-arc: ", fmt_slope(arc, unit),
                      " · historic avg ", avg_t, " over ", length(series), " terms")
      chip  <- if (!is.na(todot) && abs(todot) >= 1) {
        up <- todot > 0
        sprintf('<span style="font-size:0.72rem;font-weight:600;margin-left:3px;color:%s">%s%s</span>',
                if (up) "#A15D4E" else "#6F8B78", if (up) "▲" else "▼",
                formatC(abs(todot), format = "f", digits = 1))
      } else ""
      sprintf('<div title="%s" style="display:flex;align-items:center;gap:2px">%s%s</div>',
              htmltools::htmlEscape(tip, attribute = TRUE), spark, chip)
    }

    create_regstats_reactable <- function(table_data) {
      if (is.null(table_data) || nrow(table_data) == 0) return(NULL)
      table_data <- dplyr::ungroup(table_data)

      # Trend sparkline of the flagged metric across the course's same-term-type history
      # (the report attaches trend_hist / trend_terms). Precompute the HTML via the shared
      # trend_cell_html (pct = FALSE → counts), then drop the list-columns before reactable.
      if (all(c("trend_hist", "trend_terms") %in% names(table_data))) {
        table_data$trend <- vapply(seq_len(nrow(table_data)),
          function(i) trend_cell_html(table_data$trend_hist[[i]], table_data$trend_terms[[i]],
                                      table_data$term[i], pct = FALSE),
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
        pop_sd         = reactable::colDef(name = "Hist SD",   maxWidth = 75, align = "right"),
        trend          = reactable::colDef(name = "Trend", minWidth = 108, maxWidth = 150,
          align = "left", html = TRUE),
        n_hist_terms   = reactable::colDef(name = "Hist Terms", maxWidth = 85, align = "right"),
        registered      = reactable::colDef(name = "Enrolled",  maxWidth = 80, align = "right"),
        registered_mean = reactable::colDef(name = "Hist Avg",  maxWidth = 80, align = "right"),
        sd_deviation    = reactable::colDef(name = "SDs",       maxWidth = 65, align = "right",
          style = sd_style),
        impacted        = reactable::colDef(name = "Impacted",  maxWidth = 85, align = "right",
          style = function(v) {
            if (is.na(v) || v <= 0) list(color = "#aaa")
            else list(color = "#A15D4E", fontWeight = "600")
          })
      )

      if (length(drop_col) > 0)
        col_defs[[drop_col]] <- reactable::colDef(name = "Drops",      maxWidth = 70, align = "right")
      if (length(mean_col) > 0)
        col_defs[[mean_col]] <- reactable::colDef(name = "Drops Hist", maxWidth = 85, align = "right")

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
        dept           = input$rs_dept,
        term           = input$rs_term,
        pt             = input$rs_pt,
        level          = input$rs_level,
        thresholds     = list(
          min_impacted      = input$rs_min_impacted,
          min_wait          = input$rs_min_wait,
          pct_sd            = input$rs_pct_sd,
          chronic_fill_rate = input$rs_chronic_fill_rate
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

    observeEvent(input$rs_dashboard_button, {
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
        duration_sec <- end_report_timer(timer)
        signals_data(NULL)
        regstats_data(list(flagged = result, opt = opt, generated_at = Sys.time(),
                           duration_sec = round(duration_sec, 1)))
        avg <- get_average_report_time("regstats_dashboard")
        session$sendCustomMessage("regstats_load_complete", list(
          duration_sec = round(duration_sec, 1),
          avg_sec      = if (!is.null(avg)) round(avg, 1) else NULL
        ))
      }, error = function(e) {
        handle_error(e, "regstats_dashboard")
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
        session$sendCustomMessage("regstats_load_complete", list(
          duration_sec = duration_sec,
          avg_sec      = NULL
        ))
      }, error = function(e) {
        handle_error(e, "regstats_regenerate")
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
        min_wait          = input$rs_min_wait
      ))

    # ── Download report ────────────────────────────────────────────────────────

    output$rs_report_download <- downloadHandler(
      filename = function() {
        paste0("regstats-report-", format(Sys.time(), "%Y%m%d-%H%M%S"), ".html")
      },
      content = function(file) {
        opt <- build_opt()

        status_message <- create_timing_status_message("regstats_report", "Generating regstats")
        showNotification(status_message, type = "message", duration = NULL, id = "regstats_report_loading")

        timer <- start_report_timer("regstats_report", list(
          campus = input$rs_campus, college = input$rs_college, term = input$rs_term
        ))

        tryCatch({
          create_regstat_report(students, sections, opt)
          duration_sec <- end_report_timer(timer)
          report_path <- file.path(getwd(), "www", "output.html")
          if (file.exists(report_path)) {
            file.copy(report_path, file, overwrite = TRUE)
          } else {
            stop("Report file was not generated")
          }
          removeNotification("regstats_report_loading")
          showNotification(paste0("Regstats report downloaded! (", round(duration_sec, 1), "s)"),
            type = "message", duration = 5)
        }, error = function(e) {
          handle_error(e, "regstats_report", "regstats_report_loading")
        })
      }
    )

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
      scope_dept    <- if (length(data$opt$dept)           == 0) "All" else paste(data$opt$dept,           collapse = ", ")
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
      summary <- flagged$summary
      hist_label <- if (!is.null(summary) && !is.null(summary$n_hist_terms)) {
        paste0(summary$n_hist_terms, " prior same-type term",
               if (summary$n_hist_terms != 1) "s" else "")
      } else {
        "historical baseline available in tables"
      }
      baseline_label <- if (!is.null(summary) && !is.null(summary$baseline_scope)) {
        summary$baseline_scope
      } else {
        "exact term runs exclude target term from historical means"
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
            paste0("Data as of ", age_label, calc_label)),
          tags$span("·", class = "rs-stripe-sep"),
          tags$a(
            id = ns("rs_report_download"),
            class = "shiny-download-link rs-download-link",
            href = "", target = "_blank", download = NA,
            icon("download"), " Download Report"
          )
        ),
        div(class = "rs-stripe-row",
          tags$span(class = "rs-stripe-label", "Thresholds:"),
          tags$span(
            paste0("min impacted · ", thresholds$min_impacted,
                   "  —  min SDs · ", thresholds$pct_sd,
                   "  —  chronic fill · ", thresholds$chronic_fill_rate,
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
        )
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
             near-capacity squeezes, or elevated drop rates — compared against each course's own
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
        data$opt$dept,
        sections
      )
      downstream_count      <- nrow(downstream_df)
      downstream_scope_note <- if (length(data$opt$dept) > 0)
        paste0("Showing destinations within ", paste(data$opt$dept, collapse = ", "),
               ". Run without a dept filter to see all.")
      else
        "Showing all destination courses. Select a dept to narrow to a specific unit."

      docs <- "https://cedarplatform.org/users/regstats"

      snap_ui <- local({
        s <- data$flagged$summary
        if (is.null(s)) return(NULL)

        term_lbl <- paste(sapply(s$target_terms, fmt_term), collapse = ", ")
        hist_lbl <- paste0(term_lbl, " · comparisons vs hist avg across ",
                           s$n_hist_terms, " prior same-type term",
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
                info_panel("About enrollment bumps",
                  tags$ul(
                    tags$li("Courses with registration higher than their historical average for the same term type (fall vs. fall, spring vs. spring)."),
                    tags$li("Most actionable when the course is near capacity or when Downstream Concerns shows pressure will persist."),
                    tags$li("Column calculations (", tags$em("registered_mean"), ", ", tags$em("SDs from mean"), ", ", tags$em("impacted"), ") are explained in the docs."),
                    tags$li(tags$strong("Trend"), " sparkline plots this course’s enrollment across its prior same-type offerings, with this term dotted; the ▲/▼ chip is the trend heading into it. Tells a one-term bump from a course on a rising path — hover for the full-arc trend and historic average.")
                  ),
                  tags$a("Full methodology →", href = paste0(docs, "#enrollment-bumps"), target = "_blank")
                ),
                if (bumps_count > 0) reactable::reactableOutput(ns("rs_bumps_table"))
                else div(class = "alert alert-info mt-2",
                  icon("circle-check"), " No enrollment bumps found with the current filters and thresholds.")
              ),

              tabPanel("Enrollment Dips",
                info_panel("About enrollment dips",
                  tags$ul(
                    tags$li("Courses with registration significantly below their historical average for the same term type."),
                    tags$li("May indicate a change in student interest, competing alternatives, scheduling issues, or an instructor/format change that hasn't been widely noticed."),
                    tags$li("Column calculations follow the same pattern as Enrollment Bumps; concern tier reflects severity of the shortfall."),
                    tags$li(tags$strong("Trend"), " sparkline plots this course’s enrollment across its prior same-type offerings, with this term dotted; the ▲/▼ chip is the trend heading into it. Tells a one-term dip from a sustained decline — hover for the full-arc trend and historic average.")
                  ),
                  tags$a("Full methodology →", href = paste0(docs, "#enrollment-dips"), target = "_blank")
                ),
                if (dips_count > 0) reactable::reactableOutput(ns("rs_dips_table"))
                else div(class = "alert alert-info mt-2",
                  icon("circle-check"), " No enrollment dips found with the current filters and thresholds.")
              ),

              tabPanel("High Waitlists",
                info_panel("About high waitlists",
                  tags$ul(
                    tags$li("Courses where the current waitlist count exceeds the Min Waiting threshold."),
                    tags$li("A large waitlist means demand is already outpacing available seats — consider opening an additional section or increasing capacity.")
                  ),
                  tags$a("Full methodology →", href = paste0(docs, "#high-waitlists"), target = "_blank")
                ),
                if (waits_count > 0) reactable::reactableOutput(ns("rs_waits_table"))
                else div(class = "alert alert-info mt-2",
                  icon("circle-check"), " No high waitlist courses found with the current filters.")
              ),

              tabPanel("Saturation",
                info_panel("About saturation",
                  tags$ul(
                    tags$li("Two signals, shown together: ", tags$strong("emerging"), " (a course filling faster than its own history) and ",
                            tags$strong("chronic"), " (near capacity term after term). A course can appear for either or both."),
                    tags$li(tags$strong("Census Fill"), " (the bar) = census headcount ÷ capacity, where census headcount adds late drops back to enrolled. It’s measured the same way for every term, so drops don’t distort comparisons, and it’s what flagging uses. Hover the bar for the ",
                            tags$strong("final"), " end-of-term fill; a ", tags$strong("▾N"), " chip shows how many students a course loses after census (late-drop melt) when that’s 5 or more."),
                    tags$li(tags$strong("Fill Trend"), " = this course’s census fill across its prior offerings of the same term type and part of term (e.g. past falls, full-term only), with the term you’re viewing dotted in context. The ",
                            tags$strong("▲/▼"), " chip is the trend heading ", tags$em("into"), " that term (points per term, matching the dot); hover for the full-arc trend and the historic average."),
                    tags$li(tags$strong("SDs Hist"), " = SDs above the course’s own historical census-fill mean — the emerging signal (blank = no deviation data). ",
                            tags$strong("Terms at Cap"), " = prior same-type terms with census fill ≥ 80% — the chronic signal. Chronic flags need 3+ such terms and a current fill at or above the Chronic Fill Rate control."),
                    tags$li("Sort by ", tags$strong("Terms at Cap"), " to surface entrenched capacity problems; sort by ",
                            tags$strong("SDs Hist"), " to find courses filling faster than their own pattern.")
                  ),
                  tags$a("Full methodology →", href = paste0(docs, "#saturation"), target = "_blank")
                ),
                if (sat_count > 0) reactable::reactableOutput(ns("rs_sat_table"))
                else div(class = "alert alert-info mt-2",
                  icon("circle-check"), " No saturation found with the current filters.")
              ),

              tabPanel("Early Drops",
                info_panel("About early drops",
                  tags$ul(
                    tags$li("Courses with pre-census withdrawal (DR) rates significantly different from their historical average — flagged in both directions."),
                    tags$li("High rates often reflect scheduling conflicts, unclear course descriptions, or prerequisite mismatches. Unusually low rates may signal a change in course format, grading policy, or cohort composition."),
                    tags$li("Concern tier reflects direction: ", tags$em("_high"), " = more drops than usual, ", tags$em("_low"), " = fewer drops than usual."),
                    tags$li(tags$strong("Trend"), " sparkline plots this course’s early-drop count across its prior same-type offerings, with this term dotted; the ▲/▼ chip is the trend heading into it — a one-term spike vs. a worsening pattern. Hover for the full-arc trend and historic average.")
                  ),
                  tags$a("Full methodology →", href = paste0(docs, "#early-drops"), target = "_blank")
                ),
                if (early_drops_count > 0) reactable::reactableOutput(ns("rs_early_drops_table"))
                else div(class = "alert alert-info mt-2",
                  icon("circle-check"), " No early drop anomalies found with the current filters.")
              ),

              tabPanel("Late Drops",
                info_panel("About late drops",
                  tags$ul(
                    tags$li("Courses with post-census withdrawal (DW/DG) rates significantly different from their historical average — flagged in both directions."),
                    tags$li("These appear on transcripts and may affect financial aid — high rates are a stronger signal of course difficulty, pacing, or support gaps than early drops."),
                    tags$li("Concern tier reflects direction: ", tags$em("_high"), " = more drops than usual, ", tags$em("_low"), " = fewer drops than usual."),
                    tags$li(tags$strong("Trend"), " sparkline plots this course’s late-drop count across its prior same-type offerings, with this term dotted; the ▲/▼ chip is the trend heading into it — a one-term spike vs. a worsening pattern. Hover for the full-arc trend and historic average.")
                  ),
                  tags$a("Full methodology →", href = paste0(docs, "#late-drops"), target = "_blank")
                ),
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
                  tags$a("Full methodology →", href = paste0(docs, "#downstream-concerns"), target = "_blank")
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
                  div(class = "empty-state", p("No downstream concerns found for the current scope."))
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
        dplyr::select(dplyr::any_of(c("term", "college", "subject_course", "course_title",
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
            campus         = reactable::colDef(show = FALSE),
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
               function(i) trend_cell_html(df$fill_hist[[i]], df$fill_hist_terms[[i]], df$term[i], pct = TRUE),
               character(1))
      else rep("", nrow(df))

      # Select only what the table shows, in display order (Term · College · Course ·
      # Title lead, Hist Terms last). Two fill columns: Census Fill (current term) and
      # Fill Trend (its historic census-fill series). `enrolled` and `fill_rate_final`
      # are kept but hidden for the Census Fill cell's chip/tooltip. Everything else
      # get_enrl or the history join leaked (xl_sections, reg_sections, avg_size,
      # total_enrl, waiting, avail, campus, fill_rate_mean, the fill_hist list-columns)
      # is dropped here.
      display_order <- c(
        "term", "college", "subject_course", "course_title", "part_term",
        "enrolled_census", "capacity", "sections",
        "fill_rate", "fill_trend", "sd_above_mean", "n_chronic_terms", "n_hist_terms",
        "enrolled", "fill_rate_final"
      )
      df <- df[, intersect(display_order, names(df)), drop = FALSE]

      sat_col_defs <- list(
        enrolled        = reactable::colDef(show = FALSE),
        fill_rate_final = reactable::colDef(show = FALSE),
        subject_course  = reactable::colDef(name = "Course", minWidth = 82,
          cell = function(v) htmltools::span(class = "fw-semibold", v)),
        course_title    = reactable::colDef(name = "Title", minWidth = 150,
          cell = function(v) if (!is.na(v)) htmltools::span(class = "text-sub", v) else ""),
        college         = reactable::colDef(name = "College", maxWidth = 64, align = "center"),
        part_term       = cedar_pot_coldef(),
        term            = reactable::colDef(name = "Term", maxWidth = 64, align = "center"),
        enrolled_census = reactable::colDef(name = "Enr", maxWidth = 56, align = "right"),
        capacity        = reactable::colDef(name = "Cap", maxWidth = 56, align = "right"),
        sections        = reactable::colDef(name = "Sects", maxWidth = 58, align = "right"),
        # Census headcount and its fill are the headline. Final fill is folded into the
        # same cell: the bar carries a ▾N melt chip when a course sheds students after
        # census, and hovering shows the final end-of-term fill. The cell closes over
        # `df` so it can read final/melt for this row by index.
        fill_rate       = reactable::colDef(name = "Census Fill", minWidth = 140, maxWidth = 178,
          align = "left",
          cell = function(value, index) {
            if (is.na(value)) return("")
            final <- if ("fill_rate_final" %in% names(df)) df$fill_rate_final[index] else NA_real_
            melt  <- if (all(c("enrolled_census", "enrolled") %in% names(df)))
                       df$enrolled_census[index] - df$enrolled[index] else NA_real_
            final_txt <- if (!is.na(final))
              paste0("Final fill ", round(final * 100), "% (after late drops)")
            else "No final-fill data"
            htmltools::div(
              title = final_txt,
              style = "display:flex;align-items:center;gap:6px",
              fill_bar(value),
              if (!is.na(melt) && melt >= 5)
                htmltools::span(
                  title = paste0(melt, " students drop after census (melt)"),
                  style = paste0("font-size:0.72rem;color:#7A5010;font-weight:600;",
                                 "white-space:nowrap;background:#F4E9D2;border-radius:8px;padding:0 6px"),
                  paste0("▾", melt))
              else NULL
            )
          }),
        fill_trend      = reactable::colDef(name = "Fill Trend", minWidth = 108, maxWidth = 150,
          align = "left", html = TRUE),
        sd_above_mean   = reactable::colDef(name = "SDs Hist", maxWidth = 78, align = "right",
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
      df <- filter_downstream_by_dept(signals$downstream, data$opt$dept, sections)
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
